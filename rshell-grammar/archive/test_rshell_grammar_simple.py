#!/usr/bin/env python3
"""
Simple test harness for RShell grammar using tree-sitter parse CLI.

This script executes `tree-sitter parse` and verifies the output contains
expected node types.

Usage:
    python test_rshell_grammar_simple.py
    python test_rshell_grammar_simple.py --verbose
"""

import argparse
import subprocess
import sys
from pathlib import Path

GRAMMAR_DIR = Path(__file__).parent / "vendor" / "tree-sitter-rshell"

# Test cases - From ENHANCED_SYNTAX_FINAL_DESIGN.md examples
TEST_CASES = [
    # Basic literals
    {
        "name": "Boolean literal (true)",
        "code": "X = true",
        "expect": ["boolean_literal", "rshell_assignment"],
    },
    {
        "name": "Boolean literal (false)",
        "code": "Y = false",
        "expect": ["boolean_literal", "rshell_assignment"],
    },
    {
        "name": "Number literal",
        "code": "X = 42",
        "expect": ["number", "rshell_assignment"],
    },
    {
        "name": "String literal",
        "code": 'NAME = "production"',
        "expect": ["string", "rshell_assignment"],
    },
    
    # List literals
    {
        "name": "List literal (simple)",
        "code": "L = [1, 2, 3]",
        "expect": ["list_literal", "rshell_assignment"],
    },
    {
        "name": "List literal (nested)",
        "code": "L = [[1, 2], [3, 4]]",
        "expect": ["list_literal", "rshell_assignment"],
    },
    {
        "name": "List literal (strings)",
        "code": 'SERVERS = ["web1", "web2", "db1"]',
        "expect": ["list_literal", "string", "rshell_assignment"],
    },
    
    # Map literals
    {
        "name": "Map literal (simple)",
        "code": '{"key": "value"}',
        "expect": ["map_literal", "map_entry"],
    },
    {
        "name": "Map literal (multiple entries)",
        "code": 'M = {"name": "test", "port": 8080}',
        "expect": ["map_literal", "map_entry", "rshell_assignment"],
    },
    {
        "name": "Map literal (nested)",
        "code": 'CONFIG = {"database": {"host": "localhost", "port": 5432}}',
        "expect": ["map_literal", "map_entry", "rshell_assignment"],
    },
    
    # Mixed structures
    {
        "name": "Mixed: list with maps",
        "code": 'X = [{"id": 1}, {"id": 2}]',
        "expect": ["list_literal", "map_literal", "rshell_assignment"],
    },
    {
        "name": "Server config (from ENHANCED_SYNTAX_FINAL_DESIGN.md)",
        "code": 'SERVERS = [{"name": "web1.example.com", "port": 8080, "role": "web"}]',
        "expect": ["list_literal", "map_literal", "map_entry", "rshell_assignment"],
    },
    
    # Binary expressions
    {
        "name": "Binary expression (addition)",
        "code": "X = 5 + 3",
        "expect": ["rshell_assignment", "rshell_binary_expression"],
    },
    {
        "name": "Binary expression (multiplication)",
        "code": "Y = 10 * 2",
        "expect": ["rshell_assignment", "rshell_binary_expression"],
    },
    
    # Commands (should NOT match as rshell_assignment)
    {
        "name": "Command (echo)",
        "code": "echo hello",
        "expect": ["command", "command_name"],
    },
    {
        "name": "Command with args",
        "code": 'echo "hello world"',
        "expect": ["command", "command_name", "string"],
    },
]


def parse_code(code, verbose=False):
    """Parse code using tree-sitter parse CLI."""
    import tempfile
    
    # Create temp file
    with tempfile.NamedTemporaryFile(mode='w', suffix='.sh', delete=False) as f:
        f.write(code)
        tmpfile = f.name
    
    try:
        # Run tree-sitter parse
        result = subprocess.run(
            ["tree-sitter", "parse", tmpfile],
            cwd=str(GRAMMAR_DIR),
            capture_output=True,
            text=True
        )
        
        if verbose:
            print(f"\n  📝 Input RShell code:")
            print(f"    {code}")
            print(f"\n  Tree-sitter stdout:")
            print(f"  {result.stdout}")
            print(f"\n  Tree-sitter stderr:")
            print(f"  {result.stderr}")
            print(f"\n  Return code: {result.returncode}")
        
        # Combine stdout and stderr since tree-sitter may output to either
        return result.stdout + result.stderr
    finally:
        Path(tmpfile).unlink()


def extract_node_types(output):
    """Extract node types from tree-sitter parse output."""
    import re
    # Match patterns like (node_type ...)
    matches = re.findall(r'\((\w+)', output)
    return set(matches)


def run_test(test_case, verbose=False):
    """Run a single test case."""
    name = test_case["name"]
    code = test_case["code"]
    expected = test_case["expect"]
    
    print(f"\nTesting: {name}")
    print(f"  Input: {repr(code)}")
    
    output = parse_code(code, verbose)
    
    # Always print AST in verbose mode
    if verbose and output and not output.startswith("Warning:"):
        print(f"\n  📊 Parse Tree:")
        for line in output.split('\n'):
            if line.strip() and not line.startswith("Warning:"):
                print(f"    {line}")
        print()
    
    if "ERROR" in output:
        print(f"  ❌ FAIL - Parse error detected")
        if not verbose:
            # Show error details in non-verbose mode
            for line in output.split('\n'):
                if 'ERROR' in line or line.startswith('(ERROR'):
                    print(f"    {line}")
        return False
    
    found = extract_node_types(output)
    missing = set(expected) - found
    
    if missing:
        print(f"  ❌ FAIL - Missing node types: {sorted(missing)}")
        print(f"  Found: {sorted(found)}")
        return False
    
    print(f"  ✅ PASS - Found all expected nodes")
    return True


def generate_grammar():
    """Generate the grammar before testing."""
    print("🔧 Generating grammar...")
    result = subprocess.run(
        ["tree-sitter", "generate"],
        cwd=str(GRAMMAR_DIR),
        capture_output=True,
        text=True
    )
    
    if result.returncode != 0:
        print(f"❌ Failed to generate grammar:")
        print(result.stderr)
        return False
    
    print("✅ Grammar generated successfully\n")
    return True


def main():
    parser = argparse.ArgumentParser(description="Test RShell grammar")
    parser.add_argument("--verbose", "-v", action="store_true")
    parser.add_argument("--no-generate", action="store_true", help="Skip grammar generation")
    args = parser.parse_args()
    
    print("🧪 RShell Grammar Test Suite")
    print("=" * 50)
    print(f"Grammar: {GRAMMAR_DIR}")
    print(f"Tests: {len(TEST_CASES)}\n")
    
    # Generate grammar first unless --no-generate is specified
    if not args.no_generate:
        if not generate_grammar():
            sys.exit(1)
    
    results = [run_test(test, args.verbose) for test in TEST_CASES]
    
    passed = sum(results)
    failed = len(results) - passed
    
    print("\n" + "=" * 50)
    print(f"✅ Passed: {passed}")
    print(f"❌ Failed: {failed}")
    print(f"📊 Total:  {len(results)}")
    
    sys.exit(0 if failed == 0 else 1)


if __name__ == "__main__":
    main()