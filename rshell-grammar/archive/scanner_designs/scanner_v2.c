/**
 * RShell Scanner V2 - Dual Grammar Architecture
 * 
 * Simplified scanner for dual grammar system:
 * - Emits mode tokens only at line boundaries when mode changes
 * - No complex state tracking (grammar handles blocks)
 * - Fixed infinite loop issues in lookahead
 * - Clear separation: line-level mode vs inline transitions
 */

#include <tree_sitter/parser.h>
#include <wctype.h>
#include <string.h>
#include <stdbool.h>
#include <stdio.h>

// Token types (must match grammar externals order)
enum TokenType {
  CMD_START,       // 0: Entering CMD mode
  CMD_END,         // 1: Exiting CMD mode
  EXPR_START,      // 2: Entering EXPR mode
  EXPR_END,        // 3: Exiting EXPR mode
  ERROR_IN_CMD,    // 4: Syntax error in CMD mode
  ERROR_IN_EXPR,   // 5: Syntax error in EXPR mode
};

typedef enum {
  MODE_UNINIT,  // Initial state
  MODE_CMD,
  MODE_EXPR
} Mode;

typedef struct {
  Mode current_mode;      // Current line's mode
  bool at_line_start;     // Are we at column 0?
  
  // Block depth tracking for nested contexts
  int expr_block_depth;   // How many EXPR blocks deep (for {...})
  int cmd_block_depth;    // How many CMD blocks deep (for $rsh())
  
  // Lookahead buffer for pattern detection
  char lookahead_buffer[32];
  int lookahead_len;
} Scanner;

// ===== LIFECYCLE FUNCTIONS =====

void *tree_sitter_rshell_external_scanner_create() {
  Scanner *scanner = (Scanner *)calloc(1, sizeof(Scanner));
  scanner->current_mode = MODE_UNINIT;
  scanner->at_line_start = true;
  scanner->expr_block_depth = 0;
  scanner->cmd_block_depth = 0;
  scanner->lookahead_len = 0;
  return scanner;
}

void tree_sitter_rshell_external_scanner_destroy(void *payload) {
  free(payload);
}

unsigned tree_sitter_rshell_external_scanner_serialize(void *payload, char *buffer) {
  Scanner *scanner = (Scanner *)payload;
  
  buffer[0] = (char)scanner->current_mode;
  buffer[1] = scanner->at_line_start ? 1 : 0;
  buffer[2] = (char)scanner->expr_block_depth;
  buffer[3] = (char)scanner->cmd_block_depth;
  
  return 4;
}

void tree_sitter_rshell_external_scanner_deserialize(void *payload, const char *buffer, unsigned length) {
  Scanner *scanner = (Scanner *)payload;
  
  if (length >= 4) {
    scanner->current_mode = (Mode)buffer[0];
    scanner->at_line_start = buffer[1] != 0;
    scanner->expr_block_depth = (int)buffer[2];
    scanner->cmd_block_depth = (int)buffer[3];
  } else {
    scanner->current_mode = MODE_UNINIT;
    scanner->at_line_start = true;
    scanner->expr_block_depth = 0;
    scanner->cmd_block_depth = 0;
  }
  
  scanner->lookahead_len = 0;
}

// ===== HELPER FUNCTIONS =====

// Table of EXPR mode keywords
static const char *EXPR_KEYWORDS[] = {
  "if", "for", "while", "return", "elif", "else", "break", "continue", NULL
};

// Check if string starts with an EXPR keyword
static bool is_keyword(const char *str, int len) {
  if (len < 2) return false;
  
  for (int i = 0; EXPR_KEYWORDS[i] != NULL; i++) {
    int kw_len = strlen(EXPR_KEYWORDS[i]);
    
    if (len >= kw_len && 
        strncmp(str, EXPR_KEYWORDS[i], kw_len) == 0 &&
        (len == kw_len || !isalnum(str[kw_len]))) {
      return true;
    }
  }
  
  return false;
}

// Check if string contains an assignment pattern
static bool is_assignment(const char *str, int len) {
  if (len < 2) return false;
  
  // Must start with identifier character
  if (!isalpha(str[0]) && str[0] != '_') return false;
  
  // Look for = operator
  for (int i = 1; i < len; i++) {
    if (str[i] == '=') {
      // Simple assignment: X = 
      if (i > 0 && (isalnum(str[i-1]) || str[i-1] == '_')) {
        return true;
      }
      // Compound assignment: X += , X -= , etc.
      if (i > 1 && (str[i-1] == '+' || str[i-1] == '-' || 
                     str[i-1] == '*' || str[i-1] == '/')) {
        return true;
      }
    }
    
    // Still in identifier
    if (isalnum(str[i]) || str[i] == '_') continue;
    
    // Hit space - might be "X ="
    if (str[i] == ' ' || str[i] == '\t') continue;
    
    // Hit something else - stop looking
    break;
  }
  
  return false;
}

