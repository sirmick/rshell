#!/usr/bin/env python3
"""
Test suite for the RShell scanner (external scanner in C).
Tests mode detection and token emission for the new mode-specific syntax.
"""

import subprocess
import json
import tempfile
import os
from pathlib import Path

class ScannerTest:
    """Test harness for the RShell scanner"""
    
    def __init__(self):
        self.grammar_dir = Path(__file__).parent.parent
        self.scanner_path = self.grammar_dir / "src" / "scanner.c"
        self.test_scanner_path = self.grammar_dir / "tests" / "scanner_test_driver.c"
        
    def compile_test_scanner(self):
        """Compile a test driver for the scanner"""
        # We'll create a simple test driver that uses the scanner
        test_driver = """
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>
#include <stdint.h>

// Include the scanner implementation
#include "../src/scanner.c"

// Token names for output
const char* token_names[] = {
    "EXPR_LINE_START",
    "CMD_LINE_START", 
    "LINE_START",
    "CMD_EXPR_INTERP_START",    // ${
    "CMD_EXPR_INTERP_END",      // }
    "EXPR_CMD_EXEC_START",      // $rsh(
    "EXPR_CMD_EXEC_END",        // )
    "CMD_SUBSTITUTION_START",   // $(
    "CMD_SUBSTITUTION_END"      // )
};

int main(int argc, char** argv) {
    if (argc != 3) {
        fprintf(stderr, "Usage: %s <input_text> <initial_mode>\\n", argv[0]);
        return 1;
    }
    
    const char* input = argv[1];
    const char* mode = argv[2];
    
    // Create scanner
    void* scanner = tree_sitter_rshell_external_scanner_create();
    
    // Set initial state based on mode
    unsigned state_size = tree_sitter_rshell_external_scanner_serialize(scanner, NULL);
    char* state_buffer = calloc(1, state_size);
    
    // For testing, we'll manually set scanner state
    // This is a simplified version - real scanner has more complex state
    if (strcmp(mode, "expr") == 0) {
        // Set EXPR mode indicator in state
        state_buffer[0] = 1;  // Assuming first byte is mode
    }
    
    tree_sitter_rshell_external_scanner_deserialize(
        scanner, state_buffer, state_size
    );
    
    // Create lexer struct
    TSLexer lexer = {
        .lookahead = input[0],
        .result_symbol = 0,
    };
    
    // Simplified token scan
    const bool* valid_symbols = calloc(9, sizeof(bool));
    for (int i = 0; i < 9; i++) {
        ((bool*)valid_symbols)[i] = true;  // All tokens potentially valid
    }
    
    bool scanned = tree_sitter_rshell_external_scanner_scan(
        scanner, &lexer, valid_symbols
    );
    
    if (scanned) {
        printf("Token: %s\\n", token_names[lexer.result_symbol]);
    } else {
        printf("No token\\n");
    }
    
    tree_sitter_rshell_external_scanner_destroy(scanner);
    free(state_buffer);
    
    return 0;
}
"""
        
        # Write test driver
        with open(self.test_scanner_path, 'w') as f:
            f.write(test_driver)
            
        # Compile it
        compile_cmd = [
            "gcc", "-o", str(self.grammar_dir / "tests" / "scanner_test"),
            str(self.test_scanner_path),
            "-I", str(self.grammar_dir / "src")
        ]
        
        result = subprocess.run(compile_cmd, capture_output=True, text=True)
        if result.returncode != 0:
            raise RuntimeError(f"Failed to compile scanner test: {result.stderr}")
            
    def test_token(self, input_text, initial_mode="cmd"):
        """Test what token the scanner produces for given input"""
        test_binary = self.grammar_dir / "tests" / "scanner_test"
        
        if not test_binary.exists():
            self.compile_test_scanner()
            
        result = subprocess.run(
            [str(test_binary), input_text, initial_mode],
            capture_output=True,
            text=True
        )
        
        return result.stdout.strip()


