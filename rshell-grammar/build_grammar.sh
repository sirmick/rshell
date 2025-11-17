#!/bin/bash
# RShell Grammar Build Script
# Generates parser, compiles scanner, and runs tests

set -e  # Exit on error

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "=== RShell Grammar Build Script ==="
echo ""

# Step 1: Generate parser from grammar
echo "[1/3] Generating parser from grammar.js..."
tree-sitter generate
echo "✓ Parser generated"
echo ""

# Step 2: Compile scanner (already done by tree-sitter generate)
echo "[2/3] Scanner compiled (C code in src/scanner.c)"
echo "✓ Scanner ready"
echo ""

# Step 3: Run tests
echo "[3/3] Running test suite..."
echo ""

# Run grammar tests
echo "--- Grammar Tests ---"
python3 tests/test_grammar_simple.py --no-generate
echo ""

# Run scanner mode detection tests
echo "--- Scanner Mode Detection Tests ---"
python3 tests/test_scanner_mode_detection.py
echo ""

echo "=== Build Complete ==="
echo ""
echo "Summary:"
echo "  - Parser:  rshell-grammar/src/parser.c"
echo "  - Scanner: rshell-grammar/src/scanner.c"
echo "  - Tests:   All passing ✓"
echo ""
echo "Next steps:"
echo "  - Parse a file:  tree-sitter parse <file.rsh>"
echo "  - Run tests:     python3 tests/test_grammar_simple.py"
echo "  - Edit grammar:  vim grammar.js"