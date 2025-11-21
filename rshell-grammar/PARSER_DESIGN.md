# RShell Parser Design - Mode-Aware Grammar Architecture

**Date**: 2025-11-20
**Status**: V3 Production Implementation
**Pattern**: Minimal external scanner + grammar-based mode detection (hybrid single grammar)

---

## Table of Contents

1. [Overview](#overview)
2. [Part I: Scanner Mechanism](#part-i-scanner-mechanism)
3. [Part II: Dual Grammar Concept](#part-ii-dual-grammar-concept)
4. [Part III: Complete Examples](#part-iii-complete-examples)
5. [Part IV: Implementation Guide](#part-iv-implementation-guide)

---

## Overview

RShell uses a **mode-aware single grammar** where an external scanner provides minimal structural tokens (line boundaries and block starts), while the grammar itself handles mode detection and parsing decisions. This is NOT a pure dual grammar - nodes are extensively reused between modes.

**Key Design**: The scanner is deliberately minimal (105 lines, only 2 external tokens), following the tree-sitter-python pattern. The grammar uses lookahead to determine whether a line is EXPR or CMD mode.

---

# Part I: Scanner Mechanism

The scanner is the intelligent component that emits mode boundary tokens to Tree-sitter, telling it when to switch between EXPR and CMD grammars.

## 1. Scanner Tokens

The scanner emits **4 external tokens**:

| Token | Meaning | Example |
|-------|---------|---------|
| `EXPR_START` | Enter Expression mode | `X = 42` |
| `EXPR_END` | Exit Expression mode | End of `${}` |
| `CMD_START` | Enter Command mode | `echo hello` |
| `CMD_END` | Exit Command mode | End of `$rsh()` |

## 2. Mode Detection Logic

### 2.1 Line-Based Detection

**When**: At the start of each line (when not inside blocks/calls/interpolations)

**EXPR mode triggers** (emit `EXPR_START`):

1. **Assignments**:
   ```rshell
   X = 42
   COUNT += 1
   ITEMS -= 5
   TOTAL *= 2
   AVERAGE /= COUNT
   REMAINDER %= 10
   ```

2. **Control flow keywords**:
   ```rshell
   if (X > 10) {
   for S in SERVERS {
   while (not ready) {
   return result
   break
   continue
   else {
   elif (Y < 5) {
   ```

3. **Function calls**:
   ```rshell
   print("hello")
   log.write("message")
   items[0].process(data)
   server.api.call(endpoint)
   ```

**CMD mode** (emit `CMD_START`): Everything else
```rshell
echo hello
ls -la
ssh server.com
cat file.txt | grep pattern
```

### 2.2 Inline Mode Transitions

**From EXPR to CMD**: `$rsh(command)`
```rshell
result = $rsh(ls -la)
         ^         ^
    CMD_START  CMD_END
```

**From CMD to EXPR**: `${expression}`
```rshell
echo Server: ${S.fqdn}
             ^       ^
        EXPR_START EXPR_END
```

## 3. Delimiter Tracking (Critical!)

The scanner MUST track three types of delimiter nesting:

### 3.1 EXPR Block Depth: `{ }` in Control Flow

**Purpose**: Keep EXPR mode active across multi-line control flow blocks

**Example**:
```rshell
for S in SERVERS {        # { depth = 1 → stay in EXPR
  result = $rsh(ssh ...)  # depth = 1 → EXPR continues
  
  if (not result.ok) {    # { depth = 2 → still EXPR
    FAILED += S           # depth = 2 → still EXPR
  }                       # } depth = 1
}                         # } depth = 0 → can switch modes
```

**Rules**:
- In EXPR mode, `{` → increment `expr_block_depth`
- In EXPR mode, `}` → decrement `expr_block_depth`
- **Only perform line-based detection when `expr_block_depth == 0`**

**Why it matters**:
```rshell
for S in SERVERS {
  echo Checking $S      # This is CMD mode (line doesn't start with keyword)
}                       # But we're still inside EXPR block depth
```

### 3.2 Command Call Depth: `( )` in `$rsh()`

**Purpose**: Know when command execution ends, detect unclosed calls

**Example**:
```rshell
result = $rsh(ssh server.com -p 8080)
         ^                          ^
    ( depth=1                   ) depth=0
    emit CMD_START              emit CMD_END
```

**Rules**:
- `$rsh(` → set `in_rsh_call = true`, `cmd_paren_depth = 1`
- Track `(` and `)` while in call
- `)` when depth reaches 0 → emit `CMD_END`, set `in_rsh_call = false`
- **ERROR**: Newline while `in_rsh_call == true` → unclosed call error

**Scanner Error Example**:
```rshell
result = $rsh(ssh server.com
              ^^^^^^^^^^^^^ ERROR: Unclosed $rsh() at end of line
```

### 3.3 Interpolation Depth: `{ }` in `${}`

**Purpose**: Know when expression interpolation ends, detect unclosed braces

**Example**:
```rshell
echo Status: ${result.exit_code}
             ^                 ^
        { depth=1          } depth=0
        emit EXPR_START    emit EXPR_END
```

**Rules**:
- `${` → set `in_expr_interp = true`, `expr_interp_depth = 1`
- Track `{` and `}` while in interpolation
- `}` when depth reaches 0 → emit `EXPR_END`, set `in_expr_interp = false`
- **ERROR**: Newline while `in_expr_interp == true` → unclosed interpolation error

**Scanner Error Example**:
```rshell
echo Status: ${result.exit_code
             ^^^^^^^^^^^^^^^^^^^^ ERROR: Unclosed ${} at end of line
```

## 4. Scanner State Structure

```cpp
struct ScannerState {
  // Current mode
  Mode current_mode;           // EXPR or CMD
  
  // Delimiter tracking
  int expr_block_depth;        // Track { } in EXPR control flow
  int cmd_paren_depth;         // Track ( ) in $rsh()
  int expr_interp_depth;       // Track { } in ${}
  
  // Flags
  bool at_line_start;          // For line-based detection
  bool in_rsh_call;            // Inside $rsh(...)
  bool in_expr_interp;         // Inside ${...}
};
```

## 5. Scanner Decision Flow

```
At each character position:

1. Are we at line start AND all depths == 0?
   YES → Perform line-based mode detection
         - Check for assignment/keyword/function call
         - Emit EXPR_START or CMD_START
   NO  → Continue to step 2

2. Are we looking at an inline transition?
   - $rsh( → Start tracking CMD call (depth++)
   - ${   → Start tracking EXPR interp (depth++)
   - )    → In $rsh()? depth--, emit CMD_END if depth==0
   - }    → In ${}? depth--, emit EXPR_END if depth==0

3. Are we in EXPR mode tracking blocks?
   - { → expr_block_depth++
   - } → expr_block_depth--

4. Is this a newline?
   - If in_rsh_call → ERROR: Unclosed $rsh()
   - If in_expr_interp → ERROR: Unclosed ${}
   - Set at_line_start = true
```

---

# Part II: Mode-Aware Single Grammar Concept

## 1. The Approach: Hybrid Grammar with Node Reuse

**This is NOT a pure dual grammar**. Instead, it's a pragmatic hybrid:

**Mode-Specific Nodes** (only 6):
- `expr_line` - Expression mode entry point
- `expr_block` - Control flow blocks (`{ }`)
- `cmd_line` - Command mode entry point
- `cmd_execution` - `$rsh()` syntax
- `expr_interpolation` - `${}` syntax
- `cmd_substitution` - `$()` syntax

**Shared Nodes** (~40 nodes):
- All expressions: `expression`, `binary_expression`, `unary_expression`, `parenthesized`
- All data types: `literal`, `number`, `string`, `boolean`, `array`, `object`
- All identifiers: `identifier`, `variable_reference`, `property_access`
- Control flow: `if_statement`, `for_statement`, `while_statement`
- Commands: `command`, `pipeline`, `command_name`, `command_argument`
- Everything else: `assignment`, `function_call`, etc.

**Why This Design?**
- Runtime doesn't need separate handling for same semantic constructs
- An `identifier` is an `identifier` regardless of mode
- Reduces code duplication and complexity
- Trade-off: Some ambiguity (bare `ls` could be variable or command)

## 3. Grammar Structure

```javascript
module.exports = grammar({
  name: 'rshell',
  
  // Scanner-emitted tokens
  externals: $ => [
    $.cmd_start,
    $.cmd_end,
    $.expr_start,
    $.expr_end,
  ],
  
  rules: {
    // Top level: sections driven by scanner tokens
    program: $ => repeat(choice(
      $.expr_section,
      $.cmd_section,
      $.comment,
    )),
    
    // ===== EXPR GRAMMAR =====
    
    expr_section: $ => seq(
      $.expr_start,              // Scanner says "enter EXPR mode"
      repeat($.expr_statement),
      optional($.expr_end)
    ),
    
    expr_statement: $ => choice(
      $.expr_assignment,         // X = 42
      $.expr_control_flow,       // if/for/while
      $.expr_function_call,      // print()
      $.expr_command_exec,       // $rsh(cmd)
    ),
    
    expr_assignment: $ => seq(
      $.identifier,
      choice('=', '+=', '-=', '*=', '/=', '%='),
      $.expr_expression
    ),
    
    expr_block: $ => seq(
      '{',                       // Grammar handles braces
      repeat(choice(
        $.expr_section,          // Can have EXPR inside
        $.cmd_section,           // Can have CMD inside
      )),
      '}'
    ),
    
    expr_command_exec: $ => seq(
      '$rsh',
      '(',
      $.cmd_section,             // Nested CMD grammar!
      ')'
    ),
    
    // ===== CMD GRAMMAR =====
    
    cmd_section: $ => seq(
      $.cmd_start,               // Scanner says "enter CMD mode"
      repeat($.cmd_statement),
      optional($.cmd_end)
    ),
    
    cmd_statement: $ => choice(
      $.cmd_simple_command,      // echo hello
      $.cmd_pipeline,            // cat | grep
    ),
    
    cmd_expr_interpolation: $ => seq(
      '${',
      $.expr_expression,         // Nested EXPR grammar!
      '}'
    ),
    
    // ===== SHARED RULES =====
    
    identifier: $ => /[a-zA-Z_][a-zA-Z0-9_]*/,
    number: $ => /-?\d+(\.\d+)?/,
    string: $ => choice(
      seq('"', repeat(/[^"]/), '"'),
      seq("'", repeat(/[^']/), "'"),
    ),
  }
});
```

## 3. Not Like HTML+JavaScript

Unlike HTML parsers with embedded JavaScript (which have truly separate grammars), RShell uses a **hybrid approach**:

**HTML+JS Pattern** (true dual grammar):
- Completely separate AST node types
- `html_element` ≠ `javascript_statement`
- No node reuse between languages

**RShell Pattern** (mode-aware single grammar):
- Extensive node reuse (`identifier`, `expression`, `literal`, etc.)
- Mode detection via grammar lookahead, not scanner
- Only mode-switching constructs are unique (`$rsh()`, `${}`)
- Same semantic constructs use same nodes regardless of mode

**Result**: Simpler, more maintainable, but with acceptable ambiguities (e.g., bare `ls`).

---

# Part III: Complete Examples

## Example 1: Server Health Check

**RShell code**:
```rshell
SERVERS = [
  {'fqdn':'web1.example.com', 'port':22},
  {'fqdn':'db1.example.com', 'port':22}
]
FAILED = []
SUCCESS = []

SERVERS += {'fqdn':'api1.example.com', 'port':22}

for S in SERVERS {
  result = $rsh(ssh $S.fqdn -p $S.port echo ok)
  
  if (not result.success) {
    FAILED += S
  } else {
    SUCCESS += S
  }
}

for S in SUCCESS {
  echo ${S.fqdn} succeeded! Total: ${SUCCESS.length}
}

if (FAILED.length > 0) {
  for S in FAILED {
    echo FAILED: ${S.fqdn}
  }
}
```

**Scanner behavior**:
```
Line 1: "SERVERS = [" → EXPR_START (assignment)
        { depth = 0
Line 2: "  {'fqdn'..." → depth = 0, inside list literal (grammar handles)
Line 4: "]" → list closes
Line 5: "FAILED = []" → depth = 0, still EXPR (assignment)
Line 6: "SUCCESS = []" → depth = 0, still EXPR (assignment)
Line 8: "SERVERS += {" → depth = 0, EXPR (compound assignment)
Line 10: "for S in SERVERS {" → depth = 0, EXPR (keyword)
         { depth++ = 1
Line 11: "  result = $rsh(...)" → depth = 1, EXPR continues (assignment)
         $rsh( → CMD_START, cmd_paren_depth = 1
         ... → cmd_paren_depth tracks parens
         ) → cmd_paren_depth = 0, CMD_END
Line 13: "  if (not result.success) {" → depth = 1, EXPR (keyword)
         { depth++ = 2
Line 14: "    FAILED += S" → depth = 2, EXPR continues (assignment)
Line 15: "  }" → depth-- = 1
Line 16: "  } else {" → depth = 1, EXPR (keyword)
         { depth++ = 2
Line 17: "    SUCCESS += S" → depth = 2, EXPR continues
Line 18: "  }" → depth-- = 1
Line 19: "}" → depth-- = 0 (can switch modes now)
Line 21: "for S in SUCCESS {" → depth = 0, EXPR_START (keyword)
         { depth++ = 1
Line 22: "  echo ${S.fqdn}..." → depth = 1, CMD mode (line starts with 'echo')
         → CMD_START
         ${ → EXPR_START, expr_interp_depth = 1
         } → expr_interp_depth = 0, EXPR_END
         (similar for second ${})
Line 23: "}" → depth-- = 0
```

**Parse tree structure**:
```
program
  expr_section (lines 1-19)
    expr_start
    expr_assignment (SERVERS = [...])
    expr_assignment (FAILED = [])
    expr_assignment (SUCCESS = [])
    expr_assignment (SERVERS += {...})
    expr_for_statement
      expr_block
        {
        expr_assignment (result = $rsh(...))
          expr_command_exec
            $rsh(
              cmd_section
                cmd_simple_command
                  ssh $S.fqdn -p $S.port echo ok
            )
        expr_if_statement
          expr_block
            {
            expr_assignment (FAILED += S)
            }
          else
            expr_block
              {
              expr_assignment (SUCCESS += S)
              }
        }
  
  expr_section (lines 21-23)
    expr_start
    expr_for_statement
      expr_block
        {
        cmd_section
          cmd_start
          cmd_simple_command
            echo
            cmd_expr_interpolation (${S.fqdn})
            ...
        }
  
  expr_section (lines 25-29)
    expr_start
    expr_if_statement
      expr_block
        {
        expr_for_statement
          expr_block
            {
            cmd_section
              echo FAILED: ${S.fqdn}
            }
        }
```

## Example 2: Nested Mode Switches

**RShell code**:
```rshell
result = $rsh(echo Status: ${SERVER.port})
```

**Scanner behavior**:
```
"result = $rsh(" → EXPR_START (assignment)
                   $rsh( → CMD_START, cmd_paren_depth = 1
"echo Status: ${" → ${  → EXPR_START, expr_interp_depth = 1
"SERVER.port" → (EXPR continues)
"}" → expr_interp_depth = 0, EXPR_END
")" → cmd_paren_depth = 0, CMD_END
```

**Parse tree**:
```
program
  expr_section
    expr_start
    expr_assignment
      identifier: "result"
      =
      expr_command_exec
        $rsh
        (
        cmd_section                    ← Nested CMD
          cmd_start
          cmd_simple_command
            cmd_name: "echo"
            cmd_argument: "Status:"
            cmd_expr_interpolation
              ${
              expr_expression          ← Nested EXPR inside CMD
                property_access
                  identifier: "SERVER"
                  .
                  identifier: "port"
              }
        )
```

## Example 3: Multi-line EXPR Block with CMD Lines

**RShell code**:
```rshell
for S in SERVERS {
  echo Checking ${S.fqdn}
  result = $rsh(ping -c 1 ${S.fqdn})
  echo Result: ${result.exit_code}
}
```

**Scanner behavior**:
```
"for S in SERVERS {" → EXPR_START (keyword)
                       { → expr_block_depth = 1
"  echo Checking ${...}" → depth = 1, line starts with 'echo' → CMD_START
                           ${ → EXPR_START (interp)
                           } → EXPR_END
"  result = $rsh(...)" → depth = 1, assignment → still EXPR (no new EXPR_START)
                         $rsh( → CMD_START
                         ${ → EXPR_START (interp)
                         } → EXPR_END  
                         ) → CMD_END
"  echo Result: ${...}" → depth = 1, 'echo' → CMD_START
                          ${ → EXPR_START
                          } → EXPR_END
"}" → expr_block_depth = 0
```

---

# Part IV: Implementation Guide

## 1. Scanner State Management

### State Structure

```cpp
// scanner.h
struct ScannerState {
  // Mode tracking
  Mode current_mode;           // EXPR or CMD
  
  // Delimiter depth tracking
  int expr_block_depth;        // { } in EXPR blocks (for, if, while)
  int cmd_paren_depth;         // ( ) in $rsh(...)
  int expr_interp_depth;       // { } in ${...}
  
  // Context flags
  bool at_line_start;          // For line-based detection
  bool in_rsh_call;            // Currently inside $rsh(...)
  bool in_expr_interp;         // Currently inside ${...}
  
  // Serialization support
  std::vector<char> serialize() const;
  static ScannerState deserialize(const char* buf, unsigned len);
};
```

### Serialization

**Clean struct-based approach with memcpy**:

```cpp
// Packed binary format for serialization (no padding)
struct __attribute__((packed)) SerializedState {
  uint8_t version;
  uint8_t current_mode;
  uint8_t at_line_start;
  uint8_t in_rsh_call;
  uint8_t in_expr_interp;
  int32_t expr_block_depth;
  int32_t cmd_paren_depth;
  int32_t expr_interp_depth;
};

std::vector<char> ScannerState::serialize() const {
  SerializedState packed{};
  packed.version = 1;
  packed.current_mode = static_cast<uint8_t>(current_mode);
  packed.at_line_start = at_line_start ? 1 : 0;
  packed.in_rsh_call = in_rsh_call ? 1 : 0;
  packed.in_expr_interp = in_expr_interp ? 1 : 0;
  packed.expr_block_depth = static_cast<int32_t>(expr_block_depth);
  packed.cmd_paren_depth = static_cast<int32_t>(cmd_paren_depth);
  packed.expr_interp_depth = static_cast<int32_t>(expr_interp_depth);
  
  std::vector<char> result(sizeof(SerializedState));
  std::memcpy(result.data(), &packed, sizeof(SerializedState));
  return result;
}

ScannerState ScannerState::deserialize(const char* buf, unsigned len) {
  ScannerState s;
  
  // Validate buffer size and version
  if (len < sizeof(SerializedState)) return s;
  
  SerializedState packed{};
  std::memcpy(&packed, buf, sizeof(SerializedState));
  
  if (packed.version != 1) return s;  // version check
  
  s.current_mode = static_cast<Mode>(packed.current_mode);
  s.at_line_start = packed.at_line_start != 0;
  s.in_rsh_call = packed.in_rsh_call != 0;
  s.in_expr_interp = packed.in_expr_interp != 0;
  s.expr_block_depth = packed.expr_block_depth;
  s.cmd_paren_depth = packed.cmd_paren_depth;
  s.expr_interp_depth = packed.expr_interp_depth;
  
  return s;
}
```

## 2. Main Scan Function Logic

```cpp
bool Scanner::scan(void* lexer_ptr, const bool* valid_symbols) {
  TSLexer* lexer = static_cast<TSLexer*>(lexer_ptr);
  
  // === INLINE TRANSITIONS ===
  
  // $rsh( - Start CMD call from EXPR
  if (state_.current_mode == Mode::Expr &&
      lexer->lookahead == '$' && peek_match(lexer_ptr, "$rsh(")) {
    state_.in_rsh_call = true;
    state_.cmd_paren_depth = 1;
    if (valid_symbols[CMD_START]) {
      return emit(lexer_ptr, TokenType::CmdStart);
    }
  }
  
  // ${ - Start EXPR interpolation from CMD
  if (state_.current_mode == Mode::Cmd &&
      lexer->lookahead == '$' && peek_match(lexer_ptr, "${")) {
    state_.in_expr_interp = true;
    state_.expr_interp_depth = 1;
    if (valid_symbols[EXPR_START]) {
      return emit(lexer_ptr, TokenType::ExprStart);
    }
  }
  
  // Track delimiters in $rsh()
  if (state_.in_rsh_call) {
    if (lexer->lookahead == '(') {
      state_.cmd_paren_depth++;
    } else if (lexer->lookahead == ')') {
      state_.cmd_paren_depth--;
      if (state_.cmd_paren_depth == 0) {
        state_.in_rsh_call = false;
        if (valid_symbols[CMD_END]) {
          return emit(lexer_ptr, TokenType::CmdEnd);
        }
      }
    }
  }
  
  // Track delimiters in ${}
  if (state_.in_expr_interp) {
    if (lexer->lookahead == '{') {
      state_.expr_interp_depth++;
    } else if (lexer->lookahead == '}') {
      state_.expr_interp_depth--;
      if (state_.expr_interp_depth == 0) {
        state_.in_expr_interp = false;
        if (valid_symbols[EXPR_END]) {
          return emit(lexer_ptr, TokenType::ExprEnd);
        }
      }
    }
  }
  
  // === DELIMITER TRACKING IN EXPR BLOCKS ===
  
  if (state_.current_mode == Mode::Expr) {
    if (lexer->lookahead == '{') {
      state_.expr_block_depth++;
    } else if (lexer->lookahead == '}') {
      state_.expr_block_depth--;
    }
  }
  
  // === LINE-BASED MODE DETECTION ===
  
  // Only at line start AND when not inside any blocks/calls
  if ((lexer->get_column(lexer) == 0 || state_.at_line_start) &&
      state_.expr_block_depth == 0 &&
      !state_.in_rsh_call &&
      !state_.in_expr_interp) {
    
    state_.at_line_start = false;
    skip_whitespace(lexer_ptr);
    
    // Skip empty lines and comments
    if (lexer->lookahead == '\n' || lexer->lookahead == '#' || lexer->lookahead == 0) {
      return false;
    }
    
    // Consume line start for analysis
    std::string line_buffer = consume_until(lexer_ptr, '\n', 80);
    
    // Determine mode
    bool is_expr = is_assignment(line_buffer) ||
                   is_keyword(line_buffer) ||
                   is_function_call(line_buffer);
    
    Mode new_mode = is_expr ? Mode::Expr : Mode::Cmd;
    
    // Emit token if mode changed
    if (new_mode != state_.current_mode) {
      state_.current_mode = new_mode;
      
      if (new_mode == Mode::Expr && valid_symbols[EXPR_START]) {
        return emit(lexer_ptr, TokenType::ExprStart);
      } else if (new_mode == Mode::Cmd && valid_symbols[CMD_START]) {
        return emit(lexer_ptr, TokenType::CmdStart);
      }
    }
  }
  
  // === ERROR DETECTION ===
  
  if (lexer->lookahead == '\n') {
    if (state_.in_rsh_call) {
      // ERROR: Unclosed $rsh() call
      // TODO: Emit error token or handle via valid_symbols
    }
    if (state_.in_expr_interp) {
      // ERROR: Unclosed ${} interpolation
      // TODO: Emit error token or handle via valid_symbols
    }
    state_.at_line_start = true;
  }
  
  return false;
}
```

## 3. Helper Functions

### Pattern Detection

```cpp
bool Scanner::is_assignment(std::string_view buffer) const {
  size_t pos = 0;
  
  // Skip identifier
  if (!std::isalpha(buffer[pos]) && buffer[pos] != '_') return false;
  while (pos < buffer.length() && (std::isalnum(buffer[pos]) || buffer[pos] == '_')) {
    pos++;
  }
  
  // Skip whitespace
  while (pos < buffer.length() && (buffer[pos] == ' ' || buffer[pos] == '\t')) {
    pos++;
  }
  
  // Check for assignment operators: =, +=, -=, *=, /=, %=
  std::string_view remaining = buffer.substr(pos);
  return starts_with(remaining, "=") ||
         starts_with(remaining, "+=") ||
         starts_with(remaining, "-=") ||
         starts_with(remaining, "*=") ||
         starts_with(remaining, "/=") ||
         starts_with(remaining, "%=");
}

bool Scanner::is_keyword(std::string_view buffer) const {
  static const std::array<std::string_view, 8> keywords = {
    "if", "for", "while", "return", "break", "continue", "else", "elif"
  };
  
  for (const auto& kw : keywords) {
    if (starts_with(buffer, kw)) {
      size_t len = kw.length();
      // Check word boundary
      if (len >= buffer.length() ||
          (!std::isalnum(buffer[len]) && buffer[len] != '_')) {
        return true;
      }
    }
  }
  return false;
}

bool Scanner::is_function_call(std::string_view buffer) const {
  // Match: identifier(...) or obj.method(...) or obj[0].method(...)
  size_t pos = 0;
  
  while (pos < buffer.length()) {
    // Skip identifier
    if (!std::isalpha(buffer[pos]) && buffer[pos] != '_') break;
    while (pos < buffer.length() && (std::isalnum(buffer[pos]) || buffer[pos] == '_')) {
      pos++;
    }
    
    // Skip whitespace
    while (pos < buffer.length() && (buffer[pos] == ' ' || buffer[pos] == '\t')) {
      pos++;
    }
    
    // Check for ( - function call
    if (pos < buffer.length() && buffer[pos] == '(') {
      return true;
    }
    
    // Check for . or [ - continue chain
    if (pos < buffer.length() && (buffer[pos] == '.' || buffer[pos] == '[')) {
      pos++;
      if (buffer[pos-1] == '[') {
        // Skip until ]
        while (pos < buffer.length() && buffer[pos] != ']') pos++;
        if (pos < buffer.length()) pos++; // skip ]
      }
      continue;
    }
    
    break;
  }
  
  return false;
}
```

## 4. Testing Strategy

### Unit Tests

```cpp
// Test delimiter tracking
TEST(scanner_delimiter_tracking) {
  Scanner s;
  
  // Simulate EXPR block
  s.process_char('{');
  assert(s.state().expr_block_depth == 1);
  
  s.process_char('{');
  assert(s.state().expr_block_depth == 2);
  
  s.process_char('}');
  assert(s.state().expr_block_depth == 1);
  
  s.process_char('}');
  assert(s.state().expr_block_depth == 0);
}

TEST(scanner_rsh_call_tracking) {
  Scanner s;
  
  // Simulate $rsh()
  s.process("$rsh(");
  assert(s.state().in_rsh_call == true);
  assert(s.state().cmd_paren_depth == 1);
  
  s.process_char(')');
  assert(s.state().in_rsh_call == false);
  assert(s.state().cmd_paren_depth == 0);
}
```

### Integration Tests

```python
# Test multi-line EXPR block
def test_multiline_expr_block():
    code = """
for S in SERVERS {
  echo $S
}
"""
    tree = parse(code)
    assert tree.root_node.type == 'program'
    # Verify EXPR section wraps the for loop
    # Verify CMD section for echo inside the block
```

---

## Success Criteria

- [ ] Scanner tracks all three delimiter types (EXPR blocks, $rsh() calls, ${} interpolations)
- [ ] Line-based detection only occurs when all depths are zero
- [ ] Unclosed $rsh() and ${} emit scanner errors
- [ ] Multi-line EXPR blocks work correctly
- [ ] Nested mode switches parse correctly
- [ ] All existing grammar tests pass
- [ ] New tests for delimiter tracking pass

---

**Last Updated**: 2025-11-20
**Status**: V3 implementation complete and production-ready (97.7% test coverage)
**Architecture**: Mode-aware single grammar with minimal scanner (105 lines, 2 tokens)
**Reference**: See STATUS.md for current implementation details and test results
