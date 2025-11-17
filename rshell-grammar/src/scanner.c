#include <tree_sitter/parser.h>
#include <wctype.h>
#include <string.h>
#include <stdlib.h>
#include <stdbool.h>

// Token types MUST match order in grammar's externals
enum TokenType {
  NEWLINE,          // 0
  LINE_START,       // 1 - generic line start (mode unchanged)
  EXPR_LINE_START,  // 2 - expression mode line start (mode change)
  CMD_LINE_START,   // 3 - command mode line start (mode change)
};

// Scanner state - persisted between calls
typedef struct {
  bool at_line_start;      // Are we at the start of a line?
  bool last_mode_was_expr; // Track previous line's mode
  bool has_emitted_mode;   // Have we emitted initial mode?
} Scanner;

// Create scanner
void *tree_sitter_rshell_external_scanner_create() {
  Scanner *scanner = malloc(sizeof(Scanner));
  scanner->at_line_start = true;        // File starts at line start
  scanner->last_mode_was_expr = false;  // Default to CMD mode
  scanner->has_emitted_mode = false;    // Haven't emitted yet
  return scanner;
}

// Destroy scanner
void tree_sitter_rshell_external_scanner_destroy(void *payload) {
  Scanner *scanner = (Scanner *)payload;
  free(scanner);
}

// Serialize state (for incremental parsing)
unsigned tree_sitter_rshell_external_scanner_serialize(
  void *payload,
  char *buffer
) {
  Scanner *scanner = (Scanner *)payload;
  buffer[0] = scanner->at_line_start ? 1 : 0;
  buffer[1] = scanner->last_mode_was_expr ? 1 : 0;
  buffer[2] = scanner->has_emitted_mode ? 1 : 0;
  return 3;  // We wrote 3 bytes
}

// Deserialize state
void tree_sitter_rshell_external_scanner_deserialize(
  void *payload,
  const char *buffer,
  unsigned length
) {
  Scanner *scanner = (Scanner *)payload;
  if (length >= 3) {
    scanner->at_line_start = (buffer[0] == 1);
    scanner->last_mode_was_expr = (buffer[1] == 1);
    scanner->has_emitted_mode = (buffer[2] == 1);
  } else if (length > 0) {
    scanner->at_line_start = (buffer[0] == 1);
    scanner->last_mode_was_expr = false;
    scanner->has_emitted_mode = false;
  } else {
    scanner->at_line_start = true;
    scanner->last_mode_was_expr = false;
    scanner->has_emitted_mode = false;
  }
}

// Helper: Check if character is identifier continuation
static bool is_identifier_cont(int32_t c) {
  return iswalnum(c) || c == '_';
}

// Helper: Check if identifier is a reserved keyword
static bool is_reserved_keyword(const char *word, size_t len) {
  // Reserved keywords for expression mode
  const char *keywords[] = {"if", "elif", "else", "for", "while", "return", "continue", "break", "yield"};
  
  for (size_t i = 0; i < sizeof(keywords) / sizeof(keywords[0]); i++) {
    if (strlen(keywords[i]) == len && memcmp(word, keywords[i], len) == 0) {
      return true;
    }
  }
  return false;
}

// Main scan function
bool tree_sitter_rshell_external_scanner_scan(
  void *payload,
  TSLexer *lexer,
  const bool *valid_symbols
) {
  Scanner *scanner = (Scanner *)payload;
  
  // Check if we should emit a line start token
  if (scanner->at_line_start &&
      (valid_symbols[LINE_START] || valid_symbols[EXPR_LINE_START] || valid_symbols[CMD_LINE_START])) {
    
    // Mark end BEFORE any lookahead
    lexer->mark_end(lexer);
    
    // Skip leading whitespace
    while (lexer->lookahead == ' ' || lexer->lookahead == '\t') {
      lexer->advance(lexer, true);
    }
    
    // Default: CMD mode unless we find EXPR patterns
    bool is_expr_mode = false;
    
    int32_t first_char = lexer->lookahead;
    
    // Block close → EXPR mode
    if (first_char == '}') {
      is_expr_mode = true;
    }
    // Identifier: check for EXPR patterns
    else if (is_identifier_cont(first_char)) {
      // Read identifier into buffer
      char word_buf[32];
      size_t word_len = 0;
      
      while (is_identifier_cont(lexer->lookahead) && word_len < 31) {
        word_buf[word_len++] = (char)lexer->lookahead;
        lexer->advance(lexer, false);
      }
      word_buf[word_len] = '\0';
      
      // Check if it's a reserved keyword
      if (is_reserved_keyword(word_buf, word_len)) {
        is_expr_mode = true;  // Keywords are EXPR mode
      } else {
        // Not a keyword - check what follows after optional whitespace
        // Skip whitespace
        while (lexer->lookahead == ' ' || lexer->lookahead == '\t') {
          lexer->advance(lexer, true);
        }
        
        int32_t next_char = lexer->lookahead;
        
        // EXPR mode patterns after identifier:
        // - = (assignment)
        // - . (property access)
        // - ( (function call)
        // - += -= *= /= %= (compound assignment)
        
        if (next_char == '=' || next_char == '.' || next_char == '(') {
          is_expr_mode = true;
        } else if (next_char == '+' || next_char == '-' || 
                   next_char == '*' || next_char == '/' || next_char == '%') {
          // Check for compound assignment
          lexer->advance(lexer, false);
          if (lexer->lookahead == '=') {
            is_expr_mode = true;
          }
        }
        // Otherwise CMD mode
      }
    }
    // Everything else (paths, symbols, etc.) → CMD mode
    
    // Determine which token to emit:
    // 1. First line OR mode changed → emit specific mode token (EXPR_LINE_START or CMD_LINE_START)
    // 2. Mode didn't change → emit generic LINE_START
    bool mode_changed = (scanner->has_emitted_mode &&
                        is_expr_mode != scanner->last_mode_was_expr);
    
    enum TokenType token_type;
    if (!scanner->has_emitted_mode || mode_changed) {
      // First line or mode change - emit specific mode token
      token_type = is_expr_mode ? EXPR_LINE_START : CMD_LINE_START;
    } else {
      // Mode unchanged - emit generic line start
      token_type = LINE_START;
    }
    
    if (valid_symbols[token_type]) {
      scanner->at_line_start = false;
      scanner->last_mode_was_expr = is_expr_mode;
      scanner->has_emitted_mode = true;
      lexer->result_symbol = token_type;
      return true;
    }
  }
  
  // Check if NEWLINE is valid here
  if (valid_symbols[NEWLINE]) {
    // Skip whitespace (but not newlines)
    while (lexer->lookahead == ' ' || lexer->lookahead == '\t') {
      lexer->advance(lexer, true);
    }
    
    // Found a newline!
    if (lexer->lookahead == '\n') {
      lexer->advance(lexer, false);  // Consume it
      scanner->at_line_start = true;  // Next token is at line start
      lexer->result_symbol = NEWLINE;
      lexer->mark_end(lexer);
      return true;
    }
    
    // Also handle semicolons as statement terminators
    if (lexer->lookahead == ';') {
      lexer->advance(lexer, false);
      scanner->at_line_start = true;  // Semicolon starts new statement
      lexer->result_symbol = NEWLINE;
      lexer->mark_end(lexer);
      return true;
    }
  }
  
  return false;  // No external token matched
}