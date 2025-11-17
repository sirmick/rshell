# RShell - Getting Started

**Status**: ✅ Phase 2 Complete - 96.8% Test Coverage (60/62 tests passing)
**Last Updated**: 2025-11-17

---

## Quick Start

### Option 1: Build Everything (Recommended)

```bash
# From project root - builds Elixir project AND grammar
./build.sh
```

This will:
1. Build RShell grammar (tree-sitter)
2. Build Elixir project with Rust NIF
3. Run all tests

### Option 2: Build Grammar Only

```bash
# Just the tree-sitter grammar
cd rshell-grammar
./build_grammar.sh
```

This will:
1. Generate parser from [`grammar.js`](rshell-grammar/grammar.js:1)
2. Compile external scanner ([`src/scanner.c`](rshell-grammar/src/scanner.c:1))
3. Run grammar tests (should show 60/62 passing - 96.8%)

---

## Testing the Grammar

### Run All Tests

```bash
cd rshell-grammar
python3 tests/test_grammar_simple.py
```

**Expected output:**
```
✓ Passed: 60
✗ Failed: 2
Total:    62

Pass rate: 96.8%
```

**Known failing tests:** Multiline lists and maps (Phase 3 feature)

### Run Specific Tests

```bash
# Test specific category
python3 tests/test_grammar_simple.py --filter control_flow

# Verbose mode (show parse trees)
python3 tests/test_grammar_simple.py --verbose

# Skip regeneration (faster)
python3 tests/test_grammar_simple.py --no-generate
```

### Test Scanner Mode Detection

```bash
python3 tests/test_scanner_mode_detection.py
```

### Parse Individual Files

```bash
# Parse and show AST
tree-sitter parse examples/rshell/01_server_health_monitor.rsh

# Just check for errors
tree-sitter parse examples/rshell/01_server_health_monitor.rsh --quiet
```

---

## Grammar Development Workflow

### Step 1: Edit the Grammar

```bash
# Edit the grammar file
vim rshell-grammar/grammar.js

# Or edit the scanner
vim rshell-grammar/src/scanner.c
```

### Step 2: Generate Parser

```bash
cd rshell-grammar
tree-sitter generate
```

This compiles `grammar.js` and `src/scanner.c` into:
- `src/parser.c` - Generated parser
- `src/node-types.json` - Node type definitions
- `src/grammar.json` - Grammar specification

### Step 3: Test Your Changes

```bash
# Quick test (skip regeneration)
python3 tests/test_grammar_simple.py --no-generate

# Full test (regenerate + test)
python3 tests/test_grammar_simple.py

# Or use the build script
./build_grammar.sh
```

---

## Understanding the Grammar

### Files Structure

```
rshell-grammar/
├── grammar.js              # Main grammar definition (~274 lines)
├── src/
│   ├── scanner.c          # External scanner for mode detection (213 lines)
│   ├── parser.c           # Generated parser (auto-generated)
│   └── grammar.json       # Grammar spec (auto-generated)
├── tests/
│   ├── test_grammar_simple.py           # Full grammar test suite (38 tests)
│   └── test_scanner_mode_detection.py   # Scanner-specific tests (20 tests)
├── examples/rshell/       # Example RShell scripts
└── build_grammar.sh       # Build script
```

### Key Concepts

1. **External Scanner** (`src/scanner.c`):
   - Determines EXPR vs CMD mode for each line
   - Emits tokens: `line_start`, `expr_line_start`, `cmd_line_start`
   - Optimizes by only emitting mode tokens on changes

2. **Grammar Rules** (`grammar.js`):
   - Accepts line_start tokens from scanner
   - Defines syntax for assignments, control flow, commands, expressions
   - Handles blocks, property access, operators

3. **Mode Detection**:
   - **EXPR mode**: Lines starting with `X =`, `if`, `for`, `while`
   - **CMD mode**: Everything else (shell commands)
   - Automatic - no manual mode switching needed!

---

## Common Tasks

### Add a New Test

Edit `rshell-grammar/tests/test_grammar_simple.py`:

```python
TEST_CASES = {
    "your_category": [
        {
            "name": "Test description",
            "code": "X = 42",
            "expect": ["assignment", "number"],
        },
    ],
}
```

