#!/usr/bin/env python3
"""
Simple test harness for RShell grammar (grammar_simple.js).

Single command to generate grammar and run tests with clear output.

Usage:
    python test_grammar_simple.py                    # Run all tests
    python test_grammar_simple.py --verbose          # Show parse trees
    python test_grammar_simple.py --filter commands  # Run specific category
    python test_grammar_simple.py --no-generate      # Skip generation
"""

import argparse
import subprocess
import sys
import signal
import time
from pathlib import Path
from typing import Set, Dict

GRAMMAR_DIR = Path(__file__).parent.parent
GRAMMAR_FILE = GRAMMAR_DIR / "grammar.js"

# Test cases organized by category
TEST_CASES = {
    "assignments": [
        {
            "name": "Simple number assignment",
            "code": "X = 42",
            "expect": ["assignment", "identifier", "number"],
        },
        {
            "name": "String assignment",
            "code": 'NAME = "production"',
            "expect": ["assignment", "string"],
        },
        {
            "name": "Boolean assignment (true)",
            "code": "DEBUG = true",
            "expect": ["assignment", "boolean"],
        },
        {
            "name": "Boolean assignment (false)",
            "code": "ENABLED = false",
            "expect": ["assignment", "boolean"],
        },
        {
            "name": "Compound assignment (+=)",
            "code": "COUNT += 1",
            "expect": ["assignment", "identifier", "number"],
        },
        {
            "name": "Compound assignment (-=)",
            "code": "VALUE -= 10",
            "expect": ["assignment", "identifier", "number"],
        },
        {
            "name": "Compound assignment (*=)",
            "code": "TOTAL *= 2",
            "expect": ["assignment", "identifier", "number"],
        },
        {
            "name": "Compound assignment (/=)",
            "code": "RESULT /= 5",
            "expect": ["assignment", "identifier", "number"],
        },
    ],
    
    "lists": [
        {
            "name": "Simple list",
            "code": "NUMS = [1, 2, 3]",
            "expect": ["assignment", "array", "number"],
        },
        {
            "name": "Nested list",
            "code": "MATRIX = [[1, 2], [3, 4]]",
            "expect": ["assignment", "array"],
        },
        {
            "name": "String list",
            "code": 'SERVERS = ["web1", "web2"]',
            "expect": ["assignment", "array", "string"],
        },
        {
            "name": "Empty list",
            "code": "ITEMS = []",
            "expect": ["assignment", "array"],
        },
    ],
    
    "maps": [
        {
            "name": "Simple map",
            "code": 'CONFIG = {"key": "value"}',
            "expect": ["assignment", "object", "object_entry", "string"],
        },
        {
            "name": "Multiple entries",
            "code": 'SERVER = {"name": "web1", "port": 8080}',
            "expect": ["assignment", "object", "object_entry"],
        },
        {
            "name": "Nested map",
            "code": 'DB = {"primary": {"host": "localhost"}}',
            "expect": ["assignment", "object", "object_entry"],
        },
        {
            "name": "Empty map",
            "code": "EMPTY = {}",
            "expect": ["assignment", "object"],
        },
    ],
    
    "commands": [
        {
            "name": "Simple command",
            "code": "ls",
            "expect": ["command", "identifier"],
        },
        {
            "name": "Command with args",
            "code": "echo hello",
            "expect": ["command", "identifier"],
        },
        {
            "name": "Command with string arg",
            "code": 'echo "hello world"',
            "expect": ["command", "string"],
        },
        {
            "name": "Command with flags",
            "code": "ls -la",
            "expect": ["command"],
        },
    ],
    
    "pipelines": [
        {
            "name": "Simple pipeline",
            "code": "ls | grep txt",
            "expect": ["pipeline", "command"],
        },
        {
            "name": "Multi-stage pipeline",
            "code": "cat file | grep pattern | wc",
            "expect": ["pipeline", "command"],
        },
    ],
    
    "variables": [
        {
            "name": "Variable reference",
            "code": "echo $HOME",
            "expect": ["command", "variable_reference"],
        },
        {
            "name": "Variable in assignment",
            "code": "Y = $X",
            "expect": ["assignment", "variable_reference"],
        },
    ],
    
    "mixed": [
        {
            "name": "List of maps",
            "code": 'SERVERS = [{"name": "web1"}, {"name": "web2"}]',
            "expect": ["assignment", "array", "object", "object_entry"],
        },
        {
            "name": "Map with list value",
            "code": 'CONFIG = {"ports": [8080, 8081]}',
            "expect": ["assignment", "object", "array", "number"],
        },
    ],
    
    # ===== PHASE 2 TESTS =====
    "property_access": [
        {
            "name": "Simple property access",
            "code": "HOST = SERVER.fqdn",
            "expect": ["assignment", "property_access"],
        },
        {
            "name": "Chained property access",
            "code": "PORT = CONFIG.database.port",
            "expect": ["assignment", "property_access", "property_chain"],
        },
        {
            "name": "Variable with property",
            "code": "VALUE = $SERVER.fqdn",
            "expect": ["assignment", "variable_reference", "property_chain"],
        },
    ],
    
    "expressions": [
        {
            "name": "Binary expression (addition)",
            "code": "SUM = 10 + 5",
            "expect": ["assignment", "binary_expression"],
        },
        {
            "name": "Binary expression (comparison)",
            "code": "CHECK = X > 10",
            "expect": ["assignment", "binary_expression"],
        },
        {
            "name": "Binary expression (logical and)",
            "code": "BOTH = A and B",
            "expect": ["assignment", "binary_expression"],
        },
        {
            "name": "Unary expression (not)",
            "code": "NEG = not TRUE",
            "expect": ["assignment", "unary_expression"],
        },
        {
            "name": "Parenthesized expression",
            "code": "CALC = (5 + 3)",
            "expect": ["assignment", "parenthesized_expression"],
        },
    ],
    
    "control_flow": [
        {
            "name": "If statement (simple)",
            "code": "if (X > 10) {\n  Y = 1\n}",
            "expect": ["if_statement", "block", "parenthesized_expression"],
        },
        {
            "name": "If-else statement",
            "code": "if (X > 10) {\n  Y = 1\n} else {\n  Y = 0\n}",
            "expect": ["if_statement", "else_clause", "block"],
        },
        {
            "name": "For loop",
            "code": "for (S in SERVERS) {\n  echo test\n}",
            "expect": ["for_statement", "block", "command"],
        },
        {
            "name": "While loop",
            "code": "while (X < 100) {\n  X += 1\n}",
            "expect": ["while_statement", "block", "assignment"],
        },
    ],
    
    "return_statements": [
        {
            "name": "Return with value",
            "code": "return 42",
            "expect": ["return_statement", "number"],
        },
        {
            "name": "Return without value",
            "code": "return",
            "expect": ["return_statement"],
        },
        {
            "name": "Return in function context",
            "code": "if (X > 0) {\n  return X\n}",
            "expect": ["if_statement", "return_statement"],
        },
    ],
    
    "loop_control": [
        {
            "name": "Continue statement",
            "code": "continue",
            "expect": ["continue_statement"],
        },
        {
            "name": "Break statement",
            "code": "break",
            "expect": ["break_statement"],
        },
        {
            "name": "Continue in loop",
            "code": "for (X in LIST) {\n  if (X > 5) {\n    continue\n  }\n}",
            "expect": ["for_statement", "if_statement", "continue_statement"],
        },
        {
            "name": "Break in loop",
            "code": "while (true) {\n  if (X > 10) {\n    break\n  }\n}",
            "expect": ["while_statement", "if_statement", "break_statement"],
        },
    ],
    
    # ===== PHASE 2 EXTENDED TESTS =====
    "nested_control_flow": [
        {
            "name": "If inside for loop",
            "code": "for (X in LIST) {\n  if (X > 5) {\n    Y = 1\n  }\n}",
            "expect": ["for_statement", "if_statement", "block", "assignment"],
        },
        {
            "name": "For inside if statement",
            "code": "if (COUNT > 0) {\n  for (ITEM in ITEMS) {\n    echo test\n  }\n}",
            "expect": ["if_statement", "for_statement", "command", "block"],
        },
        {
            "name": "While inside while",
            "code": "while (X < 10) {\n  while (Y < 5) {\n    Y += 1\n  }\n  X += 1\n}",
            "expect": ["while_statement", "assignment", "block"],
        },
        {
            "name": "If-elif-else chain",
            "code": "if (X > 10) {\n  Y = 1\n} elif (X > 5) {\n  Y = 2\n} else {\n  Y = 3\n}",
            "expect": ["if_statement", "elif_clause", "else_clause", "assignment"],
        },
    ],
    
    "complex_expressions": [
        {
            "name": "Multiple arithmetic operators",
            "code": "RESULT = 10 + 5 * 2",
            "expect": ["assignment", "binary_expression"],
        },
        {
            "name": "Nested parentheses",
            "code": "CALC = ((5 + 3) * 2)",
            "expect": ["assignment", "parenthesized_expression", "binary_expression"],
        },
        {
            "name": "Comparison in assignment",
            "code": "CHECK = X > 10",
            "expect": ["assignment", "binary_expression"],
        },
        {
            "name": "Logical AND",
            "code": "BOTH = A and B",
            "expect": ["assignment", "binary_expression"],
        },
        {
            "name": "Logical OR",
            "code": "EITHER = A or B",
            "expect": ["assignment", "binary_expression"],
        },
        {
            "name": "Combined logical",
            "code": "RESULT = (X > 5) and (Y < 10)",
            "expect": ["assignment", "binary_expression", "parenthesized_expression"],
        },
    ],
    
    "comments": [
        {
            "name": "Comment alone",
            "code": "# This is a comment",
            "expect": ["comment"],
        },
        {
            "name": "Comment after assignment",
            "code": "X = 42  # Set X to 42",
            "expect": ["assignment", "number"],
        },
        {
            "name": "Comment before command",
            "code": "# Run echo\necho hello",
            "expect": ["comment", "command"],
        },
    ],
    
    "edge_cases": [
        {
            "name": "Empty list",
            "code": "ITEMS = []",
            "expect": ["assignment", "array"],
        },
        {
            "name": "Empty map",
            "code": "CONFIG = {}",
            "expect": ["assignment", "object"],
        },
        {
            "name": "Trailing comma in list",
            "code": "L = [1, 2, 3,]",
            "expect": ["assignment", "array", "number"],
        },
        {
            "name": "Multiline list",
            "code": "SERVERS = [\n  1,\n  2,\n  3\n]",
            "expect": ["assignment", "array", "number"],
        },
        {
            "name": "Multiline map",
            "code": 'CONFIG = {\n  "host": "localhost",\n  "port": 8080\n}',
            "expect": ["assignment", "object", "object_entry", "string"],
        },
        {
            "name": "Negative numbers",
            "code": "X = -42",
            "expect": ["assignment", "number"],
        },
        {
            "name": "Floating point",
            "code": "PI = 3.14159",
            "expect": ["assignment", "number"],
        },
    ],
    
    "mixed_mode_blocks": [
        {
            "name": "Commands and assignments in if block",
            "code": "if (X > 0) {\n  Y = 1\n  echo test\n  Z = 2\n}",
            "expect": ["if_statement", "assignment", "command", "block"],
        },
        {
            "name": "Pipeline in for loop",
            "code": "for (F in FILES) {\n  cat $F | grep pattern\n}",
            "expect": ["for_statement", "pipeline", "command"],
        },
    ],
    
    "semicolons": [
        {
            "name": "Multiple assignments with semicolon",
            "code": "X = 1; Y = 2",
            "expect": ["assignment"],
        },
        {
            "name": "Assignment and command with semicolon",
            "code": "X = 42; echo done",
            "expect": ["assignment", "command"],
        },
    ],
    
    # ===== PHASE 3 TESTS: CROSS-MODE FEATURES =====
    "rsh_execution": [
        {
            "name": "Simple $rsh() call",
            "code": "result = $rsh(hostname)",
            "expect": ["assignment", "cmd_execution", "command"],
        },
        {
            "name": "$rsh() with arguments",
            "code": 'output = $rsh(echo "hello world")',
            "expect": ["assignment", "cmd_execution", "command", "string"],
        },
        {
            "name": "$rsh() with pipeline",
            "code": "files = $rsh(ls | grep txt)",
            "expect": ["assignment", "cmd_execution", "pipeline"],
        },
        {
            "name": "$rsh() with variable",
            "code": "result = $rsh(cat $FILE)",
            "expect": ["assignment", "cmd_execution", "command", "variable_reference"],
        },
        {
            "name": "$rsh() in if condition",
            "code": "if ($rsh(test -f file)) {\n  X = 1\n}",
            "expect": ["if_statement", "cmd_execution", "command"],
        },
    ],
    
    "expr_interpolation": [
        {
            "name": "Simple ${} interpolation",
            "code": "echo Hello ${NAME}",
            "expect": ["command", "expr_interpolation", "identifier"],
        },
        {
            "name": "${} with property access",
            "code": "ssh ${SERVER.fqdn}",
            "expect": ["command", "expr_interpolation", "property_access"],
        },
        {
            "name": "${} with expression",
            "code": "echo Item ${i + 1}",
            "expect": ["command", "expr_interpolation", "binary_expression"],
        },
        {
            "name": "Multiple ${} in command",
            "code": "curl https://${HOST}:${PORT}/api",
            "expect": ["command", "expr_interpolation"],
        },
    ],
    
    "path_literals": [
        {
            "name": "Absolute path",
            "code": "/bin/ls -la",
            "expect": ["command", "path"],
        },
        {
            "name": "Relative path with ./",
            "code": "./script.sh arg1",
            "expect": ["command", "path"],
        },
        {
            "name": "Home path",
            "code": "cat ~/config.json",
            "expect": ["command", "path"],
        },
    ],
    
    "nested_mode_switches": [
        {
            "name": "EXPR → CMD → EXPR ($rsh with ${})",
            "code": 'result = $rsh(echo Status: ${PORT})',
            "expect": ["assignment", "cmd_execution", "command", "expr_interpolation"],
        },
        {
            "name": "CMD → EXPR with property",
            "code": "echo Server: ${S.fqdn}",
            "expect": ["command", "expr_interpolation", "property_access"],
        },
        {
            "name": "$rsh with variable interpolation",
            "code": "output = $rsh(ssh ${HOST} whoami)",
            "expect": ["assignment", "cmd_execution", "command", "expr_interpolation"],
        },
        {
            "name": "Nested in for loop",
            "code": 'for (S in SERVERS) {\n  result = $rsh(echo ${S.fqdn})\n}',
            "expect": ["for_statement", "assignment", "cmd_execution", "expr_interpolation", "property_access"],
        },
    ],
    
    "function_calls": [
        {
            "name": "Simple function call",
            "code": "print(42)",
            "expect": ["function_call", "identifier", "number"],
        },
        {
            "name": "Function with multiple args",
            "code": 'format(name, age, city)',
            "expect": ["function_call", "identifier"],
        },
        {
            "name": "Function in assignment",
            "code": "result = calculate(X, Y)",
            "expect": ["assignment", "function_call"],
        },
    ],
}


