#!/usr/bin/env python3
"""
Test suite for RShell tree-sitter grammar.

This script tests that the RShell grammar correctly recognizes RShell-specific
syntax constructs like list literals, map literals, boolean literals, and
RShell assignments.

Requirements:
    pip install tree-sitter

Usage:
    python test_rshell_grammar.py
    python test_rshell_grammar.py --verbose
    python test_rshell_grammar.py --test "X = true"
"""

import argparse
import sys
import subprocess
from pathlib import Path

# Import tree_sitter bindings
try:
    from tree_sitter import Language, Parser
except ImportError:
    print("Error: tree-sitter not installed. Run: pip install tree-sitter")
    sys.exit(1)

# Paths
GRAMMAR_DIR = Path(__file__).parent / "vendor" / "tree-sitter-rshell"
BUILD_DIR = Path(__file__).parent / "build"


def build_grammar():
    """Build the RShell grammar using tree-sitter CLI."""
    print("🔨 Building RShell grammar...")
    
    # Ensure grammar is generated
    result = subprocess.run(
        ["tree-sitter", "generate"],
        cwd=str(GRAMMAR_DIR),
        capture_output=True,
        text=True
    )
    
    if result.returncode != 0:
        print(f"Error generating grammar: {result.stderr}")
        sys.exit(1)
    
    # Build the library
    BUILD_DIR.mkdir(exist_ok=True)
    result = subprocess.run(
        ["tree-sitter", "build", "--output", str(BUILD_DIR / "rshell.so")],
        cwd=str(GRAMMAR_DIR),
        capture_output=True,
        text=True
    )
    
    if result.returncode != 0:
        print(f"Error building grammar: {result.stderr}")
        sys.exit(1)
    
    print("✓ Grammar built successfully\n")


def load_grammar():
    """Load the compiled RShell grammar."""
    grammar_path = BUILD_DIR / "rshell.so"
    
    if not grammar_path.exists():
        build_grammar()
    
    # Load the built library
    return Language(str(grammar_path), "rshell")


def parse_code(code, language):
    """Parse RShell code and return the syntax tree."""
    parser = Parser()
    parser.set_language(language)
    return parser.parse(bytes(code, "utf8"))


def extract_node_types(node, types=None):
    """Recursively extract all node types from the syntax tree."""
    if types is None:
        types = set()
    
    types.add(node.type)
    for child in node.children:
        extract_node_types(child, types)
    
    return types


def print_tree(node, indent=0, verbose=False):
    """Pretty print the syntax tree."""
    if node.type == "program":
        # Skip program node, show children directly
        for child in node.children:
            print_tree(child, indent, verbose)
    else:
        prefix = "  " * indent
        text_repr = f" '{node.text.decode('utf8')}'" if verbose and node.child_count == 0 else ""
        print(f"{prefix}({node.type}{text_repr}")
        
        for child in node.children:
            print_tree(child, indent + 1, verbose)
        
        print(f"{prefix})")


# Test cases
TEST_CASES = [
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
        "name": "Map literal (simple)",
        "code": 'M = {"key": "value"}',
        "expect": ["map_literal", "map_entry", "rshell_assignment"],
    },
    {
        "name": "Map literal (multiple entries)",
        "code": 'M = {"name": "test", "port": 8080}',
        "expect": ["map_literal", "map_entry", "rshell_assignment"],
    },
    {
        "name": "Mixed: list with maps",
        "code": 'X = [{"id": 1}, {"id": 2}]',
        "expect": ["list_literal", "map_literal", "map_entry", "rshell_assignment"],
    },
    {
        "name": "RShell expression (addition)",
        "code": "R = 5 + 3",
        "expect": ["rshell_assignment"],
    },
]


def run_test(test_case, language, verbose=False):
    """Run a single test case."""
    name = test_case["name"]
    code = test_case["code"]
    expected_nodes = test_case["expect"]
    
    print(f"Testing: {name}")
    print(f"  Code: {code}")
    
    tree = parse_code(code, language)
    
    if tree.root_node.has_error:
        print(f"  ❌ FAIL - Parse error detected")
        if verbose:
            print("\n  Syntax tree:")
            print_tree(tree.root_node, 2, verbose)
        return False
    
    found_nodes = extract_node_types(tree.root_node)
    missing_nodes = set(expected_nodes) - found_nodes
    
    if missing_nodes:
        print(f"  ❌ FAIL - Missing node types: {sorted(missing_nodes)}")
        print(f"  Found node types: {sorted(found_nodes)}")
        if verbose:
            print("\n  Syntax tree:")
            print_tree(tree.root_node, 2, verbose)
        return False
    
    print(f"  ✅ PASS - Found all expected nodes: {expected_nodes}")
    if verbose:
        print("\n  Syntax tree:")
        print_tree(tree.root_node, 2, verbose)
    print()
    
    return True


def run_all_tests(verbose=False):
    """Run all test cases."""
    print("🧪 RShell Grammar Test Suite")
    print("=" * 50)
    print(f"Grammar: {GRAMMAR_DIR}")
    print(f"Test cases: {len(TEST_CASES)}\n")
    
    language = load_grammar()
    
    results = [run_test(test, language, verbose) for test in TEST_CASES]
    
    passed = sum(results)
    failed = len(results) - passed
    
    print("=" * 50)
    print("Test Results:")
    print(f"  ✅ Passed: {passed}")
    print(f"  ❌ Failed: {failed}")
    print(f"  📊 Total:  {len(results)}")
    
    return failed == 0


def main():
    parser = argparse.ArgumentParser(description="Test RShell tree-sitter grammar")
    parser.add_argument("--verbose", "-v", action="store_true", help="Show detailed output")
    parser.add_argument("--test", "-t", type=str, help="Test a specific code snippet")
    parser.add_argument("--rebuild", "-r", action="store_true", help="Force rebuild grammar")
    
    args = parser.parse_args()
    
    if args.rebuild or not (BUILD_DIR / "rshell.so").exists():
        build_grammar()
    
    if args.test:
        # Test a specific code snippet
        language = load_grammar()
        print(f"Testing: {args.test}\n")
        tree = parse_code(args.test, language)
        
        if tree.root_node.has_error:
            print("❌ Parse error detected")
        else:
            print("✓ Parse successful")
        
        print("\nSyntax tree:")
        print_tree(tree.root_node, verbose=args.verbose)
        
        print("\nNode types found:")
        for node_type in sorted(extract_node_types(tree.root_node)):
            print(f"  - {node_type}")
    else:
        # Run all tests
        success = run_all_tests(args.verbose)
        sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()