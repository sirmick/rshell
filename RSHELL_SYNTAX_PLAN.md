# RShell Syntax Implementation Plan

**Status**: Phase 3 In Progress - Cross-Mode Features
**Timeline**: 3-4 weeks total
**Approach**: Modern shell breaking with bash for clean, structured programming

---

## Current Status

**Phase 3 IN PROGRESS**: Mode-specific constructs (`${}` and `$rsh()`) 
**Grammar**: `rshell-grammar/grammar.js` (~444 lines)
**Scanner**: `rshell-grammar/src/scanner.c` (382 lines) - Two-mode detection with cross-mode features
**Test Results**: 
- Basic features: 69/69 tests passing (100%)
- Mode-specific: 19/23 tests passing (82.6%)

### Quick Start

```bash
# Build and test
cd rshell-grammar
./build_grammar.sh

# Run specific tests
python3 tests/test_mode_specific_syntax.py
python3 tests/test_scanner_mode_detection.py
```

---

## Design Philosophy

**RShell breaks with bash intentionally** to create a modern shell with:
- **Two distinct modes**: EXPR for programming, CMD for shell operations
- **Structured data types**: Native lists, maps, objects (not just strings)
- **Modern control flow**: Python-like if/for/while with blocks
- **Cross-mode features**: `${}` interpolation in CMD, `$rsh()` execution in EXPR

---

## The Two-Mode System

### Mode Detection (Automatic)

Mode is determined by **how each line starts**:

#### EXPR Mode Triggers
- Keywords: `if`, `elif`, `else`, `for`, `while`, `return`, `continue`, `break`
- Assignments: `X =`, `COUNT +=` 
- Property access: `SERVER.port`
- Function calls: `calculate()`
- Block closings: `}`

#### CMD Mode (Default)
- Everything else (commands, paths, executables)

### Cross-Mode Constructs

| Mode | Construct | Purpose | Example |
|------|-----------|---------|---------|
| CMD | `${expr}` | Interpolate expressions | `echo ${user.name}` |
| EXPR | `$rsh(cmd)` | Execute commands | `result = $rsh(ls -la)` |

---

## Implementation Phases

### ✅ Phase 1: Core Shell (Complete)

**Deliverables**: Basic parsing, data structures, mode detection

**Features Implemented**:
- [x] Line-based mode detection
- [x] Basic data types (numbers, strings, booleans)
- [x] Lists and maps with nesting
- [x] Simple assignments (`X = 42`)
- [x] Direct commands (`echo hello`)
- [x] Pipelines (`ls | grep txt`)
- [x] Comments (`# comment`)

**Test Coverage**: 100% (all basic tests passing)

---

### ✅ Phase 2: Control Flow & Expressions (Complete)

**Deliverables**: Modern programming constructs

**Features Implemented**:
- [x] If/elif/else statements
- [x] For loops (`for item in list`)
- [x] While loops
- [x] Arithmetic operators (`+`, `-`, `*`, `/`)
- [x] Comparison operators (`>`, `<`, `==`, `!=`, `>=`, `<=`)
- [x] Logical operators (`and`, `or`, `not`)
- [x] Property access (`SERVER.port`, `CONFIG.db.host`)
- [x] Array indexing (`ITEMS[0]`, `ITEMS[-1]`)
- [x] Compound assignments (`+=`, `-=`, `*=`, `/=`)

**Test Coverage**: 100% (control flow and expressions working)

---

### 🔧 Phase 3: Cross-Mode Features (In Progress)

**Goal**: Enable seamless interaction between EXPR and CMD modes

**Planned Features**:
- [x] `${}` expression interpolation in CMD mode (partially working)
- [x] `$rsh()` command execution in EXPR mode (needs fixes)
- [ ] Pipeline support in cross-mode constructs
- [ ] Property access on `$rsh()` results
- [ ] Nested interpolation support

**Current Issues**:
1. Grammar integration bugs (lines 379-408 in grammar.js)
2. Pipeline support incomplete
3. Property access on command results failing
4. Test coverage: 82.6% (19/23 tests passing)

**Test Failures**:
```
- ${} in pipeline
- $rsh() in pipeline  
- $rsh() with property access
- Chained assignments with $rsh()
```

---

### 📋 Phase 4: Advanced Shell Features (Planned)

**Goal**: Modern redirection and command sequencing

**Planned Features**:
- [ ] Output redirection: `>`, `>>`
- [ ] Input redirection: `<`
- [ ] Error redirection: `(stderr)>`, `(stderr+stdout)>`
- [ ] Command chaining: `&&`, `||`, `;`
- [ ] Background execution: `&`
- [ ] Job control

---

## Testing Strategy

### Test Structure

