#!/usr/bin/env python3
"""
Comprehensive AST analysis test suite for RShell grammar.
Tests Phase 1 completion and identifies edge cases and issues.
"""

import argparse
import subprocess
import sys
import json
from pathlib import Path
from typing import Dict, List, Any

GRAMMAR_DIR = Path(__file__).parent / "vendor" / "tree-sitter-rshell"

class TestResult:
    def __init__(self, name: str, code: str, expected: List[str], actual: str, passed: bool, error_msg: str = ""):
        self.name = name
        self.code = code
        self.expected = expected
        self.actual = actual
        self.passed = passed
        self.error_msg = error_msg

def parse_code(code: str) -> str:
    """Parse code using tree-sitter parse CLI."""
    import tempfile
    
    with tempfile.NamedTemporaryFile(mode='w', suffix='.sh', delete=False) as f:
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

def extract_node_types(output: str) -> set:
    """Extract node types from tree-sitter parse output."""
    import re
    matches = re.findall(r'\((\w+)', output)
    return set(matches)

def analyze_ast(output: str) -> Dict[str, Any]:
    """Analyze AST structure for issues."""
    analysis = {
        "has_errors": "ERROR" in output,
        "node_types": extract_node_types(output),
        "depth": output.count("("),
        "is_complete": "(program" in output and not "ERROR" in output,
        "error_lines": []
    }
    
    # Extract ERROR lines
    for line in output.split('\n'):
        if 'ERROR' in line:
            analysis["error_lines"].append(line.strip())
    
    return analysis

def run_test(name: str, code: str, expected: List[str]) -> TestResult:
    """Run a single test case."""
    output = parse_code(code)
    analysis = analyze_ast(output)
    
    if analysis["has_errors"]:
        return TestResult(name, code, expected, output, False, 
                         f"Parse error: {', '.join(analysis['error_lines'])}")
    
    missing = set(expected) - analysis["node_types"]
    if missing:
        return TestResult(name, code, expected, output, False, 
                         f"Missing nodes: {sorted(missing)}")
    
    return TestResult(name, code, expected, output, True)

