#!/usr/bin/env python3
"""
Test suite for RShell mode-specific syntax.
Tests the new $rsh() and ${} constructs introduced in Phase 4.

Tests:
- ${} expression interpolation in CMD mode
- $rsh() command execution in EXPR mode
- $() command substitution in CMD mode
- Invalid cross-mode syntax detection
"""

import argparse
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Set, Dict, Tuple, List

GRAMMAR_DIR = Path(__file__).parent.parent

# Mode-specific syntax test cases
MODE_SPECIFIC_TESTS = {
    "cmd_mode_expr_interpolation": [
        {
            "name": "${} simple interpolation",
            "code": 'echo "User: ${user}"',
            "expect": ["cmd_expr_interpolation", "identifier"],
            "should_pass": True
        },
        {
            "name": "${} expression in command",
            "code": 'echo "Total: ${count + 1}"',
            "expect": ["cmd_expr_interpolation", "binary_expression"],
            "should_pass": True
        },
        {
            "name": "${} property access",
            "code": 'ssh ${server.fqdn} -p ${server.port}',
            "expect": ["cmd_expr_interpolation", "property_access"],
            "should_pass": True
        },
        {
            "name": "Multiple ${} interpolations",
            "code": 'echo "Name: ${first} ${last}"',
            "expect": ["cmd_expr_interpolation"],
            "should_pass": True
        },
        {
            "name": "${} in pipeline",
            "code": 'grep ${pattern} file.txt | wc -l',
            "expect": ["pipeline", "cmd_expr_interpolation"],
            "should_pass": True
        }
    ],
    
    "cmd_mode_substitution": [
        {
            "name": "$() basic substitution",
            "code": 'echo $(whoami)',
            "expect": ["command", "cmd_substitution"],
            "should_pass": True
        },
        {
            "name": "$() in pipeline",
            "code": 'grep $(cat pattern.txt) logfile',
            "expect": ["command", "cmd_substitution"],
            "should_pass": True
        },
        {
            "name": "Multiple $() substitutions",
            "code": 'echo $(whoami) on $(hostname)',
            "expect": ["command", "cmd_substitution"],
            "should_pass": True
        },
        {
            "name": "$() with flags",
            "code": 'ls $(find . -name "*.txt")',
            "expect": ["command", "cmd_substitution"],
            "should_pass": True
        }
    ],
    
    "expr_mode_cmd_execution": [
        {
            "name": "$rsh() basic execution",
            "code": 'user = $rsh(whoami)',
            "expect": ["assignment", "expr_cmd_execution"],
            "should_pass": True
        },
        {
            "name": "$rsh() with flags",
            "code": 'files = $rsh(ls -la)',
            "expect": ["assignment", "expr_cmd_execution"],
            "should_pass": True
        },
        {
            "name": "$rsh() in pipeline",
            "code": 'result = $rsh(cat file | grep pattern)',
            "expect": ["assignment", "expr_cmd_execution", "pipeline"],
            "should_pass": True
        },
        {
            "name": "$rsh() with property access",
            "code": 'status = $rsh(ssh ${server.fqdn} echo ok).exit_code',
            "expect": ["property_access", "expr_cmd_execution"],
            "should_pass": True
        },
        {
            "name": "Chained assignments with $rsh()",
            "code": 'user = $rsh(whoami) and host = $rsh(hostname)',
            "expect": ["chained_assignment", "expr_cmd_execution"],
            "should_pass": True
        }
    ],
    
    "invalid_cross_mode": [
        {
            "name": "$rsh() in CMD mode (invalid)",
            "code": 'echo $rsh(whoami)',
            "expect": ["ERROR"],
            "should_pass": False
        },
        {
            "name": "${} in EXPR mode (invalid)",
            "code": 'result = ${user}',
            "expect": ["ERROR"],
            "should_pass": False
        },
        {
            "name": "$() in EXPR mode (invalid)",
            "code": 'result = $(whoami)',
            "expect": ["ERROR"],
            "should_pass": False
        },
        {
            "name": "Nested $rsh() in ${} (invalid)",
            "code": 'echo "${X + $rsh(whoami)}"',
            "expect": ["ERROR"],
            "should_pass": False
        },
        {
            "name": "Nested ${} in $rsh() (invalid)",
            "code": 'result = $rsh(echo ${user})',
            "expect": ["ERROR"],
            "should_pass": False
        }
    ],
    
    "complex_valid_examples": [
        {
            "name": "CMD mode with mixed syntax",
            "code": '''echo "User: ${user} on $(hostname)"''',
            "expect": ["command", "cmd_expr_interpolation", "cmd_substitution"],
            "should_pass": True
        },
        {
            "name": "EXPR mode with $rsh()",
            "code": '''result = $rsh(ssh server.com uname -a)
if (result.success) {
    status = "OK"
}''',
            "expect": ["assignment", "expr_cmd_execution", "if_statement"],
            "should_pass": True
        },
        {
            "name": "For loop with $rsh()",
            "code": '''for server in servers {
    result = $rsh(ping -c 1 server)
}''',
            "expect": ["for_statement", "expr_cmd_execution"],
            "should_pass": True
        },
        {
            "name": "Command with complex ${} interpolation",
            "code": 'curl "https://${config.host}:${config.port}/api/v${version}"',
            "expect": ["command", "cmd_expr_interpolation"],
            "should_pass": True
        }
    ]
}