```
tests/
├── test_grammar_simple.py        # Basic features (69 tests)
├── test_mode_specific_syntax.py  # Cross-mode (23 tests)
├── test_scanner_mode_detection.py # Scanner unit tests
└── test_phase3.py               # Advanced features
```

### Running Tests

```bash
# All basic tests
python3 tests/test_grammar_simple.py

# Mode-specific features
python3 tests/test_mode_specific_syntax.py

# Verbose output for debugging
python3 tests/test_grammar_simple.py --verbose --filter control

# Scanner tests
python3 tests/test_scanner_mode_detection.py
```

### Adding Tests

Edit test files and add to appropriate category:

```python
TEST_CASES = {
    "category_name": [
        {
            "name": "Test description",
            "code": "X = 42",
            "expect": ["assignment", "number"],
            "should_pass": True
        },
    ],
}
```

---

## Grammar Architecture

### Core Components

1. **scanner.c** (382 lines)
   - Tracks line boundaries
   - Detects mode based on line start patterns
   - Manages `${}` and `$rsh()` depth tracking
   - Handles parenthesis balancing

2. **grammar.js** (444 lines)
   - Tree-sitter grammar rules
   - Declares 8 external tokens from scanner
   - Defines syntax for both modes

3. **External Tokens**
   ```c
   NEWLINE                  // Line boundaries
   LINE_START               // Generic line start
   EXPR_LINE_START         // EXPR mode line start
   CMD_LINE_START          // CMD mode line start
   CMD_EXPR_INTERP_START   // ${ in CMD mode
   CMD_EXPR_INTERP_END     // } closing ${}
   EXPR_CMD_EXEC_START     // $rsh( in EXPR mode
   EXPR_CMD_EXEC_END       // ) closing $rsh()
   ```

---

## Current Work Items

### Immediate Fixes Needed

1. **Grammar bugs** (30 min)
   - Remove unused token declarations (lines 18-19)
   - Fix `$rsh()` implementation (lines 406-419)
   - Fix `$()` implementation (lines 377-391)

2. **Pipeline support** (1 hour)
   - Add pipeline handling in `$rsh()` content
   - Support pipes in `${}` interpolation

3. **Property access** (30 min)
   - Enable `.property` on `$rsh()` results
   - Fix chained assignments with `$rsh()`

### Documentation Updates

1. ✅ **RSHELL_SYNTAX_DESIGN.md** - Updated with two-mode philosophy
2. ⏳ **RSHELL_SYNTAX_PLAN.md** - This document (updated)
3. [ ] **README.md** - Update feature list and examples
4. [ ] **STATUS.md** - Reflect actual implementation state

---

## Success Metrics

### Phase Completion Criteria

| Phase | Target | Current | Status |
|-------|--------|---------|--------|
| Phase 1 | 100% basic tests | 100% | ✅ Complete |
| Phase 2 | 100% control flow | 100% | ✅ Complete |
| Phase 3 | 100% cross-mode | 82.6% | 🔧 In Progress |
| Phase 4 | Redirection working | 0% | 📋 Not Started |

### Overall Progress

- **Lines of Code**: ~850 (grammar + scanner + tests)
- **Test Coverage**: 88/92 tests passing (95.6% overall)
- **Features Complete**: 75% of planned features
- **Time Invested**: ~2.5 weeks
- **Time Remaining**: ~1.5 weeks

---

## Design Decisions & Rationale

### Why Break with Bash?

1. **Structured Data**: Lists and maps as first-class citizens
2. **Type Safety**: Variables have types, not just strings
3. **Clean Syntax**: Clear visual distinction between modes
4. **Better Errors**: Parser knows context for meaningful messages
5. **Modern Features**: Property access, methods, proper scoping

### Why Two Modes?

1. **Clarity**: Always clear if you're programming or commanding
2. **Optimization**: Parser can optimize for each mode
3. **Safety**: Can't accidentally execute code as commands
4. **Expressiveness**: Best of both worlds without compromise

### Why `${}` and `$rsh()`?

1. **Visual Distinction**: Immediately clear what's happening
2. **No Ambiguity**: `${}` = expression, `$rsh()` = command
3. **Parser Friendly**: Unambiguous tokens for tree-sitter
4. **Extensible**: Room for future constructs like `$async()`

---

## Timeline Summary

| Week | Focus | Status | Notes |
|------|-------|--------|-------|
| 1 | Core parsing + data structures | ✅ Complete | Ahead of schedule |
| 2 | Control flow + expressions | ✅ Complete | All tests passing |
| 3 | Cross-mode features | 🔧 Current | 82.6% complete |
| 4 | Redirection + polish | 📋 Next | Final features |

---

**Last Updated**: 2025-11-18
**Current Focus**: Fixing grammar integration for `$rsh()` and `${}` constructs
**Next Milestone**: 100% cross-mode test coverage