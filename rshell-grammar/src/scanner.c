/**
 * RShell Scanner V3 - Clean Minimal Implementation
 * 
 * Following the tree-sitter-python pattern:
 * - Scanner only emits structural boundary tokens (NEWLINE, BLOCK_START)
 * - Grammar handles all mode detection (EXPR vs CMD)
 * - Only responds when valid_symbols[] requests tokens
 * 
 * Tokens:
 *   NEWLINE      - Line boundary (like Python)
 *   BLOCK_START  - { in EXPR mode (like Python INDENT)
 */

#include "tree_sitter/parser.h"
#include <string.h>
#include <wctype.h>

enum TokenType {
    NEWLINE,
    BLOCK_START,
};

typedef struct {
    int expr_block_depth;  // Track { } nesting in EXPR mode
} Scanner;

// ===== C API FUNCTIONS =====

void* tree_sitter_rshell_external_scanner_create() {
    Scanner* scanner = calloc(1, sizeof(Scanner));
    return scanner;
}

void tree_sitter_rshell_external_scanner_destroy(void* payload) {
    Scanner* scanner = (Scanner*)payload;
    free(scanner);
}

unsigned tree_sitter_rshell_external_scanner_serialize(
    void* payload, 
    char* buffer
) {
    Scanner* scanner = (Scanner*)payload;
    
    // Serialize expr_block_depth as 2 bytes (little-endian)
    buffer[0] = (char)(scanner->expr_block_depth & 0xFF);
    buffer[1] = (char)((scanner->expr_block_depth >> 8) & 0xFF);
    
    return 2;
}

void tree_sitter_rshell_external_scanner_deserialize(
    void* payload,
    const char* buffer,
    unsigned length
) {
    Scanner* scanner = (Scanner*)payload;
    
    // Initialize to default
    scanner->expr_block_depth = 0;
    
    // Deserialize if buffer has data
    if (length >= 2) {
        scanner->expr_block_depth = 
            (unsigned char)buffer[0] | 
            ((unsigned char)buffer[1] << 8);
    }
}

bool tree_sitter_rshell_external_scanner_scan(
    void* payload,
    TSLexer* lexer,
    const bool* valid_symbols
) {
    Scanner* scanner = (Scanner*)payload;
    
    // Skip whitespace (but NOT newlines - we want to detect those)
    while (lexer->lookahead == ' ' || 
           lexer->lookahead == '\t' || 
           lexer->lookahead == '\r') {
        lexer->advance(lexer, true);
    }
    
    // === NEWLINE TOKEN ===
    // Emit when we see a newline AND grammar wants it
    if (valid_symbols[NEWLINE] && lexer->lookahead == '\n') {
        lexer->advance(lexer, false);
        lexer->mark_end(lexer);
        lexer->result_symbol = NEWLINE;
        return true;
    }
    
    // === BLOCK_START TOKEN ===
    // Only emit when { appears and grammar wants it
    // Grammar will request this when it knows we're in EXPR mode
    if (valid_symbols[BLOCK_START] && lexer->lookahead == '{') {
        scanner->expr_block_depth++;
        lexer->advance(lexer, false);
        lexer->mark_end(lexer);
        lexer->result_symbol = BLOCK_START;
        return true;
    }
    
    // Track } for block depth (but don't emit token - grammar handles })
    if (lexer->lookahead == '}' && scanner->expr_block_depth > 0) {
        scanner->expr_block_depth--;
    }
    
    // Grammar doesn't want any tokens right now
    return false;
}