# Scanner Infinite Loop - Root Cause Analysis

## The Fundamental Problem

Our scanner causes infinite loops because it emits tokens **without consuming any input**.

### What Happens

1. Tree-sitter calls `scan()` at position 0 in "X = 2"
2. Scanner detects this is an assignment (EXPR mode)
3. Scanner emits `EXPR_START` without advancing the lexer
4. Tree-sitter calls `scan()` again **at the same position 0**
5. Scanner detects assignment again, emits `EXPR_START` again
6. Infinite loop!

### Why Python Scanner Works

Python's INDENT/DEDENT scanner works because:

1. **It consumes input**: Python scanner consumes all whitespace/newlines (lines 217-265) BEFORE emitting tokens
2. **Tokens are position-bound**: INDENT/DEDENT are emitted AFTER newlines, so they naturally occur at different positions
3. **Clear termination**: Once whitespace is consumed, the scanner moves forward

### Our Problem

Our mode tokens (`EXPR_START`, `CMD_START`) are **line-prefix tokens** - they mark the START of content, not something that comes AFTER whitespace. This creates a chicken-egg problem:

- We need to emit `EXPR_START` BEFORE the grammar parses `X = 2`
- But we can't consume `X = 2` because that's what the grammar needs to parse
- So we emit without consuming... causing infinite loops

## Possible Solutions

### Solution 1: Zero-Width Tokens (Current Attempt - BROKEN)

Emit tokens without consuming input. **This doesn't work** because Tree-sitter re-calls the scanner at the same position.

### Solution 2: Grammar-Driven Mode Detection

Instead of scanner emitting mode tokens proactively, let the **grammar** detect modes by looking at first token:

```javascript
// Grammar checks first token
program: $ => repeat(choice(
  $.expr_line,  // Starts with keywords/assignments
  $.cmd_line,   // Everything else
))

expr_line: $ => seq(
  choice(
    $.assignment,  // X =
    $.if_statement, // if
    // ...
  )
)
```

**Problem**: Ambiguity - grammar can't tell if "X" starts `X = 2` (EXPR) or `X --flag` (CMD command)

### Solution 3: Scanner Consumes First Token

Scanner peeks ahead, determines mode, and **consumes the first identifier/keyword**:

```cpp
if (line starts with assignment) {
  consume_until(space);  // Consume "X"
  emit(EXPR_START);
}
```

**Problem**: Grammar expects to see "X" but scanner already consumed it

### Solution 4: Newline-Based Token Emission (PYTHON PATTERN)

Emit mode tokens AFTER newlines, not BEFORE content:

```
Line 1: X = 2\n
        ^     ^
        |     emit EXPR_START here (after \n)
        grammar parses this
```

**Problem**: First line has no preceding newline

### Solution 5: Explicit Mode Delimiters in Syntax

Add explicit mode markers to the syntax:

```rshell
@expr X = 2
@cmd echo "hello"
```

**Problem**: Changes the language design

## Recommended Solution

Based on Python scanner analysis, the cleanest solution is **Solution 4 with BOF handling**:

1. Emit mode tokens AFTER newlines (like Python's INDENT)
2. For first line, emit token at BOF (beginning of file)
3. Scanner must track: "have we emitted initial mode token?"

### Implementation

```cpp
// State
bool initial_token_emitted = false;

// In scan()
if (!initial_token_emitted) {
  // BOF - analyze first line
  if (is_assignment(peek_line())) {
    initial_token_emitted = true;
    emit(EXPR_START);
    return true;
  }
}

if (lexer->lookahead == '\n') {
  // Consume newline
  lexer->advance(lexer, false);
  lexer->mark_end(lexer);
  
  // Peek next line
  if (next line is assignment) {
    emit(EXPR_START);
    return true;
  }
}
```

This way, scanner **consumes the newline** before emitting the mode token, breaking the infinite loop.

## Next Steps

1. Add `initial_token_emitted` to scanner state
2. Emit mode tokens AFTER newlines (consuming the newline)
3. Handle BOF special case
4. Test with `X = 2`