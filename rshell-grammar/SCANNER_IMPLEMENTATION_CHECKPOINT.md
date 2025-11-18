# Scanner Implementation Checkpoint

**Date**: 2025-11-18
**Status**: In Progress - Foundation Complete, Debugging Needed

## Implementation Overview

### Scanner Design (`src/scanner.c`)

**Token Set (6 tokens):**
```c
enum TokenType {
  CMD_START,       // 0: Entering CMD mode
  CMD_END,         // 1: Exiting CMD mode
  EXPR_START,      // 2: Entering EXPR mode
  EXPR_END,        // 3: Exiting EXPR mode
  ERROR_IN_CMD,    // 4: Syntax error in CMD mode
  ERROR_IN_EXPR,   // 5: Syntax error in EXPR mode
};
```

**Scanner State:**
```c
typedef struct {
  Mode mode_stack[16];      // Stack of nested modes
  int mode_depth;           // Current depth
  Mode last_emitted_mode;   // Track last emitted mode
  bool has_emitted;         // Have we emitted any token?
} Scanner;
```

**Key Features:**
1. **Mode Change Optimization**: Only emits tokens when mode actually changes
2. **Mode Stack**: Supports nesting (e.g., `$rsh(echo ${X})`)
3. **Line-Based Detection**: Analyzes line content to determine EXPR vs CMD
4. **Comment Handling**: Skips comment and empty lines when detecting mode
5. **Explicit Mode Switches**: Handles `$rsh(`, `${`, `)`, `}`

### Grammar Design (`grammar.js`)

**External Tokens:**
```javascript
externals: $ => [
  $.cmd_start,       // 0: Entering CMD mode
  $.cmd_end,         // 1: Exiting CMD mode
  $.expr_start,      // 2: Entering EXPR mode
  $.expr_end,        // 3: Exiting EXPR mode
  $.error_in_cmd,    // 4: Syntax error in CMD mode
  $.error_in_expr,   // 5: Syntax error in EXPR mode
],
```

**Mode Sections:**
- `expr_section`: Bounded by `expr_start` and `optional(expr_end)`
- `cmd_section`: Bounded by `cmd_start` and `optional(cmd_end)`

**Key Constructs:**
- `expr_cmd_execution`: `$rsh()` - Execute commands from EXPR mode
- `cmd_expr_interpolation`: `${}` - Interpolate expressions in CMD mode
- `cmd_substitution`: `$()` - Bash-style subshell (no mode switch)

## Scanner Behavior

### Line Start Detection

**Process:**
1. Check if at column 0 or first emission
2. Skip whitespace
3. **Skip comments** (lines starting with `#`) - return false
4. **Skip empty lines** - return false
5. Analyze line content via `is_expr_line_start()`
6. Compare with `last_emitted_mode`
7. Only emit if mode changed or first time

**EXPR Mode Indicators:**
- Keywords: `if`, `for`, `while`, `return`
- Assignment pattern: `IDENTIFIER =` (or `+=`, `-=`, etc.)

**CMD Mode (default):**
- Everything else

### Explicit Mode Switches

**`$rsh(` Detection:**
- Emits: `CMD_START`
- Action: `push_mode(MODE_CMD)`
- Updates: `last_emitted_mode = MODE_CMD`

**`${` Detection:**
- Emits: `EXPR_START`
- Action: `push_mode(MODE_EXPR)`
- Updates: `last_emitted_mode = MODE_EXPR`

**`)` and `}` Detection:**
- Emits: `CMD_END` or `EXPR_END`
- Action: `pop_mode()`
- Updates: `last_emitted_mode = current_mode()` (parent mode)

## Current Test Results

### Single Line Tests
✅ **WORKING**: `result = $rsh(ls -la)`
```
(program
  (expr_section
    (expr_start)
    (assignment
      name: (identifier "result")
      value: (expression
        (expr_cmd_execution
          (command
            name: (command_name (identifier "ls"))
            argument: (command_argument (command_flag "-la"))))))))
```

✅ **WORKING**: Comments as top-level items
```
(program
  (comment "# Test 1: $rsh() in EXPR mode"))
```

### Multi-Line Tests
❌ **FAILING**: Files with multiple non-comment lines

Example input:
```rshell
# Test 1: $rsh() in EXPR mode
result = $rsh(ls -la)

# Test 2: ${} in CMD mode  
echo "User: ${user}"
```

Current error: Line 1 not being parsed (no mode token emitted)

## Known Issues

1. **Multi-line mode detection**: After processing first line/comment, subsequent lines not getting mode tokens
2. **Scanner state after returning false**: When scanner returns false for comments, state may not be correct for next line
3. **Column tracking**: Using `lexer->get_column()` which may not work as expected

## Design Philosophy

**Scanner Responsibilities (MINIMAL):**
- Emit mode boundary tokens ONLY when mode changes
- Track mode stack for nested constructs
- Handle explicit mode switches (`$rsh(`, `${`)

**Grammar Responsibilities (MAXIMAL):**
- All actual parsing of syntax
- Handle comments (top-level and inline)
- Manage precedence and conflicts
- Parse `$rsh()`, `${}`, `$()` structures

**Key Principle**: Scanner emits boundaries, grammar does parsing

## Next Steps

1. Debug why line 1 in multi-line files doesn't get mode token
2. Fix scanner's column tracking or line-start detection
3. Test mode transitions across multiple lines
4. Update test expectations to match actual node names
5. Run full test suite: `python3 tests/test_mode_specific_syntax.py`

## Files Modified

- `rshell-grammar/src/scanner.c` - Complete rewrite with state tracking
- `rshell-grammar/grammar.js` - Updated tokens, renamed nodes, added mode sections
- Tests not yet updated to match new implementation

## Commands for Testing

```bash
# Generate grammar
cd rshell-grammar && tree-sitter generate

# Test single file
tree-sitter parse test_simple.rsh

# Run test suite (when ready)
python3 tests/test_mode_specific_syntax.py
```

## References

- `$()` is bash-style subshell, context-free, no mode switching
- `$rsh()` is EXPR→CMD mode switch
- `${}` is CMD→EXPR mode switch