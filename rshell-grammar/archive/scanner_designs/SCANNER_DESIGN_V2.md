# RShell Scanner Design V2 - Specification

**Version**: 2.0  
**Date**: 2025-11-19  
**Status**: Design Phase  
**Purpose**: Complete redesign of scanner to fix architectural issues

---

## Executive Summary

The current scanner has fundamental architectural issues mixing line-based and nested mode detection. This design separates these concerns clearly, fixing infinite loops, missing end tokens, and state management issues.

---

## Core Principles

### 1. **Two Separate Mode Systems**

**Base Mode (Line-Level)**
- Each line has a base mode: `CMD` or `EXPR`
- Determined by line's first non-whitespace content
- Does NOT use a stack (lines don't nest)
- Emits tokens at line boundaries

**Nested Mode (Inline Transitions)**
- Used ONLY for `$rsh()` and `${}` inline constructs
- DOES use a stack (these nest)
- Emits tokens at construct boundaries `(`, `)`, `{`, `}`

### 2. **Clear Token Emission Rules**

**CRITICAL INSIGHT from Grammar Analysis:**
The grammar uses `optional($.expr_end)` and `optional($.cmd_end)` in sections, meaning:
- END tokens are NOT required for line-based mode changes
- The grammar handles newlines as implicit section boundaries
- Scanner only needs to emit START tokens when mode changes
- END tokens are ONLY for nested constructs (`$rsh()`, `${}`)

**Line-Based Tokens:**
- `EXPR_START` - Beginning of EXPR mode line (when entering EXPR)
- `CMD_START` - Beginning of CMD mode line (when entering CMD)
- NO end tokens for line-based changes (grammar handles via newlines)

**Nested Tokens:**
- `EXPR_START` - Opening `${` 
- `EXPR_END` - Closing `}` of `${}`
- `CMD_START` - Opening `$rsh(`
- `CMD_END` - Closing `)` of `$rsh()`

### 3. **Zero-Width Tokens**

All scanner tokens are zero-width:
- Use `mark_end()` before any lookahead
- Scanner peeks but doesn't consume
- Grammar consumes the actual characters

---

## State Structure

```c
typedef struct {
  // Base mode tracking (line-level)
  Mode base_mode;           // Current line's mode (MODE_UNINIT, CMD, or EXPR)
  bool at_line_start;       // Are we at column 0?
  
  // Nested mode tracking (inline constructs)
  Mode nested_stack[16];    // Stack for $rsh() and ${} ONLY
  int nested_depth;         // Current nesting depth (0 = not nested)
  
  // Lookahead buffer (for pattern detection)
  char lookahead_buffer[32];
  int lookahead_len;
} Scanner;
```

**Key Changes:**
- `base_mode` replaces `last_emitted_mode` (clearer intent)
- `at_line_start` replaces `has_emitted` (clearer condition)
- `nested_stack` is ONLY for inline constructs
- Removed `in_lookahead` flag (not needed with proper design)

---

## Mode Detection Algorithm

### Line Start Detection

**When:** `lexer->get_column(lexer) == 0` OR `at_line_start == true`

**Process:**
1. Skip whitespace (space, tab)
2. If `#` → skip line (return false)
3. If `\n` or EOF → skip (return false)
4. Peek ahead to determine mode (non-consuming)
5. If mode differs from `base_mode`:
   - Update `base_mode`
   - Emit appropriate token
6. Set `at_line_start = false`

**EXPR Mode Indicators:**
- Keywords: `if`, `for`, `while`, `return`, `elif`, `else`, `break`, `continue`
- Assignment: `IDENTIFIER =` or `IDENTIFIER OP=` where OP is `+`, `-`, `*`, `/`

**CMD Mode:**
- Everything else (default)

### Inline Transition Detection

**`$rsh(` Detection:**
1. See `$` at any position
2. Peek ahead: check for `rsh(`
3. If matched AND `valid_symbols[CMD_START]`:
   - Push current mode to `nested_stack`
   - `nested_depth++`
   - Emit `CMD_START` (zero-width)

**`${` Detection:**
1. See `$` at any position
2. Peek ahead: check for `{`
3. If matched AND `valid_symbols[EXPR_START]`:
   - Push current mode to `nested_stack`
   - `nested_depth++`
   - Emit `EXPR_START` (zero-width)

**`)` Detection (Close `$rsh()`):**
1. See `)` at any position
2. If `nested_depth > 0` AND `valid_symbols[CMD_END]`:
   - `nested_depth--`
   - Pop from `nested_stack`
   - Emit `CMD_END` (zero-width)

**`}` Detection (Close `${}`):**
1. See `}` at any position
2. If `nested_depth > 0` AND `valid_symbols[EXPR_END]`:
   - `nested_depth--`
   - Pop from `nested_stack`
   - Emit `EXPR_END` (zero-width)

---

## Lookahead Implementation

### Requirements
- Must NOT consume characters
- Must detect patterns reliably
- Must handle edge cases (EOF, newlines)

### New `peek_pattern` Function

```c
// Peek ahead to check for a specific pattern
// Returns true if pattern matches, false otherwise
// Does NOT consume any characters (truly non-consuming)
static bool peek_pattern(TSLexer *lexer, const char *pattern) {
  int32_t saved_pos = /* save lexer position somehow */;
  
  for (int i = 0; pattern[i] != '\0'; i++) {
    if (lexer->lookahead != pattern[i]) {
      /* restore position */
      return false;
    }
    lexer->advance(lexer, false);
  }
  
  /* restore position */
  return true;
}
```

**Problem:** Tree-sitter doesn't provide position save/restore!

### Alternative: Build Buffer WITHOUT Advancing

```c
// Peek ahead into buffer without consuming
// Builds a buffer of upcoming characters for pattern matching
static bool peek_ahead_buffer(TSLexer *lexer, Scanner *scanner, int max_chars) {
  scanner->lookahead_len = 0;
  
  // Mark position - this ensures zero-width token
  lexer->mark_end(lexer);
  
  // We'll advance to peek, but mark_end means token is zero-width
  int32_t ch = lexer->lookahead;
  int count = 0;
  
  // Skip leading whitespace
  while ((ch == ' ' || ch == '\t') && count < max_chars) {
    lexer->advance(lexer, true);  // Skip as whitespace
    ch = lexer->lookahead;
    count++;
  }
  
  // Collect pattern characters
  while (ch != 0 && ch != '\n' && ch != '\r' && 
         scanner->lookahead_len < 31 && count < max_chars) {
    
    // Store character if ASCII
    if (ch < 128) {
      scanner->lookahead_buffer[scanner->lookahead_len++] = (char)ch;
    }
    
    // Stop at delimiters
    if (ch == ' ' || ch == '\t' || ch == '=' || 
        ch == '(' || ch == '{' || ch == ';') {
      // Include the delimiter
      break;
    }
    
    lexer->advance(lexer, false);
    ch = lexer->lookahead;
    count++;
  }
  
  scanner->lookahead_buffer[scanner->lookahead_len] = '\0';
  return scanner->lookahead_len > 0;
}
```

**Key Point:** After calling `mark_end()`, subsequent `advance()` calls don't consume from the grammar's perspective. The token emitted is zero-width.

---

## Pattern Matching Functions

### Keyword Detection

```c
static const char *EXPR_KEYWORDS[] = {
  "if", "for", "while", "return", "elif", "else", "break", "continue", NULL
};

static bool is_keyword(const char *str, int len) {
  for (int i = 0; EXPR_KEYWORDS[i] != NULL; i++) {
    int kw_len = strlen(EXPR_KEYWORDS[i]);
    if (len >= kw_len && 
        strncmp(str, EXPR_KEYWORDS[i], kw_len) == 0 &&
        (len == kw_len || !isalnum(str[kw_len]))) {
      return true;
    }
  }
  return false;
}
```

### Assignment Detection

```c
static bool is_assignment(const char *str, int len) {
  if (len < 2) return false;
  
  // Must start with identifier character
  if (!isalpha(str[0]) && str[0] != '_') return false;
  
  // Look for = operator
  for (int i = 1; i < len; i++) {
    // Found equals
    if (str[i] == '=') {
      // Simple assignment: X =
      if (i > 0 && (isalnum(str[i-1]) || str[i-1] == '_')) {
        return true;
      }
      // Compound assignment: X +=, X -=, etc.
      if (i > 1 && strchr("+-*/", str[i-1])) {
        return true;
      }
    }
    
    // Still in identifier
    if (isalnum(str[i]) || str[i] == '_') continue;
    
    // Hit space - might be "X ="
    if (str[i] == ' ') continue;
    
    // Hit something else - not an assignment
    break;
  }
  
  return false;
}
```

---

## Main Scan Function Flow

```c
bool tree_sitter_rshell_external_scanner_scan(
    void *payload, 
    TSLexer *lexer, 
    const bool *valid_symbols) {
  
  Scanner *scanner = (Scanner *)payload;
  
  // === PART 1: Line Start Detection ===
  if (lexer->get_column(lexer) == 0) {
    scanner->at_line_start = true;
  }
  
  if (scanner->at_line_start) {
    // Skip whitespace
    while (lexer->lookahead == ' ' || lexer->lookahead == '\t') {
      lexer->advance(lexer, true);
    }
    
    // Skip comments and empty lines
    if (lexer->lookahead == '#' || 
        lexer->lookahead == '\n' || 
        lexer->lookahead == 0) {
      return false;
    }
    
    // Determine mode via lookahead
    if (!peek_ahead_buffer(lexer, scanner, 20)) {
      return false;
    }
    
    Mode new_mode = (is_keyword(scanner->lookahead_buffer, scanner->lookahead_len) ||
                     is_assignment(scanner->lookahead_buffer, scanner->lookahead_len))
                    ? MODE_EXPR : MODE_CMD;
    
    // CRITICAL: Emit START token ONLY when mode changes OR first line
    // The grammar's optional(end) means newlines implicitly end sections
    // We don't need to emit END tokens for line-based transitions
    
    if (new_mode != scanner->base_mode || scanner->base_mode == MODE_UNINIT) {
      scanner->base_mode = new_mode;
      scanner->at_line_start = false;
      
      if (new_mode == MODE_EXPR && valid_symbols[EXPR_START]) {
        lexer->result_symbol = EXPR_START;
        return true;
      } else if (new_mode == MODE_CMD && valid_symbols[CMD_START]) {
        lexer->result_symbol = CMD_START;
        return true;
      }
    }
    
    scanner->at_line_start = false;
  }
  
  // === PART 2: Inline Transition Detection ===
  
  // Check for $rsh( or ${
  if (lexer->lookahead == '$') {
    lexer->mark_end(lexer);
    lexer->advance(lexer, false);
    
    // Check for ${
    if (lexer->lookahead == '{' && valid_symbols[EXPR_START]) {
      push_nested(scanner, scanner->base_mode);
      lexer->result_symbol = EXPR_START;
      return true;
    }
    
    // Check for $rsh(
    if (lexer->lookahead == 'r') {
      lexer->advance(lexer, false);
      if (lexer->lookahead == 's') {
        lexer->advance(lexer, false);
        if (lexer->lookahead == 'h') {
          lexer->advance(lexer, false);
          if (lexer->lookahead == '(' && valid_symbols[CMD_START]) {
            push_nested(scanner, scanner->base_mode);
            lexer->result_symbol = CMD_START;
            return true;
          }
        }
      }
    }
  }
  
  // Check for ) to close $rsh()
  if (lexer->lookahead == ')' && 
      scanner->nested_depth > 0 && 
      valid_symbols[CMD_END]) {
    lexer->mark_end(lexer);
    pop_nested(scanner);
    lexer->result_symbol = CMD_END;
    return true;
  }
  
  // Check for } to close ${}
  if (lexer->lookahead == '}' && 
      scanner->nested_depth > 0 && 
      valid_symbols[EXPR_END]) {
    lexer->mark_end(lexer);
    pop_nested(scanner);
    lexer->result_symbol = EXPR_END;
    return true;
  }
  
  return false;
}
```

---

## Test Cases

### Basic Assignment
```rshell
X = 42
```
**Expected tokens:**
1. `EXPR_START` (zero-width at position 0)
2. Grammar parses `X = 42`

### Mode Switch
```rshell
X = 42
echo hello
```
**Expected tokens:**
1. `EXPR_START` (line 1, zero-width at col 0)
2. Grammar parses `X = 42` and newline (newline implicitly ends expr_section)
3. `CMD_START` (line 2, zero-width at col 0)
4. Grammar parses `echo hello`

**Key:** The grammar's `optional($.expr_end)` means sections end at newlines without needing an END token.

### Nested Inline
```rshell
result = $rsh(ls -la)
```
**Expected tokens:**
1. `EXPR_START` (line start)
2. Grammar parses `result =`
3. `CMD_START` (at `$rsh(`, zero-width)
4. Grammar parses `ls -la`
5. `CMD_END` (at `)`, zero-width)

### Deep Nesting
```rshell
X = $rsh(echo ${Y})
```
**Expected tokens:**
1. `EXPR_START` (line start)
2. Grammar parses `X =`
3. `CMD_START` (at `$rsh(`)
4. Grammar parses `echo`
5. `EXPR_START` (at `${`)
6. Grammar parses `Y`
7. `EXPR_END` (at `}`)
8. `CMD_END` (at `)`)

---

## Implementation Checklist

- [ ] Update Scanner struct
- [ ] Implement `peek_ahead_buffer` correctly
- [ ] Implement `is_keyword` helper
- [ ] Implement `is_assignment` helper
- [ ] Implement `push_nested` / `pop_nested` helpers
- [ ] Rewrite main `scan` function
- [ ] Update serialization for new state
- [ ] Test with simple assignment
- [ ] Test with mode switches
- [ ] Test with inline constructs
- [ ] Test with deep nesting
- [ ] Update SCANNER_CURRENT_RULES.md to match new design

---

## Migration Strategy

1. **Create scanner_v2.c** alongside current scanner
2. **Test extensively** with existing test suite
3. **Once stable**, replace scanner.c
4. **Update documentation** to match new design

---

## Open Questions

1. **Newline handling**: Should scanner emit anything at newlines, or let grammar handle entirely?
   - **Answer**: Grammar handles via its rules. Scanner only emits at line START.

2. **Error recovery**: How should scanner behave on malformed input?
   - **Answer**: Return false, let grammar handle errors.

3. **Column tracking**: Should we track more position info?
   - **Answer**: No, `get_column()` is sufficient.

---

## Success Criteria

- [ ] All 69 basic tests pass
- [ ] No infinite loops
- [ ] Clear, maintainable code
- [ ] Proper separation of line vs nested modes
- [ ] Zero-width tokens work correctly
- [ ] Nested constructs work to depth 16