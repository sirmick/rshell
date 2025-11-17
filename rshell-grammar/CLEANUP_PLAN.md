# RShell Grammar Cleanup and Phase 2 Enhancement Plan

**Date**: 2025-11-17  
**Status**: In Progress  

## Current State Analysis

### File Structure Issues

1. **Duplicate Test Files** - Multiple test frameworks with overlapping coverage:
   - `tests/test_grammar_simple.py` (38 tests, 100% passing) ✅ PRIMARY
   - `tests/test_rshell_grammar.py` (expects different node types like `rshell_assignment`)
   - `tests/test_rshell_grammar_simple.py` (expects different node types)
   - `tests/test_rshell_ast_analysis.py` (comprehensive but expects wrong node types)
   - `tests/test_scanner_mode_detection.py` (20 tests, 55% passing)
   - `tests/test_grammar.sh` (bash script, basic tests)

2. **Duplicate Grammar Files**:
   - `grammar.js` (289 lines) - Main grammar with line_start, expr_line_start, cmd_line_start
   - `grammar_simple.js` (256 lines) - Simpler version without line_start optimization

3. **Test Data Files** (minimal content):
   - `test_basic.rsh`, `test_assign.rsh`, `test_cmd.rsh`, `test_if.rsh`, `test_simple.rsh`, `test_return.rsh`

### Node Type Inconsistencies

**Current Grammar Produces**:
- `assignment` (not `rshell_assignment`)
- `boolean` (not `boolean_literal`)
- `list` (not `list_literal`)
- `map` (not `map_literal`)
- `binary_expression` (not `rshell_binary_expression`)

**Tests Expect** (incorrect):
- `rshell_assignment`, `boolean_literal`, `list_literal`, `map_literal`

### Test Coverage Gaps

**Working** (from test_grammar_simple.py):
- ✅ Basic assignments (8 tests)
- ✅ Lists (4 tests)
- ✅ Maps (4 tests)  
- ✅ Commands (4 tests)
- ✅ Pipelines (2 tests)
- ✅ Variables (2 tests)
- ✅ Property access (3 tests)
- ✅ Expressions (5 tests)
- ✅ Control flow (4 tests)

**Missing Coverage**:
- ❌ Nested control flow (if inside if, for inside while, etc.)
- ❌ Complex expressions (multiple operators with precedence)
- ❌ Edge cases (empty statements, trailing commas, etc.)
- ❌ Error recovery (invalid syntax)
- ❌ Mixed mode blocks (CMD and EXPR in same block)
- ❌ Comments (defined but not tested)
- ❌ Multiple statements on one line (semicolon separated)

### Scanner Mode Detection Issues

**Passing** (11/20 tests):
- ✅ Assignments: `X = 42`, `COUNT = 100`, `_private = 10`
- ✅ Control flow: `if`, `for`, `while`
- ✅ Commands: `echo hello`, `ls`, `ls -la`, `grep pattern`
- ✅ Pipelines: `echo test | grep t`

**Failing** (9/20 tests):
- ❌ Standalone `elif`, `else`, `}` (expected - only work in context)
- ❌ `return`, `continue`, `yield` (not in grammar yet)
- ❌ Paths: `/bin/ls`, `./script.sh`, `cat file.txt` (path detection not implemented)

## Cleanup Tasks

### Phase 1: Consolidation (High Priority)

1. **Choose Primary Grammar**: `grammar.js` (has optimization)
2. **Archive/Delete**: `grammar_simple.js` (move to archive or delete)
3. **Choose Primary Test Suite**: `tests/test_grammar_simple.py`
4. **Fix Test Expectations**: Update other test files to expect correct node types
5. **Remove Test Data Files**: Use inline test cases instead

### Phase 2: Test Enhancement (High Priority)

6. **Expand test_grammar_simple.py**:
   - Add nested control flow tests
   - Add complex expression tests
   - Add comment tests
   - Add edge case tests
   - Add error recovery tests

7. **Fix Scanner Tests**:
   - Remove unrealistic tests (standalone `elif`, `else`)
   - Add path detection to scanner if needed
   - Add tests for mode transitions

### Phase 3: Documentation (Medium Priority)

8. **Update Documentation**:
   - Mark which files are primary/archived
   - Update test count in docs
   - Add troubleshooting section

9. **Create Test Guide**:
   - How to run tests
   - How to add new tests
   - Test categories explained

### Phase 4: Grammar Improvements (Medium Priority)

10. **Add Missing Features**:
    - `return` statement
    - `continue` statement  
    - `break` statement (if needed)
    - Path literals for commands

11. **Improve Error Messages**:
    - Add better conflict resolution
    - Document ambiguous cases

## Action Plan

### Week 1: Cleanup and Test Consolidation

**Day 1-2**:
- [x] Analyze current state
- [ ] Create cleanup plan
- [ ] Archive/remove duplicate files
- [ ] Fix node type expectations in tests

**Day 3-4**:
- [ ] Expand test_grammar_simple.py with Phase 2 tests
- [ ] Add 20+ new test cases
- [ ] Test nested structures
- [ ] Test complex expressions

**Day 5**:
- [ ] Fix scanner mode detection issues
- [ ] Add path detection (if needed)
- [ ] Achieve >90% scanner test pass rate

### Week 2: Grammar Enhancement

**Day 1-2**:
- [ ] Add `return`/`continue`/`break` to grammar
- [ ] Test control flow statements
- [ ] Update scanner keywords

**Day 3-4**:
- [ ] Add comprehensive error handling tests
- [ ] Test recovery from syntax errors
- [ ] Document error patterns

**Day 5**:
- [ ] Final testing and validation
- [ ] Update all documentation
- [ ] Mark Phase 2 complete

## Success Criteria

- ✅ 100% test pass rate on primary test suite (60+ tests)
- ✅ >90% scanner mode detection pass rate
- ✅ All Phase 2 features working (control flow, expressions, property access)
- ✅ Clean file structure (no duplicates)
- ✅ Comprehensive documentation
- ✅ All basic control flow statements (`return`, `continue`, `break`)

## Files to Keep

**Primary Files**:
- `grammar.js` - Main grammar
- `src/scanner.c` - External scanner
- `tests/test_grammar_simple.py` - Primary test suite
- `tests/test_scanner_mode_detection.py` - Scanner-specific tests
- `build_grammar.sh` - Build script

**Documentation**:
- `CURRENT_STATUS.md` - Updated status
- `LINE_BASED_MODE_DETECTION.md` - Technical explanation
- `TREE_SITTER_EXTERNAL_SCANNER.md` - Scanner guide
- `PHASE_2_MODE_DETECTION_COMPLETE.md` - Phase 2 summary
- `GET_STARTED_EXTERNAL_SCANNER.md` - Development guide
- `tests/README.md` - Test documentation

## Files to Archive/Remove

**To Archive** (move to `archive/` folder):
- `grammar_simple.js` - Simpler version (keep for reference)
- `tests/test_rshell_grammar.py` - Wrong node type expectations
- `tests/test_rshell_grammar_simple.py` - Wrong node type expectations
- `tests/test_rshell_ast_analysis.py` - Wrong node type expectations
- `tests/test_grammar.sh` - Replaced by Python test suite

**To Remove** (delete):
- `test_*.rsh` files (use inline test cases instead)

## Next Steps

1. Execute cleanup (archive/delete files)
2. Fix node type expectations
3. Add 30+ new test cases
4. Fix scanner issues
5. Add missing grammar features
6. Update documentation
7. Mark Phase 2 complete