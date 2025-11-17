# Line-Based Mode Detection: Implementation Complete ✅

**Status**: ✅ IMPLEMENTED - 100% test pass rate (38/38 tests)
**Last Updated**: 2025-11-17

**The Core Problem**: How do we make a context-free parser (tree-sitter) behave like it's context-sensitive (checking how lines start)?

**The Solution**: External scanner with mode tracking + optimized token emission

---

## ✅ IMPLEMENTATION SUMMARY

We successfully implemented automatic line-based mode detection using:

1. **External Scanner** (`rshell-grammar/src/scanner.c`):
   - Analyzes each line to determine EXPR vs CMD mode
   - Tracks mode changes across lines
   - Emits optimized tokens (only on mode changes)

2. **Grammar Integration** (`rshell-grammar/grammar.js`):
   - Three external tokens: `line_start`, `expr_line_start`, `cmd_line_start`
   - Statements accept both mode-change and same-mode tokens
   - Blocks transparently handle line_start tokens

3. **Test Results**:
   - **38/38 grammar tests passing (100%)**
   - All features working: assignments, control flow, expressions, property access
   - Mode detection accurate for keywords, assignments, commands

See [`PHASE_2_MODE_DETECTION_COMPLETE.md`](PHASE_2_MODE_DETECTION_COMPLETE.md) for complete implementation details.

---

## ORIGINAL CHALLENGE DOCUMENTATION

Below is the original analysis of the technical challenge. **This has now been solved!**

---

## The Design Goal

```bash
# Line 1: Starts with IDENTIFIER = → Expression Mode
X = 42

# Line 2: Starts with 'for' → Expression Mode
for S in SERVERS {
  # Line 3: Starts with IDENTIFIER = → Expression Mode
  result = shell(ssh server.com)
  
  # Line 4: Starts with 'if' → Expression Mode
  if (result.success) {
    # Line 5: Does NOT start with keyword/assignment → Command Mode
    echo Success!
  }
}

# Line 6: Does NOT start with keyword/assignment → Command Mode
ls -la
```

**The Challenge**: The parser needs to "remember" what mode it's in based on what appeared at the **start of the line**.

---

## Why This Is Hard in Tree-Sitter

### 1. Tree-Sitter is Context-Free

Tree-sitter grammars are **context-free**, meaning:
- The parser doesn't have "memory" of what came before
- It can't track "state" like "we're currently in expression mode"
- It can't easily check "did this line start with X?"

### 2. Whitespace is Usually Ignored

By default, tree-sitter treats whitespace (including newlines) as insignificant:
```javascript
extras: $ => [
  /\s/,  // Ignores ALL whitespace including newlines
]
```

This means the parser sees:
```
X = 42 echo hello
```
as the same as:
```
X = 42
echo hello
```

**But we NEED to distinguish these!**

---

## The Technical Solutions

### Solution 1: Make Newlines Significant (Partially)

We need newlines to be significant for **statement boundaries** but not inside expressions:

```javascript
// In grammar.js
program: $ => seq(
  repeat(seq(
    $._statement,
    $._statement_end  // Explicit newline or semicolon
  ))
),

_statement_end: $ => choice(
  '\n',
  ';',
  // Allow optional newline before }
  seq(optional('\n'), '}')
),

// But allow newlines INSIDE expressions
list: $ => seq(
  '[',
  optional(seq(
    $._value,
    repeat(seq(
      ',',
      optional('\n'),  // Newline allowed here
      $._value
    ))
  )),
  ']'
)
```

### Solution 2: Use Precedence to Disambiguate

When the parser sees `IDENTIFIER`, it could be:
1. Start of assignment: `X = 42`
2. Command name: `ls -la`

We use precedence to prefer assignment when `=` follows:

```javascript
// Grammar rule
_statement: $ => choice(
  prec(2, $.assignment),  // Higher precedence
  prec(1, $.command),     // Lower precedence
),

assignment: $ => seq(
  field('name', $.identifier),
  '=',
  field('value', $._expression)
),

command: $ => seq(
  field('name', $.identifier),
  repeat(field('argument', $._command_argument))
),
```

