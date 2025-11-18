#include <tree_sitter/parser.h>
#include <wctype.h>
#include <string.h>
#include <stdbool.h>
#include <stdio.h>

enum TokenType {
  CMD_START,
  CMD_END,
  EXPR_START,
  EXPR_END,
};

typedef enum {
  MODE_CMD,
  MODE_EXPR
} Mode;

typedef struct {
  Mode mode_stack[16];
  int mode_depth;
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
  return scanner->mode_depth > 0 ? scanner->mode_stack[scanner->mode_depth - 1] : MODE_EXPR;
}

void *tree_sitter_rshell_external_scanner_create() {
  Scanner *scanner = (Scanner *)calloc(1, sizeof(Scanner));
  scanner->mode_depth = 0;
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
  return scanner->mode_depth + 1;
}

void tree_sitter_rshell_external_scanner_deserialize(void *payload, const char *buffer, unsigned length) {
  Scanner *scanner = (Scanner *)payload;
  if (length > 0) {
    scanner->mode_depth = buffer[0];
    for (int i = 0; i < scanner->mode_depth && i < 16; i++) {
      scanner->mode_stack[i] = (Mode)buffer[i + 1];
    }
  }
}

bool tree_sitter_rshell_external_scanner_scan(void *payload, TSLexer *lexer, const bool *valid_symbols) {
  Scanner *scanner = (Scanner *)payload;
  
  Mode mode = current_mode(scanner);
  
  // Look for mode-switching constructs ONLY
  // Do not skip whitespace - let the grammar handle it
  
  // Check for $rsh( - switch from EXPR to CMD
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
            // Found $rsh(
            if (valid_symbols[CMD_START]) {
              lexer->advance(lexer, false);
              push_mode(scanner, MODE_CMD);
              lexer->result_symbol = CMD_START;
              return true;
            }
          }
        }
      }
    } else if (lexer->lookahead == '{') {
      // Found ${
      if (valid_symbols[EXPR_START]) {
        lexer->advance(lexer, false);
        push_mode(scanner, MODE_EXPR);
        lexer->result_symbol = EXPR_START;
        return true;
      }
    }
  }
  
  // Check for closing ) that ends CMD mode
  if (lexer->lookahead == ')') {
    if (mode == MODE_CMD && scanner->mode_depth > 0 && valid_symbols[CMD_END]) {
      lexer->advance(lexer, false);
      pop_mode(scanner);
      lexer->result_symbol = CMD_END;
      return true;
    }
  }
  
  // Check for closing } that ends EXPR mode interpolation
  if (lexer->lookahead == '}') {
    if (mode == MODE_EXPR && scanner->mode_depth > 0 && valid_symbols[EXPR_END]) {
      lexer->advance(lexer, false);
      pop_mode(scanner);
      lexer->result_symbol = EXPR_END;
      return true;
    }
  }
  
  // Do NOT emit error tokens - let the grammar handle all other content
  return false;
}