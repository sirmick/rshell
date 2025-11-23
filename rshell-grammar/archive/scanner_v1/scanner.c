i#include <tree_sitter/parser.h>
#include <wctype.h>
#include <string.h>
#include <stdbool.h>
#include <stdio.h>

enum TokenType {
  CMD_START,       // 0: Entering CMD mode
  CMD_END,         // 1: Exiting CMD mode
  EXPR_START,      // 2: Entering EXPR mode
  EXPR_END,        // 3: Exiting EXPR mode
  ERROR_IN_CMD,    // 4: Syntax error in CMD mode
  ERROR_IN_EXPR,   // 5: Syntax error in EXPR mode
};

typedef enum {
  MODE_CMD,
  MODE_EXPR
} Mode;

typedef struct {
  Mode mode_stack[16];
  int mode_depth;
  Mode last_emitted_mode;
  bool has_emitted;
  
  // Add lookahead buffer for pattern matching
  char lookahead_buffer[32];
  int lookahead_len;
  bool in_lookahead;
} Scanner;

static inline void push_mode(Scanner *scanner, Mode mode) {
  if (scanner->mode_depth < 16) {
    scanner->mode_stack[scanner->mode_depth++] = mode;
  }
}

static inline void pop_mode(Scanner *scanner) {
  if (scanner->mode_depth > 0) {
    scanner->mode_depth--;
  }
}

static inline Mode current_mode(const Scanner *scanner) {
  return scanner->mode_depth > 0 ? scanner->mode_stack[scanner->mode_depth - 1] : MODE_CMD;
}

void *tree_sitter_rshell_external_scanner_create() {
  Scanner *scanner = (Scanner *)calloc(1, sizeof(Scanner));
  scanner->mode_depth = 0;
  scanner->has_emitted = false;
  scanner->last_emitted_mode = MODE_CMD;
  scanner->in_lookahead = false;
  scanner->lookahead_len = 0;
  return scanner;
}

void tree_sitter_rshell_external_scanner_destroy(void *payload) {
  free(payload);
}

unsigned tree_sitter_rshell_external_scanner_serialize(void *payload, char *buffer) {
  Scanner *scanner = (Scanner *)payload;
  if (scanner->mode_depth > 16) return 0;
  
  buffer[0] = scanner->mode_depth;
  for (int i = 0; i < scanner->mode_depth; i++) {
    buffer[i + 1] = scanner->mode_stack[i];
  }
  buffer[scanner->mode_depth + 1] = scanner->last_emitted_mode;
  buffer[scanner->mode_depth + 2] = scanner->has_emitted ? 1 : 0;
  return scanner->mode_depth + 3;
}

void tree_sitter_rshell_external_scanner_deserialize(void *payload, const char *buffer, unsigned length) {
  Scanner *scanner = (Scanner *)payload;
  scanner->in_lookahead = false;
  scanner->lookahead_len = 0;
  
  if (length > 0) {
    scanner->mode_depth = buffer[0];
    for (int i = 0; i < scanner->mode_depth && i < 16; i++) {
      scanner->mode_stack[i] = (Mode)buffer[i + 1];
    }
    if (length > scanner->mode_depth + 1) {
      scanner->last_emitted_mode = (Mode)buffer[scanner->mode_depth + 1];
    }
    if (length > scanner->mode_depth + 2) {
      scanner->has_emitted = buffer[scanner->mode_depth + 2] != 0;
    }
  }
}

