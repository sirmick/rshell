# RShell Grammar Tests

Test suite for the RShell tree-sitter grammar.

## Quick Start

```bash
# Run all tests
python3 rshell-grammar/tests/test_grammar.py

# Run specific category
python3 rshell-grammar/tests/test_grammar.py --filter commands

# Verbose output (show parse trees)
python3 rshell-grammar/tests/test_grammar.py --verbose

# Skip grammar generation (faster)
python3 rshell-grammar/tests/test_grammar.py --no-generate
```

## Test Files

- **`test_grammar.py`** - Main test harness (22 test cases)
  - Assignments (4 tests)
  - Lists (4 tests)
  - Maps (4 tests)
  - Commands (4 tests)
  - Pipelines (2 tests)
  - Variables (2 tests)
  - Mixed (2 tests)

- **`test_grammar.sh`** - Shell script for quick manual testing
- **`test_rshell_grammar.py`** - Additional grammar tests
- **`test_rshell_grammar_simple.py`** - Simplified test cases
- **`test_rshell_ast_analysis.py`** - AST analysis utilities

## Current Status

✓ **100% pass rate** (22/22 tests passing)

All basic RShell features are working:
- Line-based mode detection (assignments vs commands)
- Data structures (lists, maps, nested)
- Commands with flags (`ls -la`)
- Pipelines (`cat file | grep pattern`)
- Variable references (`$HOME`, `$X`)

## Next Steps

Phase 2: Control flow (if/for/while statements)