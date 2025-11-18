#include <tree_sitter/parser.h>
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
  Mode last_emitted_mode;  // Track what mode we last emitted
  bool has_emitted;        // Have we emitted any mode token yet?
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
  scanner->last_emitted_mode = MODE_CMD;  // Default starting mode
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

// Check if line starts with EXPR mode indicator
static bool is_expr_line_start(TSLexer *lexer) {
  // Skip whitespace
  while (lexer->lookahead == ' ' || lexer->lookahead == '\t') {
    lexer->advance(lexer, true);
  }
  
  // Ignore comments
  if (lexer->lookahead == '#') {
    return false;  // Comments don't trigger mode change
  }
  
  // Check for keywords
  if (lexer->lookahead == 'i') {  // if
    lexer->advance(lexer, false);
    if (lexer->lookahead == 'f' && !iswalnum(lexer->lookahead)) {
      return true;
    }
  } else if (lexer->lookahead == 'f') {  // for
    lexer->advance(lexer, false);
    if (lexer->lookahead == 'o') {
      lexer->advance(lexer, false);
      if (lexer->lookahead == 'r' && !iswalnum(lexer->lookahead)) {
        return true;
      }
    }
  } else if (lexer->lookahead == 'w') {  // while
    lexer->advance(lexer, false);
    if (lexer->lookahead == 'h') {
      lexer->advance(lexer, false);
      if (lexer->lookahead == 'i') {
        lexer->advance(lexer, false);
        if (lexer->lookahead == 'l') {
          lexer->advance(lexer, false);
          if (lexer->lookahead == 'e' && !iswalnum(lexer->lookahead)) {
            return true;
          }
        }
      }
    }
  } else if (lexer->lookahead == 'r') {  // return
    lexer->advance(lexer, false);
    if (lexer->lookahead == 'e') {
      lexer->advance(lexer, false);
      if (lexer->lookahead == 't') {
        lexer->advance(lexer, false);
        if (lexer->lookahead == 'u') {
          lexer->advance(lexer, false);
          if (lexer->lookahead == 'r') {
            lexer->advance(lexer, false);
            if (lexer->lookahead == 'n' && !iswalnum(lexer->lookahead)) {
              return true;
            }
          }
        }
      }
    }
  }
  
  // Check for assignment pattern: IDENTIFIER =
  if (iswalpha(lexer->lookahead) || lexer->lookahead == '_') {
    while (iswalnum(lexer->lookahead) || lexer->lookahead == '_') {
      lexer->advance(lexer, false);
    }
    // Skip whitespace
    while (lexer->lookahead == ' ' || lexer->lookahead == '\t') {
      lexer->advance(lexer, true);
    }
    // Check for = (assignment operators)
    if (lexer->lookahead == '=' || 
        lexer->lookahead == '+' || lexer->lookahead == '-' || 
        lexer->lookahead == '*' || lexer->lookahead == '/') {
      return true;
    }
  }
  
  return false;
}

bool tree_sitter_rshell_external_scanner_scan(void *payload, TSLexer *lexer, const bool *valid_symbols) {
  Scanner *scanner = (Scanner *)payload;
  
  // At start of input or line, detect mode
  if (lexer->get_column(lexer) == 0 || !scanner->has_emitted) {
    // Skip whitespace
    while (lexer->lookahead == ' ' || lexer->lookahead == '\t') {
      lexer->advance(lexer, true);
    }
    
    // Skip comment lines entirely - they're in extras and handled by grammar
    if (lexer->lookahead == '#') {
      return false;  // Let grammar handle the comment
    }
    
    // Skip empty lines
    if (lexer->lookahead == '\n' || lexer->lookahead == '\r') {
      return false;
    }
    
    lexer->mark_end(lexer);
    Mode new_mode = is_expr_line_start(lexer) ? MODE_EXPR : MODE_CMD;
    
    // Only emit if mode changed or first time
    if (!scanner->has_emitted || new_mode != scanner->last_emitted_mode) {
      if (new_mode == MODE_EXPR && valid_symbols[EXPR_START]) {
        push_mode(scanner, MODE_EXPR);
        scanner->last_emitted_mode = MODE_EXPR;
        scanner->has_emitted = true;
        lexer->result_symbol = EXPR_START;
        return true;
      } else if (new_mode == MODE_CMD && valid_symbols[CMD_START]) {
        push_mode(scanner, MODE_CMD);
        scanner->last_emitted_mode = MODE_CMD;
        scanner->has_emitted = true;
        lexer->result_symbol = CMD_START;
        return true;
      }
    }
  }
  
  // Check for $rsh( - EXPR mode command execution
  if (lexer->lookahead == '$') {
    lexer->mark_end(lexer);
    lexer->advance(lexer, false);
    
    if (lexer->lookahead == 'r') {
      lexer->advance(lexer, false);
      if (lexer->lookahead == 's') {
        lexer->advance(lexer, false);
        if (lexer->lookahead == 'h') {
          lexer->advance(lexer, false);
          if (lexer->lookahead == '(') {
            if (valid_symbols[CMD_START]) {
              lexer->advance(lexer, false);
              push_mode(scanner, MODE_CMD);
              scanner->last_emitted_mode = MODE_CMD;
              lexer->result_symbol = CMD_START;
              return true;
            }
          }
        }
      }
    }
    // Check for ${ - CMD mode expression interpolation
    else if (lexer->lookahead == '{') {
      if (valid_symbols[EXPR_START]) {
        lexer->advance(lexer, false);
        push_mode(scanner, MODE_EXPR);
        scanner->last_emitted_mode = MODE_EXPR;
        lexer->result_symbol = EXPR_START;
        return true;
      }
    }
  }
  
  // Check for closing ) that ends CMD mode from $rsh()
  if (lexer->lookahead == ')') {
    if (scanner->mode_depth > 0 && valid_symbols[CMD_END]) {
      lexer->advance(lexer, false);
      pop_mode(scanner);
      scanner->last_emitted_mode = current_mode(scanner);
      lexer->result_symbol = CMD_END;
      return true;
    }
  }
  
  // Check for closing } that ends EXPR mode from ${}
  if (lexer->lookahead == '}') {
    if (scanner->mode_depth > 0 && valid_symbols[EXPR_END]) {
      lexer->advance(lexer, false);
      pop_mode(scanner);
      scanner->last_emitted_mode = current_mode(scanner);
      lexer->result_symbol = EXPR_END;
      return true;
    }
  }
  
  return false;
}