// Lookahead multiple characters WITHOUT consuming
// This builds a buffer of what's ahead
static bool peek_ahead(TSLexer *lexer, Scanner *scanner, int max_chars) {
  scanner->lookahead_len = 0;
  scanner->in_lookahead = true;
  
  // Mark current position - we'll emit zero-width token
  lexer->mark_end(lexer);
  
  int32_t ch = lexer->lookahead;
  int count = 0;
  
  // Skip initial whitespace without recording
  while ((ch == ' ' || ch == '\t') && count < max_chars) {
    lexer->advance(lexer, true);  // Skip whitespace
    ch = lexer->lookahead;
    count++;
  }
  
  // Now collect non-whitespace characters
  while (ch != 0 && ch != '\n' && ch != '\r' &&
         scanner->lookahead_len < 31 && count < max_chars) {
    
    // Stop at whitespace or special chars BEFORE storing
    if (ch == ' ' || ch == '\t' || ch == '=' || ch == '+' ||
        ch == '-' || ch == '*' || ch == '/' || ch == '(' || ch == '{') {
      // Store the special character and exit
      if (ch < 128 && (ch == '=' || ch == '+' || ch == '-' || ch == '*' || ch == '/')) {
        scanner->lookahead_buffer[scanner->lookahead_len++] = (char)ch;
      }
      break;
    }
    
    // Store the character
    if (ch < 128) {
      scanner->lookahead_buffer[scanner->lookahead_len++] = (char)ch;
    }
    
    lexer->advance(lexer, false);
    ch = lexer->lookahead;
    count++;
  }
  
  scanner->lookahead_buffer[scanner->lookahead_len] = '\0';
  return scanner->lookahead_len > 0;
}

// Table of EXPR mode keywords
static const struct {
  const char *keyword;
  size_t length;
} EXPR_KEYWORDS[] = {
  {"if", 2},
  {"for", 3},
  {"while", 5},
  {"return", 6},
  {"elif", 4},
  {"else", 4},
  {"break", 5},
  {"continue", 8},
  {NULL, 0}
};

// Check if buffer starts with a keyword using table lookup
static bool starts_with_keyword(Scanner *scanner) {
  if (scanner->lookahead_len < 2) return false;
  
  const char *buf = scanner->lookahead_buffer;
  
  // Check each keyword in the table
  for (int i = 0; EXPR_KEYWORDS[i].keyword != NULL; i++) {
    size_t kw_len = EXPR_KEYWORDS[i].length;
    
    if (scanner->lookahead_len >= kw_len &&
        strncmp(buf, EXPR_KEYWORDS[i].keyword, kw_len) == 0 &&
        (scanner->lookahead_len == kw_len || !isalnum(buf[kw_len]))) {
      return true;
    }
  }
  
  return false;
}

// Check if buffer contains an assignment pattern
static bool looks_like_assignment(Scanner *scanner) {
  if (scanner->lookahead_len < 2) return false;
  
  char first = scanner->lookahead_buffer[0];
  
  // Check if starts with valid identifier char
  if (!isalpha(first) && first != '_') return false;
  
  // Look for assignment operator (=, +=, -=, *=, /=)
  for (int i = 1; i < scanner->lookahead_len; i++) {
    char ch = scanner->lookahead_buffer[i];
    
    // Found assignment operator
    if (ch == '=') {
      // Check if it's a compound assignment
      if (i > 0) {
        char prev = scanner->lookahead_buffer[i - 1];
        if (prev == '+' || prev == '-' || prev == '*' || prev == '/') {
          return true;
        }
      }
      return true;
    }
    
    // Still part of identifier
    if (isalnum(ch) || ch == '_') continue;
    
    // Hit non-identifier character without finding =
    if (ch != ' ' && ch != '\t') break;
  }
  
  return false;
}

// Check if line starts with EXPR mode indicator
static bool is_expr_line_start(TSLexer *lexer, Scanner *scanner) {
  // Use lookahead buffer to check patterns
  if (!peek_ahead(lexer, scanner, 20)) {
    return false;
  }
  
  // Check for keywords or assignments
  return starts_with_keyword(scanner) || looks_like_assignment(scanner);
}

