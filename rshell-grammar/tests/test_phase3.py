#!/usr/bin/env python3
"""
Test cases for Phase 3 features of RShell grammar.

Tests:
1. shell() function
2. {} interpolation in commands
3. Path literals
4. Template strings
"""

import subprocess
import tempfile
from pathlib import Path
from typing import Set

GRAMMAR_DIR = Path(__file__).parent.parent

# Phase 3 test cases
PHASE3_TESTS = {
    "shell_function": [
        {
            "name": "Simple shell() call",
            "code": 'result = shell("ls -la")',
            "expect": ["assignment", "shell_function", "string"],
        },
        {
            "name": "shell() with variable",
            "code": 'output = shell($CMD)',
            "expect": ["assignment", "shell_function", "variable_reference"],
        },
        {
            "name": "shell() with identifier",
            "code": 'data = shell(command)',
            "expect": ["assignment", "shell_function", "identifier"],
        },
        {
            "name": "shell() in if statement",
            "code": 'if (shell("test -f file.txt").success) {\n  echo "File exists"\n}',
            "expect": ["if_statement", "shell_function", "property_access"],
        },
    ],
    
    "command_interpolation": [
        {
            "name": "Simple {} interpolation",
            "code": 'echo {NAME}',
            "expect": ["command", "command_interpolation", "identifier"],
        },
        {
            "name": "Property access in interpolation",
            "code": 'ssh {SERVER.fqdn} -p {SERVER.port}',
            "expect": ["command", "command_interpolation", "property_access"],
        },
        {
            "name": "Expression in interpolation",
            "code": 'echo Total: {COUNT + 1}',
            "expect": ["command", "command_interpolation", "binary_expression"],
        },
        {
            "name": "Multiple interpolations",
            "code": 'echo {USER} has {COUNT} items in {DIR}',
            "expect": ["command", "command_interpolation"],
        },
    ],
    
    "path_literals": [
        {
            "name": "Absolute path",
            "code": '/bin/ls -la',
            "expect": ["command", "path_literal"],
        },
        {
            "name": "Relative path with ./",
            "code": './script.sh arg1 arg2',
            "expect": ["command", "path_literal"],
        },
        {
            "name": "Relative path with ../",
            "code": '../dir/program --help',
            "expect": ["command", "path_literal"],
        },
        {
            "name": "Home path",
            "code": '~/bin/tool',
            "expect": ["command", "path_literal"],
        },
        {
            "name": "Path in assignment",
            "code": 'SCRIPT = "./deploy.sh"',
            "expect": ["assignment", "string"],  # Note: paths in quotes are strings
        },
        {
            "name": "Path literal as value",
            "code": 'PATH = /usr/local/bin',
            "expect": ["assignment", "path_literal"],
        },
    ],
    
    "template_strings": [
        {
            "name": "Simple template string",
            "code": 'MSG = `Hello world`',
            "expect": ["assignment", "template_string"],
        },
        {
            "name": "Template with interpolation",
            "code": 'MSG = `Hello ${NAME}`',
            "expect": ["assignment", "template_string", "template_interpolation"],
        },
        {
            "name": "Multiple interpolations",
            "code": 'MSG = `${USER} has ${COUNT} items`',
            "expect": ["assignment", "template_string", "template_interpolation"],
        },
        {
            "name": "Expression in template",
            "code": 'MSG = `Total: ${COUNT + 1}`',
            "expect": ["assignment", "template_string", "binary_expression"],
        },
        {
            "name": "Template in shell()",
            "code": 'result = shell(`ls ${DIR}`)',
            "expect": ["assignment", "shell_function", "template_string"],
        },
    ],
    
    "function_calls": [
        {
            "name": "Function with no args",
            "code": 'value = random()',
            "expect": ["assignment", "function_call"],
        },
        {
            "name": "Function with single arg",
            "code": 'upper = uppercase(NAME)',
            "expect": ["assignment", "function_call", "identifier"],
        },
        {
            "name": "Function with multiple args",
            "code": 'result = join(LIST, ", ")',
            "expect": ["assignment", "function_call", "identifier", "string"],
        },
        {
            "name": "Nested function calls",
            "code": 'value = max(min(X, 100), 0)',
            "expect": ["assignment", "function_call"],
        },
    ],
    
    "combined_features": [
        {
            "name": "shell() with template string",
            "code": 'result = shell(`ssh ${SERVER} -p ${PORT}`)',
            "expect": ["assignment", "shell_function", "template_string"],
        },
        {
            "name": "Command with path and interpolation",
            "code": '/usr/bin/python3 {SCRIPT} --config {CONFIG_FILE}',
            "expect": ["command", "path_literal", "command_interpolation"],
        },
        {
            "name": "Complex expression",
            "code": '''
for SERVER in SERVERS {
  result = shell(`ssh ${SERVER.fqdn} -p ${SERVER.port} "uptime"`)
  if (result.success) {
    echo {SERVER.name} is up
  }
}''',
            "expect": ["for_statement", "shell_function", "template_string", 
                      "if_statement", "command_interpolation"],
        },
    ],
}


def generate_grammar():
    """Generate the grammar with Phase 3 features."""
    print("Generating grammar with Phase 3 features...")
    
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
    """Run Phase 3 tests."""
    print("Phase 3 Feature Tests")
    print("=" * 60)
    
    if not generate_grammar():
        return
    
    total_passed = 0
    total_failed = 0
    
    for category, tests in PHASE3_TESTS.items():
        print(f"\n{category.upper()}:")
        for test in tests:
            if run_test(test):
                total_passed += 1
            else:
                total_failed += 1
    
    print("\n" + "=" * 60)
    print(f"Results: {total_passed} passed, {total_failed} failed")
    
    if total_failed == 0:
        print("🎉 All Phase 3 tests passed!")
    else:
        print(f"⚠️ {total_failed} tests need implementation")
        print("\nNote: These features need to be added to the grammar.")


if __name__ == "__main__":
    main()