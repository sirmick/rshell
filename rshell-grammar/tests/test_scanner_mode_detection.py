#!/usr/bin/env python3
"""
Test that grammar correctly handles EXPR vs CMD mode lines.

In V3 design:
- Scanner only emits NEWLINE and BLOCK_START tokens
- Grammar determines mode based on syntax patterns
- This test verifies lines parse without errors and produce expected node types
"""

import subprocess
import tempfile
from pathlib import Path


def parse_line(line: str) -> tuple[str, str]:
    """
    Parse a single line and check the result.
    Returns: (status, output) where status is 'SUCCESS' or 'ERROR'
    """
    with tempfile.NamedTemporaryFile(mode='w', suffix='.rsh', delete=False) as f:
        f.write(line)
        tmpfile = f.name
    
    try:
        result = subprocess.run(
            ['tree-sitter', 'parse', tmpfile],
            cwd='.',
            capture_output=True,
            text=True
        )
        
        output = result.stdout + result.stderr
        
        # Check for error nodes
        if '(ERROR' in output or 'MISSING' in output:
            return 'ERROR', output
        else:
            return 'SUCCESS', output
    finally:
        Path(tmpfile).unlink()


def check_node_type(output: str, expected_nodes: list[str]) -> bool:
    """Check if all expected node types are present in the parse output."""
    return all(node in output for node in expected_nodes)


def test_grammar_parsing():
    """Test that grammar correctly parses EXPR and CMD mode lines."""
    
    # Test cases: (line, expected_nodes, description)
    tests = [
        # ===== EXPR MODE CASES =====
        ("X = 42", ["assignment", "identifier", "number"], "Uppercase assignment"),
        ("COUNT = 100", ["assignment", "identifier", "number"], "Uppercase assignment"),
        ("_private = 10", ["assignment", "identifier", "number"], "Underscore assignment"),
        ("if (true) { }", ["if_statement", "block"], "Control flow: if"),
        ("for (S in [1, 2]) { }", ["for_statement", "block"], "Control flow: for"),
        ("while (X < 100) { }", ["while_statement", "block"], "Control flow: while"),
        ("return 42", ["return_statement", "number"], "Return keyword"),
        ("continue", ["continue_statement"], "Continue keyword"),
        ("break", ["break_statement"], "Break keyword"),
        
        # ===== CMD MODE CASES =====
        ("echo hello", ["cmd_line", "command", "identifier"], "Simple command"),
        ("ls", ["cmd_line", "command", "identifier"], "Single word command"),
        ("ls -la", ["cmd_line", "command"], "Command with flags"),
        ("cat file.txt", ["cmd_line", "command"], "Command with args"),
        ("grep pattern", ["cmd_line", "command"], "Another command"),
        ("/bin/ls", ["cmd_line", "command", "path"], "Path with /"),
        ("./script.sh", ["cmd_line", "command", "path"], "Path with ./"),
        ("echo test | grep t", ["cmd_line", "pipeline", "command"], "Pipeline"),
        
        # ===== STRING ARGUMENTS (CRITICAL TEST) =====
        ('echo "hello"', ["cmd_line", "command", "string"], "Command with quoted string"),
        ('echo "yo"', ["cmd_line", "command", "string"], "Simple quoted arg"),
    ]
    
    print("RShell Grammar Parsing Tests")
    print("=" * 70)
    
    passed = 0
    failed = 0
    
    for line, expected_nodes, description in tests:
        status, output = parse_line(line)
        
        if status == 'ERROR':
            failed += 1
            print(f"✗ FAIL: {description:40s} | PARSE ERROR")
            print(f"  Input: {line}")
            # Show first error line
            for line_out in output.split('\n'):
                if 'ERROR' in line_out or 'MISSING' in line_out:
                    print(f"  {line_out}")
                    break
        elif check_node_type(output, expected_nodes):
            passed += 1
            print(f"✓ PASS: {description:40s} | {', '.join(expected_nodes[:3])}")
        else:
            failed += 1
            print(f"✗ FAIL: {description:40s} | Missing expected nodes")
            print(f"  Expected: {expected_nodes}")
            print(f"  Input: {line}")
    
    print("=" * 70)
    print(f"Results: {passed} passed, {failed} failed, {len(tests)} total")
    print(f"Pass rate: {passed/len(tests)*100:.1f}%")
    
    return failed == 0


if __name__ == "__main__":
    import sys
    success = test_grammar_parsing()
    sys.exit(0 if success else 1)