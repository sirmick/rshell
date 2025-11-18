#!/bin/bash

# Build script for simplified RShell grammar

echo "=== Building Simplified RShell Grammar ==="

# Backup original scanner if it exists
if [ -f "src/scanner.c" ] && [ ! -f "src/scanner_original.c" ]; then
    cp src/scanner.c src/scanner_original.c
fi

# Copy the simplified scanner to be the main scanner
cp src/scanner_simple.c src/scanner.c

# Copy the simplified grammar to be the main grammar
cp grammar_simple.js grammar.js

# Generate the parser
echo "Generating parser..."
tree-sitter generate

if [ $? -ne 0 ]; then
    echo "ERROR: Failed to generate parser"
    exit 1
fi

echo "Parser generated successfully!"

# Compile and test the scanner unit tests
echo ""
echo "Testing scanner unit tests..."
gcc -o scanner_test src/scanner_test.c
if [ $? -eq 0 ]; then
    ./scanner_test
else
    echo "WARNING: Scanner unit tests failed to compile"
fi

# Run the test suite
echo ""
echo "Running grammar tests..."
python3 tests/test_grammar_simple.py

echo ""
echo "Running mode-specific syntax tests..."
python3 tests/test_mode_specific_syntax.py

echo ""
echo "Build complete!"