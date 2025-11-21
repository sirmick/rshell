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

# Step 2: Compile Scanner (C++)
echo "[2/4] Compiling Scanner..."
mkdir -p build
g++ -std=c++20 -Wall -Wextra -I./src -c src/scanner.cc -o build/scanner.o
echo "✓ Scanner compiled"
echo ""

# Step 3: Test Scanner (C++ unit tests)
echo "[3/4] Running Scanner unit tests..."
g++ -std=c++20 -Wall -Wextra -I./src -o build/test_scanner tests/test_scanner_v2_simple.cpp src/scanner.cc
./build/test_scanner
if [ $? -ne 0 ]; then
  echo "✗ Scanner unit tests failed"
  exit 1
fi
echo "✓ Scanner unit tests passed"
echo ""

# Step 4: Run tests
echo "[4/4] Running grammar test suite..."
echo ""

# Run grammar tests
echo "--- Grammar Tests ---"
python3 tests/test_grammar.py --no-generate
echo ""

# Run scanner mode detection tests
echo "--- Scanner Mode Detection Tests ---"
python3 tests/test_scanner_mode_detection.py
echo ""

echo "=== Build Complete ==="
echo ""
echo "Summary:"
echo "  - Parser:     rshell-grammar/src/parser.c"
echo "  - Scanner:    rshell-grammar/src/scanner.cc (C++20)"
echo "  - Tests:      All passing ✓"
echo ""
echo "Next steps:"
echo "  - Parse a file:       tree-sitter parse <file.rsh>"
echo "  - Run grammar tests:  python3 tests/test_grammar.py"
echo "  - Run scanner tests:  ./build/test_scanner"
echo "  - Edit grammar:       vim grammar.js"