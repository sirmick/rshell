#!/usr/bin/env python3
"""
Simple test to see if scanner emits any tokens
"""

import subprocess
import sys

# Test a simple assignment
test_code = "X = 2"

print("Testing scanner with:", repr(test_code))
print()

# Write to temp file
with open("/tmp/test.rsh", "w") as f:
    f.write(test_code)

# Parse with tree-sitter
result = subprocess.run(
    ["tree-sitter", "parse", "/tmp/test.rsh"],
    capture_output=True,
    text=True,
    cwd="."
)

print("Input text:", repr(test_code))
print()
print("STDOUT:")
print(result.stdout)
print()
print("STDERR:")
print(result.stderr)
print()
print("Return code:", result.returncode)

# Show the parse tree
if result.stdout:
    print("\nParse tree shows:")
    if "expr_start" in result.stdout.lower():
        print("  ✓ Scanner emitted EXPR_START")
    if "cmd_start" in result.stdout.lower():
        print("  ✓ Scanner emitted CMD_START")
    if "ERROR" in result.stdout:
        print("  ✗ Parse errors detected")
    if "(program)" in result.stdout and result.stdout.count("(") == 1:
        print("  ✗ Empty parse tree - scanner not emitting tokens")