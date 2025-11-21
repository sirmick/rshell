# RShell Scanner V2 - Clean C++ Implementation

**Status**: ✅ Tested and Working  
**Date**: 2025-11-19  
**Language**: Clean C++ (C++20)  
**Lines**: 234 (scanner) + 76 (C API) + 73 (header)  

---

## Overview

Scanner V2 is a clean, simple C++ implementation for RShell mode detection. It provides dual grammar mode switching without unnecessary complexity - **no coroutines needed**.

## Architecture

### Components

1. **scanner_v2.hpp** (73 lines) - Header with Scanner class
2. **scanner_v2.cpp** (234 lines) - Clean C++ implementation
3. **scanner_v2_c_api.cpp** (76 lines) - extern "C" wrappers for Tree-sitter
4. **test_scanner_v2_simple.cpp** (164 lines) - Simple test suite

### Key Features

- ✅ **Simple helper functions** - `try_match()`, `consume_until()`, `skip_whitespace()`, `emit()`
- ✅ **Mode-gated transitions** - `$rsh()` only in EXPR mode, `${}` only in CMD mode
- ✅ **Clean serialization** - Initializer list, no lambdas
- ✅ **Line-based detection** - Keywords/assignments → EXPR, else → CMD
- ✅ **No external dependencies** - Just C++ standard library

---

## Building

### Quick Test

```bash
cd rshell-grammar

# Compile scanner
g++ -std=c++20 -Wall -Wextra -I./src -c src/scanner_v2.cpp -o build/scanner_v2.o

# Compile C API wrapper
g++ -std=c++20 -Wall -Wextra -I./src -c src/scanner_v2_c_api.cpp -o build/scanner_v2_c_api.o

# Compile and run tests
g++ -std=c++20 -Wall -Wextra -I./src tests/test_scanner_v2_simple.cpp build/scanner_v2.o -o build/test_scanner_v2_simple
./build/test_scanner_v2_simple
```

### Expected Output

```
Running: keyword_detection... ✓ PASS
Running: assignment_detection... ✓ PASS
Running: serialization_round_trip... ✓ PASS
Running: serialization_default_state... ✓ PASS
Running: serialization_empty_buffer... ✓ PASS
Running: initial_state... ✓ PASS
Running: mode_transitions... ✓ PASS

===== Test Summary =====
Passed: 7
Failed: 0
Total:  7

✓ All tests passed!
```

---

## Scanner Semantics

### Mode Tokens

The scanner emits 6 external tokens:

```cpp
enum class TokenType {
  CmdStart = 0,      // Entering CMD mode
  CmdEnd = 1,        // Exiting CMD mode  
  ExprStart = 2,     // Entering EXPR mode
  ExprEnd = 3,       // Exiting EXPR mode
  ErrorInCmd = 4,    // Syntax error in CMD mode
  ErrorInExpr = 5    // Syntax error in EXPR mode
};
```

### Detection Rules

**EXPR Mode** detected when line starts with:
- Keywords: `if`, `for`, `while`, `return`, `break`, `continue`, `else`
- Assignments: `IDENTIFIER =`, `IDENTIFIER +=`, etc.

**CMD Mode** is the default for all other lines.

### Inline Transitions (Mode-Gated)

- `$rsh(...)` - Execute command from EXPR mode (only works in EXPR)
- `${...}` - Interpolate expression in CMD mode (only works in CMD)

This prevents invalid syntax like `$rsh()` in CMD mode or `${}` in EXPR mode.

---

## Code Structure

### Helper Functions

```cpp
// Pattern matching - try to match a string at current position
bool try_match(void* lexer, std::string_view pattern);

// Buffer building - consume until terminator or max chars
std::string consume_until(void* lexer, char terminator, int max_chars);

// Whitespace handling
void skip_whitespace(void* lexer);

// Token emission
bool emit(void* lexer, TokenType type);
```

### Main Scan Function

```cpp
bool Scanner::scan(void* lexer_ptr, const bool* valid_symbols) {
  // Inline transitions (mode-gated)
  if (state_.current_mode == Mode::Expr && try_match(lexer_ptr, "$rsh(")) { ... }
  if (state_.current_mode == Mode::Cmd && try_match(lexer_ptr, "${")) { ... }
  
  // Closing tokens
  if (lexer->lookahead == ')') { ... }
  if (lexer->lookahead == '}') { ... }
  
  // Line-based mode detection
  if (at line start) {
    std::string line_buffer = consume_until(lexer_ptr, '\n', 40);
    bool is_expr = is_keyword(line_buffer) || is_assignment(line_buffer);
    // Emit mode token if changed
  }
}
```

### Clean Serialization

```cpp
std::vector<char> ScannerState::serialize() const {
  return {
    1,  // version
    static_cast<char>(current_mode),
    at_line_start ? char(1) : char(0),
    // Block depths as 4 bytes each (big-endian)
    char((expr_block_depth >> 24) & 0xFF),
    char((expr_block_depth >> 16) & 0xFF),
    char((expr_block_depth >> 8) & 0xFF),
    char(expr_block_depth & 0xFF),
    char((cmd_block_depth >> 24) & 0xFF),
    char((cmd_block_depth >> 16) & 0xFF),
    char((cmd_block_depth >> 8) & 0xFF),
    char(cmd_block_depth & 0xFF)
  };
}
```

---

## Integration with Grammar

### Tree-sitter Integration

The scanner works with the dual grammar design in `grammar.js`:

```javascript
externals: $ => [
  $.cmd_start,
  $.cmd_end,
  $.expr_start,
  $.expr_end,
  $.error_in_cmd,
  $.error_in_expr,
],

rules: {
  program: $ => repeat(choice(
    $.expr_section,
    $.cmd_section,
  )),
  
  expr_section: $ => seq(
    $.expr_start,
    repeat($._expr_content),
    optional($.expr_end)
  ),
  
  cmd_section: $ => seq(
    $.cmd_start,
    repeat($._cmd_content),
    optional($.cmd_end)
  ),
}
```

---

## Test Coverage

✅ **Pattern Matching**
- Keyword detection (`if`, `for`, `while`, etc.)
- Assignment detection (`=`, `+=`, `-=`, etc.)

✅ **Serialization**
- Round-trip state save/restore
- Default state handling
- Empty buffer handling

✅ **State Management**
- Initial state correctness
- Mode transitions

---

## Why No Coroutines?

Initially designed with C++20 coroutines for "cleaner" code, but they added unnecessary complexity:

- **Before (coroutines)**: 295+ lines, complex generator machinery
- **After (simple C++)**: 234 lines, straightforward control flow
- **Result**: Much cleaner without coroutines!

The simple helper functions (`try_match`, `consume_until`) provide all the abstraction needed.

---

## Design Decisions

### 1. **Mode-Gated Transitions**

Inline transitions check current mode to prevent invalid syntax:
```cpp
// Only allow $rsh() in EXPR mode
if (state_.current_mode == Mode::Expr && try_match(...)) { ... }
```

### 2. **Initializer List Serialization**

Instead of lambdas and push_back loops, use clean initializer list:
```cpp
return {1, char(mode), char(flag), ...};
```

### 3. **Simple Helpers Over Abstraction**

Four simple helpers cover all needs - no need for complex wrappers or coroutines.

---

## Next Steps

- [ ] Integrate scanner.o with Tree-sitter parser.c
- [ ] Test with actual grammar parsing
- [ ] Update grammar.js to use dual grammar properly
- [ ] Performance validation

---

## License

Same as main RShell project.

---

**Status**: ✅ Ready for grammar integration