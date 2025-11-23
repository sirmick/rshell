# Scanner Infinite Loop - Root Cause Analysis

**Date**: 2025-11-19  
**Status**: CRITICAL BUG - Infinite loop in Tree-sitter integration  
**Symptom**: Parser hangs/times out on simple input like `X = 2`

---

## Root Cause

**Scanner-Grammar Mismatch**: The scanner is trying to emit mode tokens (`expr_start`, `cmd_start`) based on line analysis, but the grammar expects these tokens at specific structural points.

### The Problem

```cpp
// Scanner (WRONG approach):
if (at_line_start && is_assignment(line)) {
  emit(EXPR_START);  // Emit whenever we see assignment
}
```

```javascript
// Grammar expects:
program: $ => repeat(choice(
  $.expr_section,   // MUST start with expr_start
  $.cmd_section,    // MUST start with cmd_start
))

expr_section: $ => seq(
  $.expr_start,     // Grammar EXPECTS this token here
  repeat(content),
  optional($.expr_end)
)
```

**Mismatch**: Scanner emits tokens when IT decides, not when grammar requests via `valid_symbols[]`.

---

## Why It Creates Infinite Loop

1. Scanner peeks ahead, sees `X = 2`
2. Scanner emits `EXPR_START` token
3. Grammar tries to parse `expr_section`
4. Grammar expects content after `expr_start`
5. Scanner is called again **at the same position** (we didn't consume the `X`)
6. Scanner sees `X = 2` again
7. Scanner tries to emit `EXPR_START` again
8. **INFINITE LOOP** ♾️

---

## What We Tried

### ❌ Attempt 1: Save/Restore Lexer Position
```cpp
TSLexer saved = *lexer;
std::string line = consume_until('\n');
*lexer = saved;  // Restore
```
**Result**: Still loops - doesn't solve the fundamental mismatch

### ❌ Attempt 2: Only Emit on Mode Change
```cpp
if (new_mode != current_mode) {
  emit(new_mode_token);
}
```
**Result**: Still loops - first line always triggers mode change from Uninit

### ✅ Attempt 3: RAII LexerGuard (Added but not yet used)
```cpp
class LexerGuard {
  ~LexerGuard() { if (!committed_) restore(); }
};
```
**Status**: Safety mechanism added, but doesn't solve root cause

---

## The Real Solution

**Scanner must be PASSIVE, not ACTIVE**:

```cpp
bool Scanner::scan(void* lexer_ptr, const bool* valid_symbols) {
  // Check FIRST: Is grammar asking for a mode token?
  if (valid_symbols[EXPR_START] || valid_symbols[CMD_START]) {
    // Grammar wants a mode token - determine which one
    return emit_mode_token_if_appropriate();
  }
  
  // Grammar is NOT asking for mode tokens
  return false;
}
```

**Key principle**: Only do work when `valid_symbols[]` says the grammar wants that token.

---

## Next Steps

1. **Refactor scan() to check valid_symbols FIRST**
2. **Only analyze line content when grammar requests mode tokens**
3. **Test with simple input**: `X = 2`
4. **Verify**: No infinite loop, correct parse tree

---

## C++ Unit Tests Status

✅ **13/13 tests passing** - Pattern matching, serialization, state management all work  
❌ **Tree-sitter integration** - Infinite loop prevents testing

The scanner logic is correct in isolation, but the integration pattern is wrong.