// Peek ahead into buffer without consuming (FIXED: no infinite loop)
static bool peek_ahead_buffer(TSLexer *lexer, Scanner *scanner, int max_chars) {
  scanner->lookahead_len = 0;
  
  // Mark current position - ensures zero-width token
  lexer->mark_end(lexer);
  
  int32_t ch = lexer->lookahead;
  int count = 0;
  
  // Skip leading whitespace
  while ((ch == ' ' || ch == '\t') && count < max_chars) {
    lexer->advance(lexer, true);  // Skip as whitespace
    ch = lexer->lookahead;
    count++;
  }
  
  // Collect pattern characters up to delimiter
  while (ch != 0 && ch != '\n' && ch != '\r' && 
         scanner->lookahead_len < 31 && count < max_chars) {
    
    // Check if we hit a delimiter BEFORE storing
    bool is_delimiter = (ch == ' ' || ch == '\t' || ch == '=' || 
                         ch == '+' || ch == '-' || ch == '*' || ch == '/' ||
                         ch == '(' || ch == '{' || ch == ';');
    
    // Store character if ASCII
    if (ch < 128) {
      scanner->lookahead_buffer[scanner->lookahead_len++] = (char)ch;
    }
    
    // If delimiter, stop AFTER storing it
    if (is_delimiter) {
      break;
    }
    
    // Advance to next character
    lexer->advance(lexer, false);
    ch = lexer->lookahead;
    count++;
  }
  
  scanner->lookahead_buffer[scanner->lookahead_len] = '\0';
  return scanner->lookahead_len > 0;
}

// ===== MAIN SCAN FUNCTION =====

bool tree_sitter_rshell_external_scanner_scan(
    void *payload, 
    TSLexer *lexer, 
    const bool *valid_symbols) {
  
  Scanner *scanner = (Scanner *)payload;
  
  // === PART 1: Line Start Detection ===
  
  // Set line start flag when at column 0
  if (lexer->get_column(lexer) == 0) {
    scanner->at_line_start = true;
  }
  
  if (scanner->at_line_start) {
    // Skip leading whitespace
    while (lexer->lookahead == ' ' || lexer->lookahead == '\t') {
      lexer->advance(lexer, true);
    }
    
    // Skip comment lines and empty lines
    if (lexer->lookahead == '#' || 
        lexer->lookahead == '\n' || 
        lexer->lookahead == '\r' ||
        lexer->lookahead == 0) {
      return false;
    }
    
    // Peek ahead to determine mode
    if (!peek_ahead_buffer(lexer, scanner, 20)) {
      return false;
    }
    
    // Determine mode based on lookahead
    bool is_expr = is_keyword(scanner->lookahead_buffer, scanner->lookahead_len) ||
                   is_assignment(scanner->lookahead_buffer, scanner->lookahead_len);
    
    Mode new_mode = is_expr ? MODE_EXPR : MODE_CMD;
    
    // Emit token ONLY if mode changed OR first line
    if (new_mode != scanner->current_mode || scanner->current_mode == MODE_UNINIT) {
      scanner->current_mode = new_mode;
      scanner->at_line_start = false;
      
      if (new_mode == MODE_EXPR && valid_symbols[EXPR_START]) {
        lexer->result_symbol = EXPR_START;
        return true;
      } else if (new_mode == MODE_CMD && valid_symbols[CMD_START]) {
        lexer->result_symbol = CMD_START;
        return true;
      }
    }
    
    scanner->at_line_start = false;
  }
  
  // === PART 2: Block Depth Tracking ===
  
  // Track { for EXPR blocks
  if (lexer->lookahead == '{' && scanner->current_mode == MODE_EXPR) {
    scanner->expr_block_depth++;
  }
  
  // Track } for EXPR blocks
  if (lexer->lookahead == '}' && scanner->expr_block_depth > 0) {
    scanner->expr_block_depth--;
  }
  
  // === PART 3: Inline Transition Detection ===
  
  // Check for $rsh( - CMD execution in EXPR
  if (lexer->lookahead == '$') {
    lexer->mark_end(lexer);
    lexer->advance(lexer, false);
    
    // Check for ${
    if (lexer->lookahead == '{' && valid_symbols[EXPR_START]) {
      lexer->result_symbol = EXPR_START;
      return true;
    }
    
    // Check for $rsh(
    if (lexer->lookahead == 'r') {
      lexer->advance(lexer, false);
      if (lexer->lookahead == 's') {
        lexer->advance(lexer, false);
        if (lexer->lookahead == 'h') {
          lexer->advance(lexer, false);
          if (lexer->lookahead == '(' && valid_symbols[CMD_START]) {
            scanner->cmd_block_depth++;
            lexer->result_symbol = CMD_START;
            return true;
          }
        }
      }
    }
  }
  
  // Track closing ) for $rsh()
  if (lexer->lookahead == ')' && scanner->cmd_block_depth > 0) {
    scanner->cmd_block_depth--;
  }
  
  return false;
}