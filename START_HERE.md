# RShell - Getting Started

**Last Updated**: 2025-11-23

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

## Design Documentation by Subsystem

RShell is organized into several key subsystems, each with detailed design documentation:

### 🏗️ Architecture & Runtime
- **[ARCHITECTURE_DESIGN.md](ARCHITECTURE_DESIGN.md)** - System architecture, component relationships, data flow
- **[RUNTIME_DESIGN.md](RUNTIME_DESIGN.md)** - Runtime execution model, context management, GenServer architecture
- **[EXECUTION_FRAME_DESIGN.md](EXECUTION_FRAME_DESIGN.md)** - Frame stack, scope management, output isolation

### 💻 Builtin Commands
- **[BUILTIN_DESIGN.md](BUILTIN_DESIGN.md)** - Builtin system, namespace organization, I/O design, all 16 implemented builtins

### 🔄 Control Flow
- **[CONTROL_FLOW_DESIGN.md](CONTROL_FLOW_DESIGN.md)** - If/for/while/case statements, condition evaluation, loop execution

### 📦 Variables & Types
- **[ENV_VAR_DESIGN.md](ENV_VAR_DESIGN.md)** - Environment variables, native types (maps/lists/numbers), bracket notation, JSON support

### 📝 Syntax & Grammar
- **[RSHELL_SYNTAX_DESIGN.md](RSHELL_SYNTAX_DESIGN.md)** - RShell syntax specification, extensions to bash
- **[rshell-grammar/README.md](rshell-grammar/README.md)** - Tree-sitter grammar overview
- **[rshell-grammar/PARSER_DESIGN.md](rshell-grammar/PARSER_DESIGN.md)** - Parser architecture and implementation
- **[rshell-grammar/STATUS.md](rshell-grammar/STATUS.md)** - Current grammar implementation status

### 🧪 Testing
- **[TEST_GUIDE.md](TEST_GUIDE.md)** - Testing patterns, CLIHelper usage, best practices
- **[UNIT_TESTS.md](UNIT_TESTS.md)** - Detailed unit test coverage documentation

### 📚 Complete Documentation Index
- **[DOCUMENTATION_INDEX.md](DOCUMENTATION_INDEX.md)** - Comprehensive map of all 20 documentation files

---

## Getting Help

**New to RShell?** Start with:
1. This file (START_HERE.md) for build instructions
2. [DOCUMENTATION_INDEX.md](DOCUMENTATION_INDEX.md) for complete documentation map
3. [ARCHITECTURE_DESIGN.md](ARCHITECTURE_DESIGN.md) for system overview
4. [TEST_GUIDE.md](TEST_GUIDE.md) for testing patterns

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
  
  # Run command from EXPR mode using $rsh()
  result = $rsh(ssh ${S.fqdn} uptime)
  
  # Commands also work inside EXPR blocks!
  echo Checking server
  
  # CMD mode can use ${} for expression interpolation
  echo "Server: ${S.fqdn}"
}

# Back to CMD mode automatically
echo "Health check complete"
```

---

**Need help?** Check the documentation files or run `./build_grammar.sh` to verify everything works!