**How it works:**
```
X = 42
^
Parser sees 'X', creates IDENTIFIER
  -> Looks ahead, sees '='
  -> Chooses $.assignment (precedence 2) over $.command
  
ls -la
^
Parser sees 'ls', creates IDENTIFIER
  -> Looks ahead, sees '-la' (not '=')
  -> Chooses $.command (only option that matches)
```

### Solution 3: Separate Expression and Command Contexts

This is the HARD part. We need to track "are we in an expression context or command context?"

**Expression Context**: Inside `if`, `for`, `while`, or after `=`
**Command Context**: Direct line execution, inside `shell()`, inside `{}`

```javascript
// Top-level statements
_statement: $ => choice(
  $.assignment,        // Always expression context
  $.control_flow,      // Creates expression context
  $.command,           // Command context
),

// Inside control flow blocks
control_flow_block: $ => seq(
  '{',
  repeat(choice(
    $.assignment,      // Expression context continues
    $.command,         // But NOW command is different!
    // ... more options
  )),
  '}'
),
```

### Solution 4: Different Rules for Different Contexts

The trick is to have **different command rules** depending on context:

```javascript
// Top-level command (no interpolation)
command: $ => seq(
  $.identifier,
  repeat($._simple_argument)
),

_simple_argument: $ => choice(
  $.string,
  $.identifier,
  $.variable_reference,  // $VAR
  // NO {} interpolation yet
),

// Command in expression mode (with interpolation)
command_in_expression: $ => seq(
  $.identifier,
  repeat($._expression_command_argument)
),

_expression_command_argument: $ => choice(
  $.string,
  $.identifier,
  $.variable_reference,
  $.interpolation,  // {expr}
),

interpolation: $ => seq(
  '{',
  $._expression,
  '}'
),
```

---

## The Disambiguation Problem

Consider this code:
```bash
for S in SERVERS {
  echo {S.fqdn}
}
```

The parser sees `{` twice:
1. Line 1: `{` starts a **block** (control flow)
2. Line 2: `{` starts **interpolation** (expression in command)

**How does it know which is which?**

### Solution: Context-Aware Rules

```javascript
// At statement level, { starts a block
control_flow: $ => seq(
  'for',
  $.identifier,
  'in',
  $._expression,
  $.block  // This is a BLOCK
),

block: $ => seq(
  '{',
  repeat($._statement),
  '}'
),

// Inside a command, { is interpolation
command_in_block: $ => seq(
  $.identifier,
  repeat(choice(
    $.string,
    $.interpolation  // This is INTERPOLATION
  ))
),

interpolation: $ => seq(
  '{',
  $._expression,  // NOT a statement
  '}'
),
```

**The key difference:**
- `block` contains `repeat($._statement)` - statements
- `interpolation` contains `$._expression` - a single expression

---

## The Full Challenge Example

Let's trace through parsing this:
```bash
SERVERS = [{'fqdn':'a.b.c'}]
for S in SERVERS {
  result = shell(echo {S.fqdn})
  if (result.success) {
    echo Success!
  }
}
```

### Parse Steps:

1. **Line 1**: `SERVERS = ...`
   - Sees `SERVERS` (identifier)
   - Looks ahead, sees `=`
   - Chooses `assignment` rule (expression mode)
   - Parses `[{'fqdn':'a.b.c'}]` as list expression

2. **Line 2**: `for S in SERVERS {`
   - Sees `for` keyword
   - Enters `control_flow` rule (expression mode)
   - Creates `block` expecting statements

3. **Line 3**: `result = shell(...)`
   - Inside block, sees `result` (identifier)
   - Looks ahead, sees `=`
   - Chooses `assignment` rule
   - Parses `shell(echo {S.fqdn})` as expression
   - Inside `shell()`, `echo {S.fqdn}` is treated as command text

