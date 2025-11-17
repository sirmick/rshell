# RShell Syntax Implementation Plan

**Status**: ✅ Phase 2 Complete - Automatic Mode Detection
**Timeline**: 2-3 weeks total
**Approach**: Clean, minimal, purpose-built grammar

---

## Current Status

**✅ PHASE 2 COMPLETE**: Automatic line-based mode detection implemented!
**Grammar**: `rshell-grammar/grammar.js` (~274 lines)
**Scanner**: `rshell-grammar/src/scanner.c` (213 lines) - Mode detection with optimization
**Test Results**: 38/38 tests passing (100%)
**Test Suite**: `test_grammar_simple.py` with filter/verbose modes

### Quick Start

```bash
# Edit grammar
vim rshell-grammar/grammar_simple.js

# Run tests (auto-generates grammar)
python test_grammar_simple.py

# Run specific category with verbose output
python test_grammar_simple.py --filter commands --verbose
```

---

## Phase 1: Core Shell (Week 1)

**Goal**: Basic shell functionality with clear command/assignment distinction.

### Grammar Structure
```javascript
program     := statement*
statement   := assignment | command | pipeline | comment
assignment  := IDENTIFIER '=' expression
command     := cmd_name argument*
pipeline    := command ('|' command)*
```

### Week 1 Checklist
- [ ] Commands parse: `ls`, `echo hello`, `cat file`
- [ ] Assignments parse: `X = 42`, `NAME = "test"`
- [ ] Pipelines parse: `ls | grep txt`
- [ ] Variables work: `echo $X`
- [ ] Comments work: `# comment`

### Examples to Support

```bash
# Basic commands
ls
echo hello
cat file.txt

# Commands with arguments
ls -la
echo "hello world"
git commit -m "message"

# Pipelines
ls | grep txt
cat file | sort | uniq

# Assignments
X = 42
NAME = "Alice"
DEBUG = true

# Variable references
echo $X
Y = $X
```

---

## Phase 2: Data Structures (Week 2)

**Goal**: Structured data types with intuitive syntax.

### Grammar Extensions
```javascript
expression := literal | variable | binary_op | property_access
literal    := number | string | boolean | list | map
list       := '[' (expression (',' expression)*)? ']'
map        := '{' (key ':' value (',' key ':' value)*)? '}'
property   := variable ('.' field | '[' index ']')*
```

### Week 2 Checklist
- [ ] Lists: `[1, 2, 3]`, nested lists
- [ ] Maps: `{"key": "value"}`, nested maps
- [ ] Property access: `$SERVER.port`, `$ITEMS[0]`
- [ ] Mixed structures: lists of maps, maps with lists

### Examples to Support

```bash
# Lists
NUMBERS = [1, 2, 3, 4, 5]
MATRIX = [[1, 2], [3, 4]]
SERVERS = ["web1", "web2", "db1"]

# Maps
CONFIG = {"host": "localhost", "port": 8080}
DATABASE = {
    "primary": {"host": "db1", "port": 5432},
    "replica": {"host": "db2", "port": 5432}
}

# Property access
HOST = $CONFIG.host
PORT = $SERVER.port
FIRST = $ITEMS[0]
NESTED = $CONFIG.database.host
```

---

## Phase 3: Expressions & Control Flow (Week 3)

**Goal**: Expression evaluation and modern control structures.

### Grammar Extensions
```javascript
if_stmt    := 'if' expression block ('elif' expression block)* ('else' block)?
for_stmt   := 'for' IDENTIFIER 'in' expression block
while_stmt := 'while' expression block
block      := '{' statement* '}'
expression := ... | comparison | logical | arithmetic | grouped
```

### Week 3 Checklist
- [ ] Arithmetic: `5 + 3`, `10 * 2`, `(5 + 3) * 2`
- [ ] Comparison: `X > 5`, `Y == 10`, `Z != 0`
- [ ] Logical: `and`, `or`, `not`
- [ ] If/elif/else: `if X > 5 { ... }`
- [ ] For loops: `for item in $list { ... }`
- [ ] While loops: `while X < 10 { ... }`

### Examples to Support

```bash
# Arithmetic
X = 5 + 3
Y = (10 + 5) * 2
TOTAL = $PRICE * $QUANTITY

# Comparisons
if $COUNT > 0 {
    echo "Found items"
}

# Control flow
for S in $SERVERS {
    echo "Server: $S.name"
}

while $COUNT < 10 {
    COUNT = $COUNT + 1
}

# Complex conditions
if $STATUS == "ready" and $COUNT > 5 {
    process_data
}
```

