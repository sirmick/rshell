#!/usr/bin/env python3
"""
Test cases for $(...) command substitution syntax in RShell.
This replaces the shell() function with a more natural bash-style syntax.
"""

import subprocess
import tempfile
from pathlib import Path
from typing import Set

GRAMMAR_DIR = Path(__file__).parent.parent

# Test cases for command substitution
CMD_SUB_TESTS = {
    "basic_usage": [
        {
            "name": "Simple command substitution",
            "code": 'result = $(ls -la)',
            "expect": ["assignment", "command_substitution"],
        },
        {
            "name": "Command with quotes",
            "code": 'output = $(grep "error" /var/log/syslog)',
            "expect": ["assignment", "command_substitution"],
        },
        {
            "name": "Command with pipes",
            "code": 'count = $(ps aux | grep python | wc -l)',
            "expect": ["assignment", "command_substitution"],
        },
    ],
    
    "in_expressions": [
        {
            "name": "In conditional",
            "code": 'if ($(test -f config.json)) {\n    echo File exists\n}',
            "expect": ["if_statement", "command_substitution"],
        },
        {
            "name": "Property access on result",
            "code": 'status = $(systemctl status nginx).exitcode',
            "expect": ["assignment", "command_substitution", "property_access"],
        },
        {
            "name": "In comparison",
            "code": 'if ($(whoami) == "root") {\n    echo Running as root\n}',
            "expect": ["if_statement", "command_substitution", "binary_expression"],
        },
    ],
    
    "complex_commands": [
        {
            "name": "Nested parentheses",
            "code": 'result = $(echo $(date +%Y-%m-%d))',
            "expect": ["assignment", "command_substitution"],
        },
        {
            "name": "JSON with quotes",
            "code": 'data = $(curl -H "Content-Type: application/json" https://api.example.com)',
            "expect": ["assignment", "command_substitution"],
        },
        {
            "name": "Multiple on one line",
            "code": 'user = $(whoami) and host = $(hostname)',
            "expect": ["command_substitution", "binary_expression"],
        },
    ],
    
    "cmd_mode_usage": [
        {
            "name": "In echo command",
            "code": 'echo "Current user: $(whoami)"',
            "expect": ["command", "string"],  # In CMD mode, it's part of the string
        },
        {
            "name": "Command argument",
            "code": 'grep $(cat pattern.txt) file.log',
            "expect": ["command"],  # Scanner should handle this
        },
    ],
    
    "with_other_features": [
        {
            "name": "With template strings",
            "code": 'DIR = "/tmp"\nfiles = $(`ls -la ${DIR}`)',
            "expect": ["assignment", "command_substitution", "template_string"],
        },
        {
            "name": "In for loop",
            "code": 'for file in $(find . -name "*.txt") {\n    echo Processing {file}\n}',
            "expect": ["for_statement", "command_substitution", "command_interpolation"],
        },
        {
            "name": "Mixed with interpolation",
            "code": 'NAME = "test"\nresult = $(grep {NAME} file.txt)',
            "expect": ["assignment", "command_substitution"],
        },
    ],
}


def generate_grammar():
    """Generate the grammar with command substitution support."""
    print("Generating grammar with $() command substitution...")
    
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


def parse_code(code: str) -> str:
    """Parse code using tree-sitter."""
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
        return result.stdout + result.stderr
    finally:
        Path(tmpfile).unlink()


def extract_node_types(output: str) -> Set[str]:
    """Extract node types from tree-sitter output."""
    import re
    matches = re.findall(r'\((\w+)', output)
    return set(matches)


def run_test(test_case: dict, verbose: bool = False) -> bool:
    """Run a single test case."""
    name = test_case["name"]
    code = test_case["code"]
    expected = test_case.get("expect", [])
    
    print(f"  {name}...", end=" ", flush=True)
    
    output = parse_code(code)
    
    if verbose:
        print(f"\n  Code: {code}")
        print(f"  Output: {output[:200]}...")
    
    # Check for ERROR nodes
    if "(ERROR" in output or "MISSING" in output:
        print("✗ FAIL (parse error)")
        if not verbose:
            for line in output.split('\n'):
                if 'ERROR' in line or 'MISSING' in line:
                    print(f"      {line}")
        return False
    
    found = extract_node_types(output)
    missing = set(expected) - found
    
    if missing:
        print(f"✗ FAIL (missing: {', '.join(sorted(missing))})")
        return False
    
    print("✓")
    return True


def main():
    """Run command substitution tests."""
    print("Command Substitution $() Tests")
    print("=" * 60)
    
    if not generate_grammar():
        return
    
    total_passed = 0
    total_failed = 0
    
    for category, tests in CMD_SUB_TESTS.items():
        print(f"\n{category.upper().replace('_', ' ')}:")
        for test in tests:
            if run_test(test):
                total_passed += 1
            else:
                total_failed += 1
    
    print("\n" + "=" * 60)
    print(f"Results: {total_passed} passed, {total_failed} failed")
    
    if total_failed == 0:
        print("🎉 All command substitution tests passed!")
    else:
        print(f"⚠️ {total_failed} tests failed")


if __name__ == "__main__":
    main()