def generate_grammar() -> bool:
    """Generate the grammar with timeout protection."""
    print("Generating grammar...")
    try:
        result = subprocess.run(
            ["tree-sitter", "generate"],
            cwd=str(GRAMMAR_DIR),
            capture_output=True,
            text=True,
            timeout=15  # 15 second timeout for generation
        )
        
        if result.returncode != 0:
            print(f"ERROR: Failed to generate grammar:")
            print(result.stderr)
            return False
        
        print("✓ Grammar generated\n")
        return True
    except subprocess.TimeoutExpired:
        print("ERROR: Grammar generation timed out after 15 seconds")
        return False


def parse_code(code: str, verbose: bool = False, show_xml: bool = False) -> str:
    """Parse code using tree-sitter with timeout protection."""
    import tempfile
    
    with tempfile.NamedTemporaryFile(mode='w', suffix='.rsh', delete=False) as f:
        f.write(code)
        tmpfile = f.name
    
    try:
        # Normal parse for checking - with timeout
        result = subprocess.run(
            ["tree-sitter", "parse", tmpfile],
            cwd=str(GRAMMAR_DIR),
            capture_output=True,
            text=True,
            timeout=5  # 5 second timeout per parse
        )
        
        # Debug XML parse if requested
        xml_output = ""
        if show_xml:
            try:
                xml_result = subprocess.run(
                    ["tree-sitter", "parse", "--debug", "--xml", tmpfile],
                    cwd=str(GRAMMAR_DIR),
                    capture_output=True,
                    text=True,
                    timeout=5
                )
                xml_output = xml_result.stdout
            except subprocess.TimeoutExpired:
                xml_output = "(XML parse timed out)"
        
        if verbose:
            print(f"  Input: {code}")
            print(f"  Parse tree:")
            for line in result.stdout.split('\n'):
                if line.strip():
                    print(f"    {line}")
            if show_xml and xml_output:
                print(f"  XML AST:")
                for line in xml_output.split('\n')[:30]:  # First 30 lines
                    if line.strip():
                        print(f"    {line}")
            print()
        
        return result.stdout + result.stderr
    except subprocess.TimeoutExpired:
        return "(ERROR: Parse timed out after 5 seconds)"
    finally:
        Path(tmpfile).unlink()


