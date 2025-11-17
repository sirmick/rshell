#!/bin/bash
# Test RShell grammar using tree-sitter parse

set -e

GRAMMAR_DIR="vendor/tree-sitter-rshell"

echo "🧪 RShell Grammar Test Suite"
echo "=============================================="

# Test helper function
test_parse() {
    local name="$1"
    local code="$2"
    local expect="$3"
    
    echo "Testing: $name"
    echo "  Code: $code"
    
    # Create temp file
    tmpfile=$(mktemp)
    echo "$code" > "$tmpfile"
    
    # Parse with tree-sitter
    output=$(cd "$GRAMMAR_DIR" && tree-sitter parse "$tmpfile" 2>&1)
    
    # Check if expected node types are in output
    if echo "$output" | grep -q "$expect"; then
        echo "  ✅ PASS - Found '$expect'"
    else
        echo "  ❌ FAIL - Missing '$expect'"
        echo "  Output:"
        echo "$output" | head -20
        rm "$tmpfile"
        return 1
    fi
    
    rm "$tmpfile"
    echo ""
}

# Run tests
test_parse "Boolean literal (true)" "X = true" "boolean_literal"
test_parse "Boolean literal (false)" "Y = false" "boolean_literal"
test_parse "List literal" "L = [1, 2, 3]" "list_literal"
test_parse "Map literal" 'M = {"key": "value"}' "map_literal"
test_parse "RShell assignment" "X = true" "rshell_assignment"

echo "=============================================="
echo "✅ All tests passed!"