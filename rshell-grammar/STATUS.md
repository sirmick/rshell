# RShell Grammar - Current Status

**Last Updated**: 2025-11-17  
**Phase**: Phase 2 Complete  
**Test Coverage**: 96.8% (60/62 tests passing)

---

## Quick Summary

The RShell tree-sitter grammar implements **automatic line-based mode detection** that distinguishes between:
- **EXPR mode**: Assignments, control flow, structured data
- **CMD mode**: Shell commands, pipelines

**Status**: Production-ready for all implemented features with excellent test coverage.

---

## Test Results

### Grammar Tests: 60/62 passing (96.8%)

| Category | Tests | Status |
|----------|-------|--------|
| Assignments | 8 | ✅ 100% |
| Lists | 4 | ✅ 100% |
| Maps | 4 | ✅ 100% |
| Commands | 4 | ✅ 100% |
| Pipelines | 2 | ✅ 100% |
| Variables | 2 | ✅ 100% |
| Property Access | 3 | ✅ 100% |
| Expressions | 5 | ✅ 100% |
| Control Flow | 4 | ✅ 100% |
| Return Statements | 3 | ✅ 100% |
| Loop Control | 4 | ✅ 100% |
| Nested Control Flow | 4 | ✅ 100% |
| Complex Expressions | 6 | ✅ 100% |
| Comments | 3 | ✅ 100% |
| Edge Cases | 7 | ⚠️ 71% (5/7) |
| Mixed Mode Blocks | 2 | ✅ 100% |
| Semicolons | 2 | ✅ 100% |

### Failing Tests (2)

1. **Multiline list**: `SERVERS = [\n  1,\n  2\n]` - Scanner emits line_start inside list
2. **Multiline map**: `CONFIG = {\n  "key": "value"\n}` - Scanner emits line_start inside map

**Workaround**: Use single-line syntax: `ITEMS = [1, 2, 3]` ✅

---

## Supported Features

### ✅ Data Types
- Numbers: `42`, `3.14`, `-10`
- Strings: `"hello"`, `'world'`
- Booleans: `true`, `false`
- Lists: `[1, 2, 3]`, `[{"id": 1}, {"id": 2}]`
- Maps: `{"key": "value", "port": 8080}`

### ✅ Assignments
- Simple: `X = 42`
- Compound: `COUNT += 1`, `VALUE -= 10`, `TOTAL *= 2`, `RESULT /= 5`

### ✅ Control Flow
- If/elif/else: `if (X > 10) { Y = 1 } else { Y = 0 }`
- For loops: `for ITEM in LIST { echo $ITEM }`
- While loops: `while (X < 100) { X += 1 }`
- Nested structures supported
- Return statements: `return 42`
- Loop control: `continue`, `break`

### ✅ Expressions
- Arithmetic: `+`, `-`, `*`, `/`
- Comparison: `>`, `<`, `==`, `!=`, `>=`, `<=`
- Logical: `and`, `or`, `not`
- Parentheses: `(5 + 3) * 2`

### ✅ Commands and Pipelines
- Commands: `echo hello`, `ls -la`
- Pipelines: `cat file | grep pattern | wc -l`
- Variable references: `echo $HOME`

### ✅ Advanced Features
- Property access: `SERVER.fqdn`, `CONFIG.db.port`
- Variable with properties: `$SERVER.fqdn`
- Comments: `# This is a comment`
- Trailing commas in lists/maps
- Semicolon statement separators

---

## Build & Test

### Build Everything

```bash
# From project root
./build.sh
```

Builds grammar + Elixir project + runs all tests

### Build Grammar Only

```bash
cd rshell-grammar
./build_grammar.sh
```

### Run Tests

```bash
# All grammar tests
cd rshell-grammar
python3 tests/test_grammar_simple.py

# Specific category
python3 tests/test_grammar_simple.py --filter control_flow

# Verbose (show parse trees)
python3 tests/test_grammar_simple.py --verbose
```

---

## Known Limitation: Multiline Structures

**Problem**: 2 tests fail for multiline lists/maps

```rshell
# Fails:
ITEMS = [
  1,    # ← line_start emitted here, parser confused
  2
]

# Works:
ITEMS = [1, 2, 3]  # Single line - perfect!
```

**Why**: Scanner doesn't know we're inside brackets (called before parser consumes `[`)

**Workaround**: Use single-line syntax

**Future**: Phase 3 will add bracket tracking for 100% coverage

---

## Architecture

### External Scanner (`src/scanner.c`)

- **Purpose**: Automatic mode detection
- **How**: Analyzes each line start, emits appropriate token
- **Optimization**: Only emits mode tokens on changes
- **State**: 3 bytes (line position, last mode, initialization flag)

### Grammar (`grammar.js`)

- **Lines**: 289
- **Accepts**: External tokens from scanner
- **Defines**: All syntax rules
- **Handles**: Mode transitions automatically

---

## Files

**Core:**
- `grammar.js` - Grammar definition
- `src/scanner.c` - Mode detection
- `build_grammar.sh` - Build script

**Tests:**
- `tests/test_grammar_simple.py` - 62 test cases
- `tests/test_scanner_mode_detection.py` - Scanner tests

**Documentation:**
- `README.md` - Overview
- `STATUS.md` - This file (comprehensive status)
- `LINE_BASED_MODE_DETECTION.md` - Technical deep dive
- `TREE_SITTER_EXTERNAL_SCANNER.md` - Scanner guide

---

## Example Code

```rshell
# Assignments (EXPR mode auto-detected)
SERVERS = ["web1", "web2", "web3"]
COUNT = 0

# Commands (CMD mode auto-detected)
echo "Starting deployment..."

# Control flow (EXPR mode)
for SERVER in SERVERS {
  # Commands work inside EXPR blocks!
  ssh $SERVER "systemctl restart app"
  
  if (STATUS == 0) {
    COUNT += 1
  }
}

# Back to CMD mode automatically
echo "Deployment complete"
```

---

## Next Steps (Phase 3)

1. **Multiline structures** - Bracket tracking → 100% coverage
2. **Path literals** - `/bin/ls`, `./script.sh`
3. **Shell function** - `shell()` for explicit commands
4. **Interpolation** - `{}` in commands

---

**Quick Test**: `cd rshell-grammar && python3 tests/test_grammar_simple.py`