# Comprehensive test cases
TEST_CASES = [
    # === PHASE 1: Core RShell Syntax ===
    {
        "category": "Boolean Literals",
        "tests": [
            ("Boolean: true", "X = true", ["boolean_literal", "rshell_assignment"]),
            ("Boolean: false", "Y = false", ["boolean_literal", "rshell_assignment"]),
            ("Boolean in list", "L = [true, false]", ["boolean_literal", "list_literal"]),
            ("Boolean in map", 'M = {"enabled": true}', ["boolean_literal", "map_literal"]),
        ]
    },
    {
        "category": "Number Literals",
        "tests": [
            ("Integer", "X = 42", ["number", "rshell_assignment"]),
            ("Float", "Y = 3.14", ["number", "rshell_assignment"]),
            ("Negative", "Z = -10", ["number", "rshell_assignment"]),
            ("Scientific notation", "E = 1.5e10", ["number", "rshell_assignment"]),
        ]
    },
    {
        "category": "String Literals",
        "tests": [
            ("Double quotes", 'S = "hello"', ["string", "rshell_assignment"]),
            ("Single quotes", "S = 'world'", ["string", "rshell_assignment"]),
            ("Escaped quotes", 'S = "hello \\"world\\""', ["string", "rshell_assignment"]),
            ("Multi-line string", 'S = "line1\nline2"', ["string", "rshell_assignment"]),
        ]
    },
    {
        "category": "List Literals",
        "tests": [
            ("Empty list", "L = []", ["list_literal", "rshell_assignment"]),
            ("Simple list", "L = [1, 2, 3]", ["list_literal", "number"]),
            ("Mixed types", 'L = [1, "two", true]', ["list_literal", "number", "string", "boolean_literal"]),
            ("Nested lists", "L = [[1, 2], [3, 4]]", ["list_literal"]),
            ("Deeply nested", "L = [[[1]]]", ["list_literal"]),
            ("Trailing comma", "L = [1, 2, 3,]", ["list_literal"]),
        ]
    },
    {
        "category": "Map Literals",
        "tests": [
            ("Empty map", "M = {}", ["map_literal", "rshell_assignment"]),
            ("Single entry", 'M = {"key": "value"}', ["map_literal", "map_entry"]),
            ("Multiple entries", 'M = {"a": 1, "b": 2}', ["map_literal", "map_entry"]),
            ("Nested maps", 'M = {"outer": {"inner": 1}}', ["map_literal"]),
            ("Mixed values", 'M = {"num": 42, "str": "text", "bool": true}', ["map_literal", "number", "string", "boolean_literal"]),
            ("Trailing comma", 'M = {"a": 1, "b": 2,}', ["map_literal"]),
        ]
    },
    {
        "category": "Complex Structures",
        "tests": [
            ("List of maps", 'L = [{"id": 1}, {"id": 2}]', ["list_literal", "map_literal"]),
            ("Map of lists", 'M = {"items": [1, 2, 3]}', ["map_literal", "list_literal"]),
            ("Server config", 'SERVERS = [{"name": "web1", "port": 8080}]', ["list_literal", "map_literal"]),
            ("Deep nesting", 'D = {"a": [{"b": {"c": [1, 2]}}]}', ["map_literal", "list_literal"]),
        ]
    },
    {
        "category": "Binary Expressions",
        "tests": [
            ("Addition", "X = 5 + 3", ["rshell_binary_expression"]),
            ("Subtraction", "Y = 10 - 2", ["rshell_binary_expression"]),
            ("Multiplication", "Z = 4 * 3", ["rshell_binary_expression"]),
            ("Division", "A = 15 / 3", ["rshell_binary_expression"]),
            ("Modulo", "B = 10 % 3", ["rshell_binary_expression"]),
            ("Chained operations", "C = 1 + 2 + 3", ["rshell_binary_expression"]),
            ("Parentheses", "D = (5 + 3) * 2", ["rshell_binary_expression"]),
        ]
    },
    {
        "category": "Variable References",
        "tests": [
            ("Simple variable", "Y = $X", ["variable_expansion", "rshell_assignment"]),
            ("Property access", "PORT = $SERVER.port", ["property_access"]),
            ("Array index", "FIRST = $ITEMS[0]", ["array_access"]),
            ("Nested access", "HOST = $CONFIG.database.host", ["property_access"]),
        ]
    },
    {
        "category": "Edge Cases",
        "tests": [
            ("Assignment without spaces", "X=value", ["rshell_assignment"]),
            ("Multiple assignments", "X = 1; Y = 2", ["rshell_assignment"]),
            ("Unicode strings", 'S = "こんにちは"', ["string", "rshell_assignment"]),
            ("Empty string", 'S = ""', ["string", "rshell_assignment"]),
            ("Very long identifier", "VERY_LONG_VARIABLE_NAME_HERE = 42", ["rshell_assignment"]),
        ]
    },
    {
        "category": "Commands (Should work but currently failing)",
        "tests": [
            ("Simple command", "echo hello", ["command"]),
            ("Command with string", 'echo "hello world"', ["command", "string"]),
            ("Command with variable", "echo $VAR", ["command", "variable_expansion"]),
            ("Pipeline", "cat file | grep pattern", ["pipeline", "command"]),
            ("Command substitution", "RESULT = $(ls -la)", ["command_substitution"]),
        ]
    },
    {
        "category": "Comparison Operators (Future)",
        "tests": [
            ("Greater than", "X > 10", ["comparison_expression"]),
            ("Less than", "Y < 5", ["comparison_expression"]),
            ("Equals", "Z == 12", ["comparison_expression"]),
            ("Not equals", "A != 0", ["comparison_expression"]),
            ("Greater or equal", "B >= 5", ["comparison_expression"]),
            ("Less or equal", "C <= 10", ["comparison_expression"]),
        ]
    },
    {
        "category": "Logical Operators (Future)",
        "tests": [
            ("AND", "X > 5 and Y < 10", ["logical_expression"]),
            ("OR", "A == 0 or B == 0", ["logical_expression"]),
            ("NOT", "not DEBUG", ["unary_expression"]),
            ("Complex", "(X > 5 and Y < 10) or Z == 0", ["logical_expression"]),
        ]
    },
]

def run_all_tests(verbose: bool = False) -> List[TestResult]:
    """Run all test cases."""
    results = []
    
    for category in TEST_CASES:
        if verbose:
            print(f"\n{'='*60}")
            print(f"Category: {category['category']}")
            print(f"{'='*60}")
        
        for name, code, expected in category["tests"]:
            result = run_test(name, code, expected)
            results.append(result)
            
            if verbose or not result.passed:
                status = "✅" if result.passed else "❌"
                print(f"\n{status} {name}")
                print(f"   Code: {repr(code)}")
                if not result.passed:
                    print(f"   Error: {result.error_msg}")
                    print(f"   Expected: {result.expected}")
                    print(f"   Found: {sorted(extract_node_types(result.actual))}")
    
    return results

