# Bracket Tracking Investigation

**Date**: 2025-11-17
**Status**: ✅ SOLVED - 100% test coverage achieved with grammar-based solution
**Issue**: RESOLVED - Multiline lists and maps now work

## Problem Statement

Two test cases fail (96.8% → need 100%):

```rshell
# Failing Test 1: Multiline list
SERVERS = [
  1,
  2,
  3
]

# Failing Test 2: Multiline map
CONFIG = {
  "host": "localhost",
  "port": 8080
}
```

**Error**: `MISSING identifier` at line starts inside structures

## Root Cause

The external scanner emits `line_start` tokens at the beginning of every line, including inside data structures where continuation is expected, not a new statement.

```
SERVERS = [
  1,      # ← Scanner emits line_start here
  2,      # ← Parser expects a value, gets line_start token
  3
]
```

## Attempted Solution: Bracket Depth Tracking

### Approach

Track nesting depth of `[]`, `()`, and `{}` in scanner state:

```c
typedef struct {
  bool at_line_start;
  bool last_mode_was_expr;
  bool has_emitted_mode;
  int bracket_depth;    // Count of unclosed [
  int paren_depth;      // Count of unclosed (
  int brace_depth;      // Count of unclosed { (for maps, not blocks)
} Scanner;
```

### Challenge

**The fundamental problem**: Tree-sitter's external scanner is called at specific points by the parser, not continuously during lexing. We can't reliably track brackets because:

1. **No arbitrary lookahead**: Scanner can't scan ahead to count brackets before the parser consumes them
2. **Parser-driven**: Scanner is invoked when parser needs external tokens, not continuously
3. **Stateless tokenization**: By the time we're at a newline, the brackets have already been parsed

### Why It's Hard

```
SERVERS = [     # Parser: "I see assignment, value is next"
  1,            # Parser hasn't called scanner yet
                # Now scanner is called for newline
                # But we don't know we're inside []
```

The scanner would need to either:
- **Look backward** (not supported - scanner only sees forward stream)
- **Get context from parser** (not how external scanners work)
- **Track in real-time** (scanner not called continuously)

## Alternative Approaches Considered

### 1. Grammar-Only Solution

Make `line_start` optional inside structures:

```javascript
list: $ => seq(
  '[',
  optional(seq(
    optional($.line_start),  // Allow but don't require
    $._value,
    repeat(seq(',', optional($.line_start), $._value))
  )),
  ']'
)
```

**Problem**: Creates ambiguity - parser can't tell if identifier starts a statement or is a value.

### 2. Different Line Start Tokens

Emit different tokens inside vs outside structures:

```javascript
externals: $ => [
  $.line_start,
  $.continuation_line  // For inside structures
]
```

**Problem**: Same issue - scanner doesn't know it's inside a structure.

### 3. Parser Stack Inspection

Use Tree-sitter's internal parser stack to determine context:

**Problem**: External scanners don't have access to parser stack - this is by design for performance.

### 4. Context Tokens from Parser

Have parser emit "entering structure" / "leaving structure" tokens:

**Problem**: Chicken-and-egg - parser needs scanner to parse structures, but scanner needs parser's context.

## Working Solutions for Similar Problems

### Python (Indentation)

Python's scanner tracks indentation but doesn't need to know about brackets because Python doesn't use `{}` for blocks:

```python
def foo():
    x = [
        1,  # Indentation ignored inside []
        2
    ]
```

Python's approach: Count indentation **except when inside unclosed brackets**. But Python grammar explicitly handles this at grammar level, not scanner level.

### Bash (Heredocs)

Bash tracks heredoc state because heredocs have explicit delimiters:

```bash
cat << EOF
  content
EOF
```

Scanner sees `<< EOF`, stores delimiter, then ignores everything until `EOF`. This works because:
- Explicit start marker (`<< EOF`)
- Scanner can store state when seeing marker
- Explicit end marker (matching delimiter)

### RShell Difference

Our problem is different:
- No explicit "entering multiline mode" marker
- The `[` is parsed by grammar, not scanner
- Scanner called **after** `[` already consumed

## Recommended Path Forward

### Short Term: Accept 96.8%

**Rationale**:
- 60/62 tests passing is excellent
- Multiline structures are edge cases
- Single-line works perfectly: `ITEMS = [1, 2, 3]`
- Focus on other Phase 3 priorities first

**User Impact**: Minimal
- Most real-world lists/maps fit on one line
- Workaround exists (use single line)
- Documentation can explain limitation

### Long Term: Phase 3 Solution

**Possible approaches** (in order of complexity):

1. **Experiment with Grammar** (Easiest)
   - Try making line_start fully optional in list/map contexts
   - Use precedence to resolve ambiguities
   - May require refactoring statement rules

2. **Add Continuation Character** (Medium)
   - Explicit marker for continuation: `\` at end of line
   - Scanner knows to skip line_start on next line
   - User-visible syntax change

3. **Full Bracket Tracking** (Hardest)
   - Deep dive into Tree-sitter parser internals
   - Potentially contribute to Tree-sitter to add parser stack access
   - Or implement alternative tracking mechanism

## Learnings

1. **External scanners are powerful but limited**
   - Best for: line boundaries, indentation, heredocs
   - Not ideal for: context that requires parser knowledge

2. **Some problems better solved in grammar**
   - Precedence and associativity
   - Structure disambiguation
   - Most parsing challenges

3. **Design trade-offs**
   - Simplicity vs completeness
   - We chose simplicity (clean scanner) over 100% coverage
   - The 2 failing tests are acceptable edge cases

## Solution That Worked: Grammar-Based Approach

After investigating scanner-based solutions, we found a **pure grammar solution** that achieved 100% test coverage!

### The Key Insight

Instead of trying to prevent the scanner from emitting line tokens inside structures, we modified the grammar to **accept and consume** these tokens as part of the structure.

### Implementation

```javascript
// List item that can have line starts inside
_list_item: $ => seq(
  repeat(choice($._newline, $.line_start, $.expr_line_start, $.cmd_line_start)),
  $._value,
  repeat(choice($._newline, $.line_start, $.expr_line_start, $.cmd_line_start))
),
```

This allows the parser to consume line start tokens that appear inside lists and maps, preventing them from being misinterpreted as statement boundaries.

### Results

- **Before**: 97.1% pass rate (67/69 tests)
- **After**: 100% pass rate (69/69 tests) ✅

See [`MULTILINE_FIX_EXPLANATION.md`](MULTILINE_FIX_EXPLANATION.md) for full details.

## Conclusion

The grammar-based solution proved superior to scanner modifications:
1. **Simpler**: No complex state tracking needed
2. **Cleaner**: Pure grammar solution, scanner unchanged
3. **Effective**: 100% test coverage achieved
4. **Maintainable**: Easy to understand and modify

This demonstrates that working WITH the system (accepting tokens) rather than against it (trying to prevent tokens) often leads to better solutions.

---

**Decision**: Phase 2 complete with 100% coverage 🎉
**Next Steps**: Phase 3 features (shell() function, {} interpolation, path literals)