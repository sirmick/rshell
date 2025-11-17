#!/usr/bin/env python3
"""
Test scanner mode detection (EXPR vs CMD line start tokens).

This tests the scanner's ability to correctly identify whether a line
should start with expr_line_start or cmd_line_start.
"""

import subprocess
import tempfile
from pathlib import Path


def check_line_mode(line: str) -> str:
    """
    Parse a single line and check what line_start token was emitted.
    Returns: 'EXPR', 'CMD', or 'ERROR'
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
        if '(ERROR' in output:
            return 'ERROR'
        
        # Check which line_start token appears
        if 'expr_line_start' in output:
            return 'EXPR'
        elif 'cmd_line_start' in output:
            return 'CMD'
        else:
            return 'UNKNOWN'
    finally:
        Path(tmpfile).unlink()


def test_mode_detection():
    """Test mode detection for various line types."""
    
    # Test cases: (line, expected_mode)
    tests = [
        # ===== EXPR MODE CASES =====
        ("X = 42", "EXPR"),                          # Uppercase assignment
        ("COUNT = 100", "EXPR"),                      # Uppercase assignment
        ("_private = 10", "EXPR"),                    # Underscore assignment
        ("if (X > 10) { }", "EXPR"),                  # Control flow: if
        ("elif (Y < 5) { }", "EXPR"),                 # Control flow: elif
        ("else { }", "EXPR"),                         # Control flow: else
        ("for S in SERVERS { }", "EXPR"),             # Control flow: for
        ("while (X < 100) { }", "EXPR"),              # Control flow: while
        ("}", "EXPR"),                                # Block close
        ("return 42", "EXPR"),                        # Reserved keyword
        ("continue", "EXPR"),                         # Reserved keyword
        ("yield value", "EXPR"),                      # Reserved keyword
        
        # ===== CMD MODE CASES =====
        ("echo hello", "CMD"),                        # Simple command
        ("ls", "CMD"),                                # Single word command
        ("ls -la", "CMD"),                            # Command with flags
        ("cat file.txt", "CMD"),                      # Command with args
        ("grep pattern", "CMD"),                      # Another command
        ("/bin/ls", "CMD"),                           # Path with /
        ("./script.sh", "CMD"),                       # Path with ./
        ("echo test | grep t", "CMD"),                # Pipeline
    ]
    
    print("Scanner Mode Detection Tests")
    print("=" * 60)
    
    passed = 0
    failed = 0
    
    for line, expected in tests:
        actual = check_line_mode(line)
        status = "✓" if actual == expected else "✗"
        
        if actual == expected:
            passed += 1
        else:
            failed += 1
            
        # Show details for failures
        if actual != expected:
            print(f"{status} FAIL: {line:30s} | Expected: {expected:5s} | Got: {actual}")
        else:
            print(f"{status} PASS: {line:30s} | {expected}")
    
    print("=" * 60)
    print(f"Results: {passed} passed, {failed} failed, {len(tests)} total")
    print(f"Pass rate: {passed/len(tests)*100:.1f}%")
    
    return failed == 0


if __name__ == "__main__":
    import sys
    success = test_mode_detection()
    sys.exit(0 if success else 1)