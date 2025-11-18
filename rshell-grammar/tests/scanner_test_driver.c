
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>
#include <stdint.h>

// Include the scanner implementation
#include "../src/scanner.c"

// Token names for output
const char* token_names[] = {
    "EXPR_LINE_START",
    "CMD_LINE_START", 
    "LINE_START",
    "CMD_EXPR_INTERP_START",    // ${
    "CMD_EXPR_INTERP_END",      // }
    "EXPR_CMD_EXEC_START",      // $rsh(
    "EXPR_CMD_EXEC_END",        // )
    "CMD_SUBSTITUTION_START",   // $(
    "CMD_SUBSTITUTION_END"      // )
};

int main(int argc, char** argv) {
    if (argc != 3) {
        fprintf(stderr, "Usage: %s <input_text> <initial_mode>\n", argv[0]);
        return 1;
    }
    
    const char* input = argv[1];
    const char* mode = argv[2];
    
    // Create scanner
    void* scanner = tree_sitter_rshell_external_scanner_create();
    
    // Set initial state based on mode
    unsigned state_size = tree_sitter_rshell_external_scanner_serialize(scanner, NULL);
    char* state_buffer = calloc(1, state_size);
    
    // For testing, we'll manually set scanner state
    // This is a simplified version - real scanner has more complex state
    if (strcmp(mode, "expr") == 0) {
        // Set EXPR mode indicator in state
        state_buffer[0] = 1;  // Assuming first byte is mode
    }
    
    tree_sitter_rshell_external_scanner_deserialize(
        scanner, state_buffer, state_size
    );
    
    // Create lexer struct
    TSLexer lexer = {
        .lookahead = input[0],
        .result_symbol = 0,
    };
    
    // Simplified token scan
    const bool* valid_symbols = calloc(9, sizeof(bool));
    for (int i = 0; i < 9; i++) {
        ((bool*)valid_symbols)[i] = true;  // All tokens potentially valid
    }
    
    bool scanned = tree_sitter_rshell_external_scanner_scan(
        scanner, &lexer, valid_symbols
    );
    
    if (scanned) {
        printf("Token: %s\n", token_names[lexer.result_symbol]);
    } else {
        printf("No token\n");
    }
    
    tree_sitter_rshell_external_scanner_destroy(scanner);
    free(state_buffer);
    
    return 0;
}
