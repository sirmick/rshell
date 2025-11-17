# Tree-Sitter External Scanner: The Secret Weapon

**TL;DR**: External scanners let you write custom C/C++ code to handle **context-sensitive** parsing that's impossible with pure grammar rules.

---

## What is an External Scanner?

An external scanner is a **custom C/C++ function** that tree-sitter calls during parsing to:
1. **Track state** across tokens (e.g., "are we at the start of a line?")
2. **Make context-sensitive decisions** (e.g., "is this `{` a block or interpolation?")
3. **Handle complex tokenization** (e.g., indentation-sensitive syntax like Python)

### How It Works

```
┌─────────────────────────────────────────────────┐
│          Tree-Sitter Parser                     │
│                                                  │
│  ┌────────────────────┐    ┌─────────────────┐ │
│  │  Grammar Rules     │    │ External        │ │
│  │  (grammar.js)      │◄──►│ Scanner         │ │
│  │                    │    │ (scanner.c)     │ │
│  │  - Context-free    │    │ - Stateful      │ │
│  │  - Declarative     │    │ - Imperative    │ │
│  └────────────────────┘    └─────────────────┘ │
│                                                  │
└─────────────────────────────────────────────────┘
```

**Normal grammar**: "Here's the pattern to match"  
**External scanner**: "Here's code that decides what to match based on context"

---

## Why Do We Need It?

### Problem: Line-Based Mode Detection

In RShell, we need to know:
```bash
X = 42      # Line starts with IDENTIFIER = → Expression mode
echo hello  # Line starts with IDENTIFIER (no =) → Command mode
```

**Pure grammar can't easily check**: "Is this identifier at the start of a line?"

**External scanner CAN**:
- Track: "Did we just see a newline?"
- Return: Special token `LINE_START_IDENTIFIER` vs `IDENTIFIER`

---

## How External Scanners Work

### 1. Declare External Tokens in Grammar

```javascript
// In grammar.js
module.exports = grammar({
  name: 'rshell',
  
  // Declare which tokens the external scanner handles
  externals: $ => [
    $._newline,           // Track newlines
    $.line_start_marker,  // Special marker for line starts
  ],
  
  rules: {
    program: $ => repeat($._statement),
    
    _statement: $ => choice(
      // Use the external token to detect line starts
      seq($.line_start_marker, $.assignment),
      seq($.line_start_marker, $.control_flow),
      $.command  // Commands don't need line_start_marker
    ),
    
    assignment: $ => seq(
      $.identifier,
      '=',
      $._expression
    ),
    // ... other rules
  }
})
```

### 2. Implement Scanner in C

```c
// In src/scanner.c
#include <tree_sitter/parser.h>
#include <wctype.h>

enum TokenType {
  NEWLINE,
  LINE_START_MARKER,
};

// Scanner state - persisted between calls
typedef struct {
  bool at_line_start;  // Are we at the start of a line?
} Scanner;

// Allocate scanner state
void *tree_sitter_rshell_external_scanner_create() {
  Scanner *scanner = malloc(sizeof(Scanner));
  scanner->at_line_start = true;  // Start of file = start of line
  return scanner;
}

// Free scanner state
void tree_sitter_rshell_external_scanner_destroy(void *payload) {
  Scanner *scanner = (Scanner *)payload;
  free(scanner);
}

// Serialize state (for incremental parsing)
unsigned tree_sitter_rshell_external_scanner_serialize(
  void *payload,
  char *buffer
) {
  Scanner *scanner = (Scanner *)payload;
  buffer[0] = scanner->at_line_start;
  return 1;
}

// Deserialize state
void tree_sitter_rshell_external_scanner_deserialize(
  void *payload,
  const char *buffer,
  unsigned length
) {
  Scanner *scanner = (Scanner *)payload;
  if (length > 0) {
    scanner->at_line_start = buffer[0];
  }
}

// Main scanning function - called by tree-sitter
bool tree_sitter_rshell_external_scanner_scan(
  void *payload,
  TSLexer *lexer,
  const bool *valid_symbols
) {
  Scanner *scanner = (Scanner *)payload;
  
  // Check if LINE_START_MARKER is valid here
  if (valid_symbols[LINE_START_MARKER]) {
    if (scanner->at_line_start) {
      // We're at line start! Mark it and reset flag
      scanner->at_line_start = false;
      lexer->result_symbol = LINE_START_MARKER;
      return true;
    }
  }
  
  // Check if NEWLINE is valid here
  if (valid_symbols[NEWLINE]) {
    // Skip whitespace
    while (iswspace(lexer->lookahead) && lexer->lookahead != '\n') {
      lexer->advance(lexer, true);
    }
    
    // Found a newline!
    if (lexer->lookahead == '\n') {
      lexer->advance(lexer, false);
      scanner->at_line_start = true;  // Next token is at line start
      lexer->result_symbol = NEWLINE;
      return true;
    }
  }
  
  return false;  // No external token matched
}
```