---

## Testing Strategy

### Test Categories
1. **assignments** - Variable assignments with different types
2. **commands** - Basic commands and arguments
3. **pipelines** - Single and multi-stage pipelines
4. **lists** - List literals and nesting
5. **maps** - Map literals and nesting
6. **variables** - Variable references
7. **mixed** - Complex combinations

### Test Workflow

```bash
# Run all tests
python test_grammar_simple.py

# Test specific category
python test_grammar_simple.py --filter commands

# Verbose output (show parse trees)
python test_grammar_simple.py --verbose --filter assignments

# Skip grammar generation (for quick re-runs)
python test_grammar_simple.py --no-generate
```

### Adding New Tests

Edit `test_grammar_simple.py` and add to `TEST_CASES` dict:

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

---

## Success Metrics

### ✅ Phase 1 Complete:
- [x] Clean grammar template created
- [x] Test infrastructure ready
- [x] **100% command tests passing**
- [x] **100% assignment tests passing**
- [x] **100% pipeline tests passing**
- [x] Basic data types working (numbers, strings, booleans)

### ✅ Phase 2 Complete:
- [x] 100% list tests passing
- [x] 100% map tests passing
- [x] Property access working
- [x] Nested structures working
- [x] **Automatic mode detection implemented**
- [x] Expression evaluation working
- [x] Control flow (if/for/while) working
- [x] Comparison operators working
- [x] Logical operators working

### Phase 3 In Progress:
- [ ] shell() function implementation
- [ ] {} interpolation in commands
- [ ] Result object (.success, .stdout, .stderr, .exit_code)
- [ ] String methods (.contains(), .split(), .length)

---

## Grammar Development Tips

### 1. Start Simple

Begin with the absolute minimum:
```javascript
program: $ => repeat($._statement),
_statement: $ => $.command,
command: $ => seq($.identifier, repeat($.identifier)),
identifier: $ => /[a-zA-Z_][a-zA-Z0-9_]*/,
```

### 2. Add One Feature at a Time

Don't try to implement everything at once. Add features incrementally:
1. Commands → 2. Assignments → 3. Strings → 4. Numbers → etc.

### 3. Use Verbose Mode

When a test fails, run with verbose to see the parse tree:
```bash
python test_grammar_simple.py --filter commands --verbose
```

### 4. Common Pitfalls

- **Precedence**: Use `prec()` to resolve conflicts
- **Whitespace**: Tree-sitter handles whitespace automatically
- **Conflicts**: Run `tree-sitter generate` to see conflict warnings
- **Testing**: Test each grammar change before moving on

---

## Implementation Notes

### Why Fresh Start?

Modifying the bash grammar failed because:
- **0/5 command tests passing** - Basic commands broken
- **1,260 lines of complexity** - Bash baggage we don't need
- **Fundamental conflicts** - Text-based vs data-oriented paradigms
- **3-4+ weeks to fix** - Longer than building from scratch

### Key Design Decisions

1. **Pattern-based parsing**: `IDENTIFIER = VALUE` triggers assignment mode
2. **No ambiguity**: Every syntax element has one clear meaning
3. **Simple precedence**: Minimal precedence rules needed
4. **Clean separation**: Commands vs assignments vs control flow

### Files to Focus On

**Active Development:**
- `rshell-grammar/grammar_simple.js` - The grammar itself
- `test_grammar_simple.py` - Test harness
- `RSHELL_SYNTAX_DESIGN.md` - Complete syntax spec

**Reference:**
- `IMPLEMENTATION_GUIDE.md` - Runtime implementation details
- `CURRENT_STATUS.md` - Overall project status

---

## Timeline Summary

| Phase | Duration | Status | Deliverable |
|-------|----------|--------|-------------|
| 1 | 1 week | ✅ Complete | Commands + assignments + pipelines + data structures |
| 2 | 1 week | ✅ Complete | **Automatic mode detection** + control flow + expressions + property access |
| 3 | 1 week | 🚧 In Progress | shell() and {} interpolation |
| **Total** | **3 weeks** | **Phase 2** | **Complete enhanced syntax** |

---

**Last Updated**: 2025-11-17
**Milestone Achieved**: ✅ Automatic mode detection - 38/38 tests passing (100%)
**Next Milestone**: shell() function and {} interpolation