bool tree_sitter_rshell_external_scanner_scan(void *payload, TSLexer *lexer, const bool *valid_symbols) {
  Scanner *scanner = (Scanner *)payload;
  
  // Reset lookahead state
  scanner->in_lookahead = false;
  scanner->lookahead_len = 0;
  
  // At start of line or first token
  if (lexer->get_column(lexer) == 0 || !scanner->has_emitted) {
    // Skip leading whitespace first
    while (lexer->lookahead == ' ' || lexer->lookahead == '\t') {
      lexer->advance(lexer, true);
    }
    
    // Skip comment lines
    if (lexer->lookahead == '#') {
      return false;
    }
    
    // Skip empty lines  
    if (lexer->lookahead == '\n' || lexer->lookahead == '\r' || lexer->lookahead == 0) {
      return false;
    }
    
    // Determine the mode for this line using lookahead
    Mode new_mode = is_expr_line_start(lexer, scanner) ? MODE_EXPR : MODE_CMD;
    
    // After peeking, we've consumed characters, but mark_end was called
    // so the token will be zero-width
    
    // Emit token only if mode changed or first emission
    if (!scanner->has_emitted || new_mode != scanner->last_emitted_mode) {
      if (new_mode == MODE_EXPR && valid_symbols[EXPR_START]) {
        push_mode(scanner, MODE_EXPR);
        scanner->last_emitted_mode = MODE_EXPR;
        scanner->has_emitted = true;
        lexer->result_symbol = EXPR_START;
        return true;  // Zero-width token due to mark_end
      } else if (new_mode == MODE_CMD && valid_symbols[CMD_START]) {
        push_mode(scanner, MODE_CMD);
        scanner->last_emitted_mode = MODE_CMD;
        scanner->has_emitted = true;
        lexer->result_symbol = CMD_START;
        return true;  // Zero-width token due to mark_end
      }
    }
  }
  
  // Check for inline mode transitions ($rsh and ${})
  // These don't need multi-char lookahead
  
  // Check for $rsh( or ${ patterns
  if (lexer->lookahead == '$') {
    // Build a small lookahead buffer for pattern matching
    char pattern[5] = {0};
    int pattern_len = 0;
    
    lexer->mark_end(lexer);
    lexer->advance(lexer, false);
    
    // Collect up to 4 characters after '$'
    for (int i = 0; i < 4 && lexer->lookahead != 0; i++) {
      if (lexer->lookahead < 128) {
        pattern[pattern_len++] = (char)lexer->lookahead;
      }
      
      // Check for ${
      if (pattern_len == 1 && pattern[0] == '{' && valid_symbols[EXPR_START]) {
        push_mode(scanner, MODE_EXPR);
        scanner->last_emitted_mode = MODE_EXPR;
        lexer->result_symbol = EXPR_START;
        return true;
      }
      
      // Check for $rsh(
      if (pattern_len == 4 && strncmp(pattern, "rsh(", 4) == 0 && valid_symbols[CMD_START]) {
        push_mode(scanner, MODE_CMD);
        scanner->last_emitted_mode = MODE_CMD;
        lexer->result_symbol = CMD_START;
        return true;
      }
      
      // Don't advance past what we're looking for
      if (pattern[0] != 'r' && pattern[0] != '{') break;
      if (pattern_len > 0 && pattern[0] == '{') break;
      if (pattern_len >= 4) break;
      
      lexer->advance(lexer, false);
    }
  }
  
  // Check for ) to close $rsh()
  if (lexer->lookahead == ')') {
    if (scanner->mode_depth > 0 && valid_symbols[CMD_END]) {
      lexer->mark_end(lexer);
      pop_mode(scanner);
      scanner->last_emitted_mode = current_mode(scanner);
      lexer->result_symbol = CMD_END;
      return true;
    }
  }
  
  // Check for } to close ${}
  if (lexer->lookahead == '}') {
    if (scanner->mode_depth > 0 && valid_symbols[EXPR_END]) {
      lexer->mark_end(lexer);
      pop_mode(scanner);
      scanner->last_emitted_mode = current_mode(scanner);
      lexer->result_symbol = EXPR_END;
      return true;
    }
  }
  
  return false;
}