def extract_node_types(output: str) -> Set[str]:
    """Extract node types from tree-sitter output."""
    import re
    matches = re.findall(r'\((\w+)', output)
    return set(matches)


def run_test(test_case: dict, verbose: bool = False, debug_xml: bool = False) -> bool:
    """Run a single test case."""
    name = test_case["name"]
    code = test_case["code"]
    expected = test_case.get("expect", [])
    
    print(f"  {name}...", end=" ", flush=True)
    
    # Parse with XML debug output for failed tests
    output = parse_code(code, verbose, show_xml=debug_xml)
    
    # Check for ERROR nodes (strict check - look for actual ERROR nodes, not just the word)
    if "(ERROR" in output or "MISSING" in output:
        print("✗ FAIL (parse error)")
        if not verbose:
            print(f"      Input: {repr(code)}")
            for line in output.split('\n'):
                if 'ERROR' in line or 'MISSING' in line:
                    print(f"      {line}")
            # Show XML AST for failed tests
            if debug_xml:
                parse_code(code, verbose=True, show_xml=True)
        return False
    
    found = extract_node_types(output)
    missing = set(expected) - found
    
    if missing:
        print(f"✗ FAIL (missing: {', '.join(sorted(missing))})")
        if not verbose:
            print(f"      Input: {repr(code)}")
            print(f"      Found: {', '.join(sorted(found))}")
            # Show XML AST for failed tests
            if debug_xml:
                parse_code(code, verbose=True, show_xml=True)
        return False
    
    print("✓")
    return True