### 3. How It Gets Called

```
Parsing: X = 42\necho hello
         ^
         
1. Parser: "I need a statement"
   Scanner: valid_symbols[LINE_START_MARKER] = true
   Scanner: at_line_start = true → Return LINE_START_MARKER
   
2. Parser: "I see LINE_START_MARKER, try $.assignment"
   Grammar: Matches "X = 42"
   
3. Parser: "I need a newline or semicolon"
            ^
            
4. Scanner: valid_symbols[NEWLINE] = true
   Scanner: lookahead = '\n' → Return NEWLINE
   Scanner: at_line_start = true  // Set for next token
   
5. Parser: "I need a statement"
            echo hello
            ^
   Scanner: at_line_start = true → Return LINE_START_MARKER
   
6. Parser: "Try $.assignment... no '=' found"
7. Parser: "Try $.command... matches!"
```

---

## Real-World Examples

### Python Indentation

Python uses external scanner to track indentation levels:

```c
// Pseudo-code
typedef struct {
  int indent_stack[100];  // Stack of indentation levels
  int stack_size;
} Scanner;

bool scan(Scanner *scanner, TSLexer *lexer, const bool *valid) {
  if (at_line_start) {
    int spaces = count_spaces(lexer);
    int current_indent = scanner->indent_stack[scanner->stack_size - 1];
    
    if (spaces > current_indent) {
      push(scanner->indent_stack, spaces);
      return INDENT;
    } else if (spaces < current_indent) {
      pop(scanner->indent_stack);
      return DEDENT;
    }
  }
}
```

### Bash Heredocs

Bash uses scanner to track heredoc delimiters:

```c
typedef struct {
  char heredoc_delimiter[256];  // Current heredoc delimiter
  bool in_heredoc;
} Scanner;

bool scan(Scanner *scanner, TSLexer *lexer, const bool *valid) {
  if (valid[HEREDOC_START]) {
    // Read delimiter: << EOF
    read_delimiter(lexer, scanner->heredoc_delimiter);
    scanner->in_heredoc = true;
    return HEREDOC_START;
  }
  
  if (scanner->in_heredoc && valid[HEREDOC_END]) {
    // Check if current line matches delimiter
    if (matches(lexer, scanner->heredoc_delimiter)) {
      scanner->in_heredoc = false;
      return HEREDOC_END;
    }
  }
}
```

---

## How This Helps RShell

### Without External Scanner

```javascript
// Can't reliably detect line starts
_statement: $ => choice(
  $.assignment,  // IDENTIFIER = ...
  $.command      // IDENTIFIER ...
),

// Ambiguity! How do we know which to try first?
```

### With External Scanner

```javascript
_statement: $ => choice(
  // Only try assignment at line start
  seq($.line_start_marker, $.assignment),
  
  // Only try control flow at line start
  seq($.line_start_marker, $.control_flow),
  
  // Commands can appear anywhere (inside blocks)
  $.command
),
```