def generate_report(results: List[TestResult]) -> Dict[str, Any]:
    """Generate detailed analysis report."""
    report = {
        "total": len(results),
        "passed": sum(1 for r in results if r.passed),
        "failed": sum(1 for r in results if not r.passed),
        "pass_rate": 0,
        "categories": {},
        "issues": [],
        "recommendations": []
    }
    
    if report["total"] > 0:
        report["pass_rate"] = (report["passed"] / report["total"]) * 100
    
    # Analyze by category
    for category in TEST_CASES:
        cat_name = category["category"]
        cat_results = [r for r in results if any(r.name == test[0] for test in category["tests"])]
        report["categories"][cat_name] = {
            "total": len(cat_results),
            "passed": sum(1 for r in cat_results if r.passed),
            "failed": sum(1 for r in cat_results if not r.passed)
        }
    
    # Identify common issues
    error_patterns = {}
    for result in results:
        if not result.passed:
            if "Parse error" in result.error_msg:
                error_patterns["parse_errors"] = error_patterns.get("parse_errors", 0) + 1
            elif "Missing nodes" in result.error_msg:
                error_patterns["missing_nodes"] = error_patterns.get("missing_nodes", 0) + 1
    
    # Generate issues list
    if error_patterns.get("parse_errors", 0) > 0:
        report["issues"].append(f"Parse errors in {error_patterns['parse_errors']} tests")
    if error_patterns.get("missing_nodes", 0) > 0:
        report["issues"].append(f"Missing expected nodes in {error_patterns['missing_nodes']} tests")
    
    # Generate recommendations
    if report["categories"].get("Commands (Should work but currently failing)", {}).get("failed", 0) > 0:
        report["recommendations"].append("Fix command parsing - currently all command tests fail")
    if report["categories"].get("Variable References", {}).get("failed", 0) > 0:
        report["recommendations"].append("Implement variable expansion and property access")
    if report["categories"].get("Comparison Operators (Future)", {}).get("failed", 0) > 0:
        report["recommendations"].append("Add comparison operators for Phase 2")
    
    return report

def main():
    parser = argparse.ArgumentParser(description="Comprehensive RShell AST Analysis")
    parser.add_argument("--verbose", "-v", action="store_true")
    parser.add_argument("--json", action="store_true", help="Output JSON report")
    parser.add_argument("--no-generate", action="store_true", help="Skip grammar generation")
    args = parser.parse_args()
    
    print("🔬 RShell AST Analysis Suite")
    print("="*60)
    
    # Generate grammar if needed
    if not args.no_generate:
        print("🔧 Generating grammar...")
        result = subprocess.run(
            ["tree-sitter", "generate"],
            cwd=str(GRAMMAR_DIR),
            capture_output=True,
            text=True
        )
        if result.returncode != 0:
            print(f"❌ Failed to generate grammar: {result.stderr}")
            sys.exit(1)
        print("✅ Grammar generated\n")
    
    # Run tests
    results = run_all_tests(args.verbose)
    
    # Generate report
    report = generate_report(results)
    
    if args.json:
        print(json.dumps(report, indent=2))
    else:
        print("\n" + "="*60)
        print("📊 TEST SUMMARY")
        print("="*60)
        print(f"Total Tests: {report['total']}")
        print(f"✅ Passed: {report['passed']}")
        print(f"❌ Failed: {report['failed']}")
        print(f"📈 Pass Rate: {report['pass_rate']:.1f}%")
        
        print("\n📁 BY CATEGORY:")
        for cat_name, cat_data in report["categories"].items():
            status = "✅" if cat_data["failed"] == 0 else "⚠️" if cat_data["failed"] < cat_data["total"] else "❌"
            print(f"  {status} {cat_name}: {cat_data['passed']}/{cat_data['total']}")
        
        if report["issues"]:
            print("\n⚠️ ISSUES IDENTIFIED:")
            for issue in report["issues"]:
                print(f"  - {issue}")
        
        if report["recommendations"]:
            print("\n💡 RECOMMENDATIONS:")
            for rec in report["recommendations"]:
                print(f"  - {rec}")
        
        print("\n" + "="*60)
        if report["failed"] > 0:
            print("❌ PHASE 1 STATUS: INCOMPLETE")
            print("   Commands and some edge cases need fixing")
        else:
            print("✅ PHASE 1 STATUS: COMPLETE")
    
    sys.exit(0 if report["failed"] == 0 else 1)

if __name__ == "__main__":
    main()