4. **Line 4**: `if (result.success) {`
   - Nested control flow
   - Creates another block

5. **Line 5**: `echo Success!`
   - Inside if-block, sees `echo`
   - Looks ahead, no `=`
   - Chooses `command` rule
   - `Success!` is command argument

### The Conflicts:

1. **`IDENTIFIER` ambiguity**:
   - Could be: command name OR assignment target OR variable reference
   - Solution: Precedence + lookahead for `=`

2. **`{` ambiguity**:
   - Could be: block OR interpolation OR map literal
   - Solution: Different rules in different contexts

3. **String in command vs expression**:
   - Command: `echo "hello"` - string is argument
   - Expression: `X = "hello"` - string is value
   - Solution: Same rule, different contexts

---

## Tree-Sitter Limitations

### 1. No True Stateful Parsing

We can't say "remember we're in expression mode" across statements. Instead:
- Use **structural rules** (inside block = expression context)
- Use **precedence** (prefer assignment over command)
- Use **different rule names** for same syntax in different contexts

### 2. Lookahead is Limited

Tree-sitter can look ahead for disambiguation, but:
- Lookahead is **token-based**, not line-based
- Can't easily check "is this the first token on a new line?"
- Must rely on **explicit statement terminators** (newlines, semicolons)

### 3. Ambiguity Resolution

When multiple rules match, tree-sitter uses:
1. **Precedence** (`prec()`) - higher wins
2. **Dynamic precedence** (`prec.dynamic()`) - for runtime conflicts
3. **Length** - longer match wins
4. **Order** - first rule in `choice()` wins if tied

---

## Implementation Strategy

### Phase 1: Strict Mode (Easier)
Start with **unambiguous syntax**:
```bash
# MUST have spaces around =
X = 42        # ✓ Assignment
X=42          # ✗ Parse error

# MUST have newlines between statements
X = 42; Y = 10   # ✗ Parse error
X = 42
Y = 10           # ✓

# No shorthand
echo{X}       # ✗ Parse error
echo {X}      # ✓ Interpolation
```

### Phase 2: Add Ambiguity Resolution
Once basics work, add:
- Optional whitespace around `=`
- Semicolon statement separators
- Implicit line continuations

### Phase 3: Polish
- Better error messages
- Edge case handling
- Performance optimization

---

## Why This Will Be Hard

1. **Many edge cases**: `X=Y` (assignment? command with weird name?)
2. **Nested contexts**: Command inside expression inside command inside control flow
3. **Conflict resolution**: Need to test MANY precedence combinations
4. **Debugging**: Tree-sitter errors are cryptic
5. **Iteration required**: Will need many test-fix cycles

## Tools for Success

1. **Test harness**: `python test_grammar_simple.py --verbose`
2. **Incremental development**: One feature at a time
3. **Conflict detection**: `tree-sitter generate` shows conflicts
4. **Parse tree inspection**: `tree-sitter parse file.rsh`

---

**Bottom line**: We successfully encoded context-sensitive behavior (line-based modes) in a context-free grammar using an external scanner with state tracking and optimized token emission!

---

## ✅ Final Implementation

**What Works**:
```bash
# Automatic EXPR mode detection
X = 42
for S in SERVERS {
  Y = 1      # Still EXPR mode (line_start token)
}

# Automatic CMD mode detection
echo hello
ls -la

# Mode transitions handled automatically
if (X > 10) {    # EXPR mode
  echo "big"     # CMD mode detected inside block
}
```

**Performance**:
- Minimized token overhead (only emit mode tokens on changes)
- Fast parsing (all 38 tests < 100ms)
- Clean parse trees (no ERROR nodes)

**Files Modified**:
- `rshell-grammar/src/scanner.c` - Mode detection logic
- `rshell-grammar/grammar.js` - Token integration
- Full test suite passing (100%)

See [`PHASE_2_MODE_DETECTION_COMPLETE.md`](PHASE_2_MODE_DETECTION_COMPLETE.md) for technical details!