class TestModeSpecificSyntax:
    """Test cases for the new mode-specific syntax"""
    
    def __init__(self):
        self.scanner = ScannerTest()
        self.passed = 0
        self.failed = 0
        
    def assert_token(self, input_text, expected_token, mode="cmd", description=""):
        """Assert that scanner produces expected token"""
        result = self.scanner.test_token(input_text, mode)
        expected = f"Token: {expected_token}" if expected_token else "No token"
        
        if result == expected:
            self.passed += 1
            print(f"✓ {description or input_text}: {result}")
        else:
            self.failed += 1
            print(f"✗ {description or input_text}")
            print(f"  Expected: {expected}")
            print(f"  Got: {result}")
            
    def run_tests(self):
        """Run all scanner tests"""
        print("\n=== Scanner Token Tests ===\n")
        
        # CMD Mode Tests
        print("CMD Mode:")
        self.assert_token("${", "CMD_EXPR_INTERP_START", "cmd", "CMD: ${} expr interpolation start")
        self.assert_token("$(", "CMD_SUBSTITUTION_START", "cmd", "CMD: $() substitution start")
        self.assert_token("$rsh(", None, "cmd", "CMD: $rsh() should NOT be valid")
        
        # EXPR Mode Tests  
        print("\nEXPR Mode:")
        self.assert_token("$rsh(", "EXPR_CMD_EXEC_START", "expr", "EXPR: $rsh() cmd execution start")
        self.assert_token("${", None, "expr", "EXPR: ${} should NOT be valid")
        self.assert_token("$(", None, "expr", "EXPR: $() should NOT be valid")
        
        # Line start detection
        print("\nLine Start Detection:")
        self.assert_token("X = 1", "EXPR_LINE_START", "cmd", "Assignment triggers EXPR mode")
        self.assert_token("if (", "EXPR_LINE_START", "cmd", "Control flow triggers EXPR mode")
        self.assert_token("echo hello", "CMD_LINE_START", "cmd", "Command stays in CMD mode")
        
        print(f"\n=== Results: {self.passed} passed, {self.failed} failed ===\n")
        return self.failed == 0


class TestComplexScenarios:
    """Test complex parsing scenarios"""
    
    def __init__(self):
        self.grammar_dir = Path(__file__).parent.parent
        
    def parse_file(self, content):
        """Parse content and return AST"""
        with tempfile.NamedTemporaryFile(mode='w', suffix='.rsh', delete=False) as f:
            f.write(content)
            temp_file = f.name
            
        try:
            # Use tree-sitter to parse
            result = subprocess.run(
                ["tree-sitter", "parse", temp_file],
                cwd=str(self.grammar_dir),
                capture_output=True,
                text=True
            )
            return result.stdout
        finally:
            os.unlink(temp_file)
            
    def test_scenario(self, name, content, should_parse=True):
        """Test a parsing scenario"""
        print(f"\n{name}:")
        print(f"Input:\n{content}")
        
        ast = self.parse_file(content)
        has_error = "ERROR" in ast or "MISSING" in ast
        
        if should_parse and not has_error:
            print("✓ Parsed successfully")
            return True
        elif not should_parse and has_error:
            print("✓ Correctly detected error")
            return True
        else:
            print(f"✗ Unexpected result")
            print(f"AST:\n{ast[:500]}...")  # First 500 chars
            return False
            
    def run_tests(self):
        """Run complex scenario tests"""
        print("\n=== Complex Parsing Scenarios ===\n")
        
        passed = 0
        total = 0
        
        # Test 1: Basic mode-specific syntax
        total += 1
        if self.test_scenario(
            "Basic CMD mode with expr interpolation",
            'echo "User: ${user}"',
            should_parse=True
        ):
            passed += 1
            
        # Test 2: EXPR mode with cmd execution
        total += 1
        if self.test_scenario(
            "EXPR mode with $rsh()",
            'user = $rsh(whoami)',
            should_parse=True
        ):
            passed += 1
            
        # Test 3: Invalid cross-mode syntax
        total += 1
        if self.test_scenario(
            "Invalid: $rsh() in CMD mode",
            'echo $rsh(whoami)',
            should_parse=False
        ):
            passed += 1
            
        # Test 4: Invalid nested syntax
        total += 1
        if self.test_scenario(
            "Invalid: nested $rsh() in ${}", 
            'echo "${X + $rsh(whoami)}"',
            should_parse=False
        ):
            passed += 1
            
        # Test 5: Valid complex example
        total += 1
        if self.test_scenario(
            "Valid complex multi-line",
            """user = $rsh(whoami)
host = $rsh(hostname)
echo "User ${user} on ${host}"
result = $rsh(ls -la | grep log)""",
            should_parse=True
        ):
            passed += 1
            
        print(f"\n=== Results: {passed}/{total} passed ===\n")
        return passed == total


def main():
    """Run all tests"""
    print("RShell Scanner Test Suite")
    print("=" * 40)
    
    # Run token-level scanner tests
    token_tests = TestModeSpecificSyntax()
    token_success = token_tests.run_tests()
    
    # Run complex scenario tests
    scenario_tests = TestComplexScenarios()
    scenario_success = scenario_tests.run_tests()
    
    if token_success and scenario_success:
        print("\n✅ All tests passed!")
        return 0
    else:
        print("\n❌ Some tests failed")
        return 1


if __name__ == "__main__":
    exit(main())