#!/usr/bin/env python3
"""
Comprehensive AST validation test for RShell grammar.

This test prints detailed AST structures to validate that the grammar
produces well-formed, semantically correct abstract syntax trees.

Usage:
    python test_ast_validation.py                    # Run all validations
    python test_ast_validation.py --category basic   # Run specific category
    python test_ast_validation.py --save-output      # Save to file
"""

import argparse
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Dict, List, Tuple, Optional


GRAMMAR_DIR = Path(__file__).parent.parent


# Comprehensive test cases organized by complexity
AST_VALIDATION_CASES = {
    "basic_literals": [
        {
            "name": "Number assignment",
            "code": "X = 42",
            "description": "Should produce assignment with identifier and number literal",
        },
        {
            "name": "String assignment",
            "code": 'NAME = "production"',
            "description": "Should produce assignment with string literal",
        },
        {
            "name": "Boolean true",
            "code": "ENABLED = true",
            "description": "Should produce assignment with boolean literal",
        },
        {
            "name": "Boolean false",
            "code": "DEBUG = false",
            "description": "Should produce assignment with boolean literal",
        },
    ],
    
    "compound_assignments": [
        {
            "name": "Compound += operator",
            "code": "COUNT += 1",
            "description": "Should produce assignment with += operator and operands",
        },
        {
            "name": "Compound -= operator",
            "code": "VALUE -= 10",
            "description": "Should produce assignment with -= operator and operands",
        },
        {
            "name": "Compound *= operator",
            "code": "TOTAL *= 2",
            "description": "Should produce assignment with *= operator and operands",
        },
    ],
    
    "data_structures": [
        {
            "name": "Simple list",
            "code": "NUMS = [1, 2, 3]",
            "description": "Should produce list with three number elements",
        },
        {
            "name": "Nested list",
            "code": "MATRIX = [[1, 2], [3, 4]]",
            "description": "Should produce list containing two sub-lists",
        },
        {
            "name": "Simple map",
            "code": 'CONFIG = {"key": "value"}',
            "description": "Should produce map with single key-value entry",
        },
        {
            "name": "Multi-entry map",
            "code": 'SERVER = {"name": "web1", "port": 8080}',
            "description": "Should produce map with multiple entries",
        },
        {
            "name": "Empty list",
            "code": "ITEMS = []",
            "description": "Should produce empty list structure",
        },
        {
            "name": "Empty map",
            "code": "CONFIG = {}",
            "description": "Should produce empty map structure",
        },
    ],
    
    "commands_and_pipelines": [
        {
            "name": "Simple command",
            "code": "ls",
            "description": "Should produce command node with identifier",
        },
        {
            "name": "Command with arguments",
            "code": "echo hello world",
            "description": "Should produce command with multiple arguments",
        },
        {
            "name": "Command with string argument",
            "code": 'echo "hello world"',
            "description": "Should produce command with string literal argument",
        },
        {
            "name": "Simple pipeline",
            "code": "ls | grep txt",
            "description": "Should produce pipeline with two commands",
        },
        {
            "name": "Multi-stage pipeline",
            "code": "cat file | grep pattern | wc -l",
            "description": "Should produce pipeline with three commands",
        },
    ],
    
    "variables_and_properties": [
        {
            "name": "Variable reference in command",
            "code": "echo $HOME",
            "description": "Should produce command with variable_reference",
        },
        {
            "name": "Variable in assignment",
            "code": "Y = $X",
            "description": "Should produce assignment with variable_reference",
        },
        {
            "name": "Property access",
            "code": "HOST = SERVER.fqdn",
            "description": "Should produce property_access with identifier and property",
        },
        {
            "name": "Chained property access",
            "code": "PORT = CONFIG.database.port",
            "description": "Should produce property_access with property_chain",
        },
        {
            "name": "Variable with property",
            "code": "VALUE = $SERVER.fqdn",
            "description": "Should produce variable_reference with property_chain",
        },
    ],
    
    "expressions": [
        {
            "name": "Binary expression (addition)",
            "code": "SUM = 10 + 5",
            "description": "Should produce binary_expression with + operator",
        },
        {
            "name": "Binary expression (multiplication)",
            "code": "PRODUCT = 10 * 5",
            "description": "Should produce binary_expression with * operator",
        },
        {
            "name": "Binary expression (comparison)",
            "code": "CHECK = X > 10",
            "description": "Should produce binary_expression with > operator",
        },
        {
            "name": "Logical AND",
            "code": "BOTH = A and B",
            "description": "Should produce binary_expression with 'and' operator",
        },
        {
            "name": "Logical OR",
            "code": "EITHER = A or B",
            "description": "Should produce binary_expression with 'or' operator",
        },
        {
            "name": "Unary expression (not)",
            "code": "NEG = not TRUE",
            "description": "Should produce unary_expression with 'not' operator",
        },
        {
            "name": "Parenthesized expression",
            "code": "CALC = (5 + 3)",
            "description": "Should produce parenthesized_expression containing binary_expression",
        },
        {
            "name": "Complex expression",
            "code": "RESULT = (10 + 5) * 2",
            "description": "Should produce nested expression with correct precedence",
        },
    ],
    
    "control_flow": [
        {
            "name": "Simple if statement",
            "code": "if (X > 10) {\n  Y = 1\n}",
            "description": "Should produce if_statement with condition and block",
        },
        {
            "name": "If-else statement",
            "code": "if (X > 10) {\n  Y = 1\n} else {\n  Y = 0\n}",
            "description": "Should produce if_statement with else_clause",
        },
        {
            "name": "If-elif-else chain",
            "code": "if (X > 10) {\n  Y = 1\n} elif (X > 5) {\n  Y = 2\n} else {\n  Y = 3\n}",
            "description": "Should produce if_statement with elif_clause and else_clause",
        },
        {
            "name": "For loop",
            "code": "for S in SERVERS {\n  echo test\n}",
            "description": "Should produce for_statement with iterator and block",
        },
        {
            "name": "While loop",
            "code": "while (X < 100) {\n  X += 1\n}",
            "description": "Should produce while_statement with condition and block",
        },
    ],
    
    "return_and_loop_control": [
        {
            "name": "Return with value",
            "code": "return 42",
            "description": "Should produce return_statement with number value",
        },
        {
            "name": "Return without value",
            "code": "return",
            "description": "Should produce return_statement without child value",
        },
        {
            "name": "Return in if block",
            "code": "if (X > 0) {\n  return X\n}",
            "description": "Should produce if_statement containing return_statement",
        },
        {
            "name": "Continue statement",
            "code": "continue",
            "description": "Should produce continue_statement",
        },
        {
            "name": "Break statement",
            "code": "break",
            "description": "Should produce break_statement",
        },
        {
            "name": "Continue in loop",
            "code": "for X in LIST {\n  if (X > 5) {\n    continue\n  }\n}",
            "description": "Should produce for_statement with nested if containing continue",
        },
        {
            "name": "Break in loop",
            "code": "while (true) {\n  if (X > 10) {\n    break\n  }\n}",
            "description": "Should produce while_statement with nested if containing break",
        },
    ],
    
    "nested_structures": [
        {
            "name": "If inside for",
            "code": "for X in LIST {\n  if (X > 5) {\n    Y = 1\n  }\n}",
            "description": "Should produce for_statement with nested if_statement",
        },
        {
            "name": "For inside if",
            "code": "if (COUNT > 0) {\n  for ITEM in ITEMS {\n    echo test\n  }\n}",
            "description": "Should produce if_statement with nested for_statement",
        },
        {
            "name": "While inside while",
            "code": "while (X < 10) {\n  while (Y < 5) {\n    Y += 1\n  }\n  X += 1\n}",
            "description": "Should produce nested while_statements with correct scoping",
        },
        {
            "name": "List of maps",
            "code": 'SERVERS = [{"name": "web1"}, {"name": "web2"}]',
            "description": "Should produce list containing map elements",
        },
        {
            "name": "Map with list value",
            "code": 'CONFIG = {"ports": [8080, 8081]}',
            "description": "Should produce map with list value",
        },
    ],
    
    "comments": [
        {
            "name": "Comment alone",
            "code": "# This is a comment",
            "description": "Should produce comment node",
        },
        {
            "name": "Comment after statement",
            "code": "X = 42  # Set X to 42",
            "description": "Should produce assignment with trailing comment",
        },
        {
            "name": "Comment before statement",
            "code": "# Run echo\necho hello",
            "description": "Should produce comment followed by command",
        },
    ],
    
    "mixed_mode": [
        {
            "name": "Commands and assignments in block",
            "code": "if (X > 0) {\n  Y = 1\n  echo test\n  Z = 2\n}",
            "description": "Should produce if_statement with mixed assignment and command statements",
        },
        {
            "name": "Pipeline in for loop",
            "code": "for F in FILES {\n  cat $F | grep pattern\n}",
            "description": "Should produce for_statement with pipeline in block",
        },
        {
            "name": "Multiple statements with semicolon",
            "code": "X = 1; Y = 2; echo done",
            "description": "Should produce separate statements with semicolon separator",
        },
    ],
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


def parse_and_get_tree(code: str) -> Tuple[str, bool]:
    """Parse code and return the full tree structure and success status."""
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
        
        return output, not has_error
    finally:
        Path(tmpfile).unlink()


def format_tree_output(tree: str, indent: int = 0) -> str:
    """Format tree output with indentation."""
    lines = []
    for line in tree.split('\n'):
        if line.strip():
            lines.append(' ' * indent + line)
    return '\n'.join(lines)


def validate_ast_case(test_case: Dict, output_lines: List[str]) -> bool:
    """Validate a single AST test case and print detailed output."""
    name = test_case["name"]
    code = test_case["code"]
    description = test_case["description"]
    
    # Print test header
    output_lines.append("=" * 80)
    output_lines.append(f"TEST: {name}")
    output_lines.append("=" * 80)
    output_lines.append(f"Description: {description}")
    output_lines.append("")
    output_lines.append("Input Code:")
    output_lines.append("-" * 40)
    for line in code.split('\n'):
        output_lines.append(f"  {line}")
    output_lines.append("")
    
    # Parse and get AST
    tree, success = parse_and_get_tree(code)
    
    output_lines.append("Generated AST:")
    output_lines.append("-" * 40)
    output_lines.append(format_tree_output(tree, 2))
    output_lines.append("")
    
    if success:
        output_lines.append("✓ VALID - No parse errors detected")
    else:
        output_lines.append("✗ INVALID - Parse errors or missing nodes detected")
    
    output_lines.append("")
    output_lines.append("")
    
    return success


def run_validation_suite(category_filter: Optional[str] = None) -> Tuple[List[str], int, int]:
    """Run AST validation suite and return output lines and statistics."""
    output_lines = []
    total = 0
    passed = 0
    
    output_lines.append("╔" + "═" * 78 + "╗")
    output_lines.append("║" + " " * 20 + "RSHELL AST VALIDATION SUITE" + " " * 31 + "║")
    output_lines.append("╚" + "═" * 78 + "╝")
    output_lines.append("")
    
    for category, cases in AST_VALIDATION_CASES.items():
        if category_filter and category_filter.lower() not in category.lower():
            continue
        
        output_lines.append("")
        output_lines.append("╔" + "═" * 78 + "╗")
        output_lines.append(f"║  CATEGORY: {category.upper():<65} ║")
        output_lines.append("╚" + "═" * 78 + "╝")
        output_lines.append("")
        
        for test_case in cases:
            total += 1
            if validate_ast_case(test_case, output_lines):
                passed += 1
    
    return output_lines, passed, total


def print_summary(passed: int, total: int, output_lines: List[str]):
    """Print validation summary."""
    failed = total - passed
    pass_rate = (passed / total * 100) if total > 0 else 0
    
    summary = []
    summary.append("")
    summary.append("╔" + "═" * 78 + "╗")
    summary.append("║" + " " * 30 + "VALIDATION SUMMARY" + " " * 30 + "║")
    summary.append("╠" + "═" * 78 + "╣")
    summary.append(f"║  ✓ Valid ASTs:     {passed:<61} ║")
    summary.append(f"║  ✗ Invalid ASTs:   {failed:<61} ║")
    summary.append(f"║  Total Tests:      {total:<61} ║")
    summary.append(f"║  Pass Rate:        {pass_rate:.1f}%{' ' * (58 - len(f'{pass_rate:.1f}%'))} ║")
    summary.append("╚" + "═" * 78 + "╝")
    
    output_lines.extend(summary)
    
    for line in summary:
        print(line)


def main():
    parser = argparse.ArgumentParser(
        description="Comprehensive AST validation for RShell grammar",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python test_ast_validation.py                      # Run all validations
  python test_ast_validation.py --category basic     # Run specific category
  python test_ast_validation.py --save-output        # Save detailed output
  python test_ast_validation.py --no-generate        # Skip grammar generation
        """
    )
    parser.add_argument("--category", "-c", help="Filter by category")
    parser.add_argument("--save-output", "-s", action="store_true", 
                       help="Save detailed output to file")
    parser.add_argument("--no-generate", action="store_true", 
                       help="Skip grammar generation")
    parser.add_argument("--output-file", "-o", default="ast_validation_output.txt",
                       help="Output file name (default: ast_validation_output.txt)")
    args = parser.parse_args()
    
    print("\n╔" + "═" * 78 + "╗")
    print("║" + " " * 20 + "RSHELL AST VALIDATION SUITE" + " " * 31 + "║")
    print("╚" + "═" * 78 + "╝\n")
    
    # Generate grammar unless skipped
    if not args.no_generate:
        if not generate_grammar():
            sys.exit(1)
    
    # Run validation suite
    print("Running AST validation tests...\n")
    output_lines, passed, total = run_validation_suite(args.category)
    
    # Print summary
    print_summary(passed, total, output_lines)
    
    # Save output if requested
    if args.save_output:
        output_file = Path(GRAMMAR_DIR) / "tests" / args.output_file
        with open(output_file, 'w') as f:
            f.write('\n'.join(output_lines))
        print(f"\n✓ Detailed output saved to: {output_file}")
    
    # Exit with appropriate code
    sys.exit(0 if passed == total else 1)


if __name__ == "__main__":
    main()