def run_test_suite(category_filter: str = None, verbose: bool = False, debug_xml: bool = False) -> list:
    """Run all tests or filtered tests."""
    results = []
    
    for category, tests in TEST_CASES.items():
        if category_filter and category_filter.lower() not in category.lower():
            continue
        
        print(f"\n{category.upper()}:")
        for test in tests:
            result = run_test(test, verbose, debug_xml=debug_xml)
            results.append((category, test["name"], result))
    
    return results


def print_summary(results: list):
    """Print test summary."""
    passed = sum(1 for _, _, result in results if result)
    failed = len(results) - passed
    
    print(f"\n{'='*60}")
    print(f"SUMMARY:")
    print(f"  ✓ Passed: {passed}")
    print(f"  ✗ Failed: {failed}")
    print(f"  Total:    {len(results)}")
    
    if failed > 0:
        print(f"\nFailed tests:")
        for category, name, result in results:
            if not result:
                print(f"  - [{category}] {name}")
    
    pass_rate = (passed / len(results) * 100) if results else 0
    print(f"\nPass rate: {pass_rate:.1f}%")


def main():
    parser = argparse.ArgumentParser(
        description="Test RShell grammar",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python test_grammar_simple.py                  # Run all tests
  python test_grammar_simple.py -v               # Verbose output
  python test_grammar_simple.py --filter lists   # Only list tests
        """
    )
    parser.add_argument("--verbose", "-v", action="store_true", help="Show parse trees")
    parser.add_argument("--no-generate", action="store_true", help="Skip grammar generation")
    parser.add_argument("--filter", "-f", help="Filter tests by category")
    parser.add_argument("--debug-xml", action="store_true", help="Show XML AST with --debug for failing tests")
    args = parser.parse_args()
    
    print("RShell Grammar Test Suite")
    print("="*60)
    print(f"Grammar: {GRAMMAR_FILE}")
    
    total_tests = sum(len(tests) for category, tests in TEST_CASES.items()
                     if not args.filter or args.filter.lower() in category.lower())
    print(f"Tests: {total_tests}")
    if args.filter:
        print(f"Filter: {args.filter}")
    
    # Generate grammar unless --no-generate
    if not args.no_generate:
        if not generate_grammar():
            sys.exit(1)
    
    # Run tests
    results = run_test_suite(args.filter, args.verbose, debug_xml=args.debug_xml)
    print_summary(results)
    
    # Exit code based on failures
    failed = sum(1 for _, _, result in results if not result)
    sys.exit(0 if failed == 0 else 1)


if __name__ == "__main__":
    main()