Now the grammar is unambiguous!

---

## External Scanner Capabilities

### What It CAN Do

1. **Track state**: Remember things across tokens
2. **Look at raw characters**: Access `lexer->lookahead`
3. **Count things**: Spaces, braces, nesting depth
4. **Match patterns**: Check for specific sequences
5. **Context-aware**: Different behavior based on state

### What It CAN'T Do

1. **Parse complex structures**: Still need grammar for that
2. **Backtrack**: No going back in input
3. **Access AST**: Only sees raw character stream
4. **Be too slow**: Must be fast (called frequently)

---

## When to Use External Scanner

### Good Use Cases ✅

- **Indentation-sensitive** syntax (Python, YAML)
- **Heredocs** with dynamic delimiters (Bash, Ruby)
- **Line-based** mode switching (RShell!)
- **String interpolation** with complex escaping
- **Comment nesting** (/* /* */ */)

### Bad Use Cases ❌

- **Simple tokenization** - Use grammar rules instead
- **Complex logic** - Too slow, use grammar + precedence
- **AST manipulation** - Wrong layer

---

## RShell Implementation Strategy

### Option 1: Minimal Scanner (Recommended)

Just track line starts:

```c
enum TokenType {
  NEWLINE,
  LINE_START_MARKER,
};

// State: Just one boolean
typedef struct {
  bool at_line_start;
} Scanner;

// Simple logic:
// - When we see '\n', set at_line_start = true
// - When asked for LINE_START_MARKER at line start, return it
```

**Pros**: Simple, easy to debug  
**Cons**: Grammar still needs precedence for disambiguation

### Option 2: Full Context Tracking (Complex)

Track mode explicitly:

```c
enum TokenType {
  NEWLINE,
  EXPR_MODE_START,
  CMD_MODE_START,
};

typedef struct {
  bool at_line_start;
  enum Mode { EXPR, CMD } mode;
  int brace_depth;
} Scanner;

// Complex logic to track modes
```

**Pros**: More explicit control  
**Cons**: Complex, harder to debug, might not be needed

### Option 3: Hybrid (Best?)

Scanner just handles line detection, grammar handles mode:

```javascript
// External scanner
externals: $ => [
  $._newline,
  $.line_start,  // Just marks line starts
],

// Grammar decides mode based on what follows
_statement: $ => choice(
  // Line starts with IDENTIFIER =
  prec(2, seq($.line_start, $.assignment)),
  
  // Line starts with keyword
  prec(2, seq($.line_start, $.control_flow)),
  
  // Everything else
  prec(1, $.command)
),
```

---

## Development Workflow

### 1. Start Without Scanner

Try pure grammar first:
```bash
python test_grammar_simple.py
```

### 2. Identify Ambiguities

```
Error: Conflict between $.assignment and $.command
```

### 3. Add Minimal Scanner

```c
// Just line tracking
bool at_line_start;
```

### 4. Update Grammar

```javascript
externals: $ => [$.line_start],

_statement: $ => choice(
  seq($.line_start, $.assignment),
  $.command
),
```

### 5. Test Iteratively

```bash
# Rebuild after changing scanner.c
cd rshell-grammar
tree-sitter generate
tree-sitter test

# Test with harness
python test_grammar_simple.py --verbose
```

---

## Summary

**External Scanner = Custom C code for stateful parsing**

### For RShell:
- **Use it for**: Line-start detection
- **Don't use it for**: Everything else (keep grammar simple)
- **Strategy**: Minimal scanner + precedence-based grammar

### Key Points:
1. Lets you track state (like "at line start")
2. Called by parser to produce special tokens
3. Must be fast and simple
4. Great for context-sensitive syntax
5. Harder to debug than pure grammar

**Bottom Line**: External scanner is the escape hatch when grammar rules aren't enough. For RShell, we'll use it minimally to track line boundaries, letting the grammar handle the rest with precedence rules.