### Debug a Parse Error

```bash
# Parse with verbose output
cd rshell-grammar
tree-sitter parse /tmp/test.rsh

# Or use Python test with verbose
python3 tests/test_grammar_simple.py --filter your_test --verbose
```

### Check for Grammar Conflicts

```bash
cd rshell-grammar
tree-sitter generate
# Look for "Unresolved conflict" messages
```

---

## Build Process Details

### What `tree-sitter generate` Does:

1. **Reads** `grammar.js` and `src/scanner.c`
2. **Compiles** the grammar into a parser state machine
3. **Generates** `src/parser.c` (the actual parser code)
4. **Validates** for conflicts and ambiguities
5. **Creates** `src/node-types.json` and `src/grammar.json`

### Manual Build Steps (if needed):

```bash
# 1. Generate parser
cd rshell-grammar
tree-sitter generate

# 2. The scanner is automatically compiled by tree-sitter
#    No separate compilation step needed!

# 3. Run tests
python3 tests/test_grammar_simple.py --no-generate

# 4. Parse a file
tree-sitter parse examples/rshell/01_server_health_monitor.rsh
```

---

## Current Status

### ✅ What Works (96.8% coverage - 60/62 tests passing):

**Core Features:**
- ✅ Automatic mode detection (EXPR vs CMD)
- ✅ Assignments: `X = 42`, compound operators (`+=`, `-=`, `*=`, `/=`)
- ✅ Data types: numbers, strings, booleans, lists, maps
- ✅ Commands: `echo hello`, `ls -la`, pipelines
- ✅ Control flow: `if`/`elif`/`else`, `for`, `while` with nested blocks
- ✅ Expressions: arithmetic, comparisons, logical operators
- ✅ Property access: `SERVER.fqdn`, `$CONFIG.port`
- ✅ Comments: `# comment`
- ✅ Semicolons: Multiple statements on one line

### ⚠️ Known Limitations (2 failing tests):

- ❌ Multiline lists: `ITEMS = [\n  1,\n  2\n]` (use single-line instead)
- ❌ Multiline maps: `CONFIG = {\n  "key": "value"\n}` (use single-line instead)

**Workaround:** Use single-line syntax: `ITEMS = [1, 2, 3]` ✅

### 🔜 Phase 3 (Planned):

- Multiline structure support (requires bracket tracking in scanner)
- `return`, `continue`, `break` statements
- `shell()` function for explicit command execution
- `{}` interpolation for expressions in commands
- Path literals: `/bin/ls`, `./script.sh`

---

## Documentation

**Essential Files:**
- [`rshell-grammar/README.md`](rshell-grammar/README.md:1) - Grammar overview and quick reference
- [`rshell-grammar/CURRENT_STATUS.md`](rshell-grammar/CURRENT_STATUS.md:1) - Project status and test results
- [`RSHELL_SYNTAX_DESIGN.md`](RSHELL_SYNTAX_DESIGN.md:1) - Complete syntax specification

**Technical Deep Dives:**
- [`rshell-grammar/LINE_BASED_MODE_DETECTION.md`](rshell-grammar/LINE_BASED_MODE_DETECTION.md:1) - Mode detection explained
- [`rshell-grammar/TREE_SITTER_EXTERNAL_SCANNER.md`](rshell-grammar/TREE_SITTER_EXTERNAL_SCANNER.md:1) - Scanner implementation guide
- [`rshell-grammar/PHASE_2_MODE_DETECTION_COMPLETE.md`](rshell-grammar/PHASE_2_MODE_DETECTION_COMPLETE.md:1) - Implementation details

---

## Example RShell Code

```rshell
# Automatic EXPR mode detection
SERVERS = [
  {'fqdn':'web1.example.com', 'port':22},
  {'fqdn':'web2.example.com', 'port':22}
]

# Automatic CMD mode detection
echo "Starting health check..."

# Control flow (EXPR mode detected)
for S in SERVERS {
  # Assignment inside block
  STATUS = 0
  
  # Commands work inside EXPR blocks!
  echo Checking server
}

# Back to CMD mode automatically
echo "Health check complete"
```

---

**Need help?** Check the documentation files or run `./build_grammar.sh` to verify everything works!