def generate_grammar() -> bool:
    """Generate the grammar."""
    print("Generating grammar...")
    result = subprocess.run(
        ["tree-sitter", "generate"],
        cwd=str(GRAMMAR_DIR),
        capture_output=True,
        text=True
    )
    
    if result.returncode != 0:
        print(f"ERROR: Failed to generate grammar:")
        print(result.stderr)
        return False
    
    print("✓ Grammar generated\n")
    return True


def parse_code(code: str, verbose: bool = False) -> Tuple[str, bool]:
    """Parse code using tree-sitter. Returns (output, has_error)."""
    with tempfile.NamedTemporaryFile(mode='w', suffix='.rsh', delete=False) as f:
        f.write(code)
        tmpfile = f.name
    
    try:
        result = subprocess.run(
            ["tree-sitter", "parse", tmpfile],
            cwd=str(GRAMMAR_DIR),
            capture_output=True,
            text=True
        )
        
        output = result.stdout + result.stderr
        has_error = "(ERROR" in output or "MISSING" in output
        
        if verbose:
            print(f"  Input: {code}")
            print(f"  Parse tree:")
            for line in output.split('\n'):
                if line.strip():
                    print(f"    {line}")
            print()
        
        return output, has_error
    finally:
        Path(tmpfile).unlink()


def extract_node_types(output: str) -> Set[str]:
    """Extract node types from tree-sitter output."""
    import re
    matches = re.findall(r'\((\w+)', output)
    return set(matches)


def run_test(test_case: dict, verbose: bool = False) -> Tuple[bool, str]:
    """Run a single test case. Returns (passed, reason)."""
    name = test_case["name"]
    code = test_case["code"]
    expected_nodes = test_case.get("expect", [])
    should_pass = test_case.get("should_pass", True)
    
    print(f"  {name}...", end=" ", flush=True)
    
    output, has_error = parse_code(code, verbose)
    
    if should_pass:
        # Test should parse successfully
        if has_error:
            print("✗ FAIL (unexpected parse error)")
            if not verbose:
                for line in output.split('\n'):
                    if 'ERROR' in line or 'MISSING' in line:
                        print(f"      {line}")
            return False, "Parse error when expecting success"
        
        # Check for expected nodes
        found = extract_node_types(output)
        missing = set(expected_nodes) - found
        
        if missing:
            print(f"✗ FAIL (missing: {', '.join(sorted(missing))})")
            return False, f"Missing nodes: {missing}"
        
        print("✓")
        return True, "Success"
    
    else:
        # Test should fail to parse
        if not has_error:
            print("✗ FAIL (expected error but parsed successfully)")
            return False, "No error when expecting failure"
        
        print("✓ (correctly failed)")
        return True, "Correctly rejected invalid syntax"


def run_test_suite(category_filter: str = None, verbose: bool = False) -> List[Tuple[str, str, bool]]:
    """Run all tests or filtered tests."""
    results = []
    
    for category, tests in MODE_SPECIFIC_TESTS.items():
        if category_filter and category_filter.lower() not in category.lower():
            continue
        
        print(f"\n{category.upper().replace('_', ' ')}:")
        for test in tests:
            passed, reason = run_test(test, verbose)
            results.append((category, test["name"], passed))
    
    return results


def print_summary(results: List[Tuple[str, str, bool]]):
    """Print test summary."""
    passed = sum(1 for _, _, result in results if result)
    failed = len(results) - passed
    
    print(f"\n{'='*60}")
    print(f"MODE-SPECIFIC SYNTAX TEST SUMMARY:")
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
        description="Test RShell Mode-Specific Syntax",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python test_mode_specific_syntax.py                  # Run all tests
  python test_mode_specific_syntax.py -v               # Verbose output
  python test_mode_specific_syntax.py --filter expr    # Only EXPR mode tests
        """
    )
    parser.add_argument("--verbose", "-v", action="store_true", help="Show parse trees")
    parser.add_argument("--no-generate", action="store_true", help="Skip grammar generation")
    parser.add_argument("--filter", "-f", help="Filter tests by category")
    args = parser.parse_args()
    
    print("RShell Mode-Specific Syntax Test Suite")
    print("="*60)
    print("Testing new syntax features:")
    print("  - ${} expression interpolation in CMD mode")
    print("  - $rsh() command execution in EXPR mode")
    print("  - Invalid cross-mode syntax detection")
    
    total_tests = sum(len(tests) for category, tests in MODE_SPECIFIC_TESTS.items()
                     if not args.filter or args.filter.lower() in category.lower())
    print(f"\nTests to run: {total_tests}")
    if args.filter:
        print(f"Filter: {args.filter}")
    
    # Generate grammar unless --no-generate
    if not args.no_generate:
        if not generate_grammar():
            sys.exit(1)
    
    # Run tests
    results = run_test_suite(args.filter, args.verbose)
    print_summary(results)
    
    # Exit code based on failures
    failed = sum(1 for _, _, result in results if not result)
    sys.exit(0 if failed == 0 else 1)


if __name__ == "__main__":
    main()