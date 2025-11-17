# Getting Started: RShell External Scanner Implementation

**Goal**: Implement line-based mode detection for RShell using a tree-sitter external scanner.

---

## Quick Start

### 1. Read These Files First (in order)

1. **[START_HERE.md](START_HERE.md:1)** - Project overview and current status
2. **[RSHELL_SYNTAX_DESIGN.md](RSHELL_SYNTAX_DESIGN.md:1)** - Complete syntax specification
3. **[LINE_BASED_MODE_DETECTION.md](LINE_BASED_MODE_DETECTION.md:1)** - The parsing challenge
4. **[TREE_SITTER_EXTERNAL_SCANNER.md](TREE_SITTER_EXTERNAL_SCANNER.md:1)** - External scanner deep dive

### 2. Review Examples

Look at these examples to understand what syntax we need to support:
- **[examples/rshell/01_server_health_monitor.rsh](examples/rshell/01_server_health_monitor.rsh:1)**
- **[examples/rshell/06_data_pipeline.rsh](examples/rshell/06_data_pipeline.rsh:1)** (has functions)

### 3. Current Files

**Grammar**: `rshell-grammar/grammar_simple.js` (107 lines, basic template)
**Scanner**: `rshell-grammar/src/scanner.c` (exists, basic shell scanner)
**Test Harness**: `test_grammar_simple.py` (ready to use)

---

## The Task

### What We Need to Build

An external scanner that tracks **line boundaries** so the grammar can distinguish:

```bash
X = 42      # Line starts with IDENTIFIER = → Expression mode
echo hello  # Line starts with IDENTIFIER (no =) → Command mode
```

### External Scanner Requirements

The scanner needs to:
1. Track when we're at the **start of a line**
2. Return a special `LINE_START` token at line boundaries
3. Track `NEWLINE` tokens to know when we've crossed a line

---

## Implementation Steps

### Step 1: Understand the Current Scanner

Read the existing scanner:

```bash
cat rshell-grammar/src/scanner.c
```

Currently it's set up for bash. We need to modify it for RShell's simpler needs.

### Step 2: Define External Tokens in Grammar

In `rshell-grammar/grammar_simple.js`, add:

```javascript
module.exports = grammar({
  name: 'rshell',
  
  // NEW: Declare external tokens
  externals: $ => [
    $._newline,      // Track newlines
    $.line_start,    // Special marker for line starts
  ],
  
  extras: $ => [
    $.comment,
    /[ \t]/,  // Spaces and tabs (but NOT newlines!)
  ],
  
  rules: {
    program: $ => repeat($._statement),
    
    _statement: $ => choice(
      // Expression mode statements (need LINE_START)
      seq($.line_start, $.assignment),
      seq($.line_start, $.control_flow),
      
      // Command mode (no LINE_START needed)
      $.command,
      
      // Statement terminator
      $._newline
    ),
    
    // ... rest of rules
  }
})
```

### Step 3: Implement Scanner State

In `rshell-grammar/src/scanner.c`:

```c
#include <tree_sitter/parser.h>
#include <wctype.h>

// Token types MUST match order in grammar's externals
enum TokenType {
  NEWLINE,      // 0
  LINE_START,   // 1
};

// Scanner state - persisted between calls
typedef struct {
  bool at_line_start;  // Are we at the start of a line?
} Scanner;

// Create scanner
void *tree_sitter_rshell_external_scanner_create() {
  Scanner *scanner = malloc(sizeof(Scanner));
  scanner->at_line_start = true;  // File starts at line start
  return scanner;
}

// Destroy scanner
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
  buffer[0] = scanner->at_line_start ? 1 : 0;
  return 1;  // We wrote 1 byte
}

// Deserialize state
void tree_sitter_rshell_external_scanner_deserialize(
  void *payload,
  const char *buffer,
  unsigned length
) {
  Scanner *scanner = (Scanner *)payload;
  if (length > 0) {
    scanner->at_line_start = (buffer[0] == 1);
  } else {
    scanner->at_line_start = true;
  }
}

// Main scan function
bool tree_sitter_rshell_external_scanner_scan(
  void *payload,
  TSLexer *lexer,
  const bool *valid_symbols
) {
  Scanner *scanner = (Scanner *)payload;
  
  // Check if LINE_START is valid here
  if (valid_symbols[LINE_START] && scanner->at_line_start) {
    // We're at line start! Mark it and reset flag
    scanner->at_line_start = false;
    lexer->result_symbol = LINE_START;
    lexer->mark_end(lexer);  // Don't consume any characters
    return true;
  }
  
  // Check if NEWLINE is valid here
  if (valid_symbols[NEWLINE]) {
    // Skip whitespace (but not newlines)
    while (lexer->lookahead == ' ' || lexer->lookahead == '\t') {
      lexer->advance(lexer, true);  // Skip whitespace
    }
    
    // Found a newline!
    if (lexer->lookahead == '\n') {
      lexer->advance(lexer, false);  // Consume it
      scanner->at_line_start = true;  // Next token is at line start
      lexer->result_symbol = NEWLINE;
      lexer->mark_end(lexer);
      return true;
    }
    
    // Also handle semicolons as statement terminators
    if (lexer->lookahead == ';') {
      lexer->advance(lexer, false);
      scanner->at_line_start = true;  // Semicolon starts new statement
      lexer->result_symbol = NEWLINE;
      lexer->mark_end(lexer);
      return true;
    }
  }
  
  return false;  // No external token matched
}
```

### Step 4: Build and Test

```bash
# Navigate to grammar directory
cd rshell-grammar

# Generate parser
tree-sitter generate

# Test basic parsing
echo 'X = 42' | tree-sitter parse

# Run test suite
cd ..
python test_grammar_simple.py --filter assignments --verbose
```

---

## Development Workflow

### 1. Make Changes

Edit `grammar_simple.js` or `src/scanner.c`

### 2. Regenerate

```bash
cd rshell-grammar
tree-sitter generate
```

If you see conflicts:
```
Unresolved conflict for symbol sequence:

  ...

Expected one of: ...
```

This means you need to add precedence or fix ambiguity.

### 3. Test

```bash
# Quick parse test
echo 'X = 42' | tree-sitter parse

# Full test suite
cd ..
python test_grammar_simple.py

# Specific category with verbose
python test_grammar_simple.py --filter assignments --verbose
```

### 4. Debug

If parsing fails, use `--verbose` to see the parse tree:

```bash
python test_grammar_simple.py --filter assignments --verbose
```

Look for:
- `ERROR` nodes in the tree
- Missing node types
- Incorrect structure

---

## Common Issues and Solutions

### Issue 1: "No rule for LINE_START"

**Problem**: Grammar doesn't know about LINE_START token.

**Solution**: Add to `externals`:
```javascript
externals: $ => [
  $._newline,
  $.line_start,  // Add this
],
```

### Issue 2: Scanner not called

**Problem**: Scanner function signatures wrong.

**Solution**: Check function names exactly match:
- `tree_sitter_rshell_external_scanner_create`
- `tree_sitter_rshell_external_scanner_destroy`
- `tree_sitter_rshell_external_scanner_scan`
- `tree_sitter_rshell_external_scanner_serialize`
- `tree_sitter_rshell_external_scanner_deserialize`

Note: `rshell` must match your grammar name!

### Issue 3: Infinite loop

**Problem**: Scanner keeps returning true without advancing.

**Solution**: Always call `lexer->mark_end(lexer)` before returning true.

### Issue 4: Conflicts

**Problem**: Multiple rules match same input.

**Solution**: Use precedence:
```javascript
_statement: $ => choice(
  prec(2, seq($.line_start, $.assignment)),  // Higher priority
  prec(1, $.command),                         // Lower priority
),
```

---

## Testing Strategy

### Phase 1: Basic Tokens (Week 1)

Test just the scanner without mode switching:

```bash
# Test newline detection
echo -e 'X = 42\nY = 10' | tree-sitter parse

# Should see LINE_START and NEWLINE tokens
python test_grammar_simple.py --filter assignments --verbose
```

### Phase 2: Mode Detection (Week 2)

Test assignment vs command distinction:

```bash
# Both should parse differently
echo 'X = 42' | tree-sitter parse     # Assignment
echo 'echo hello' | tree-sitter parse # Command
```

### Phase 3: Control Flow (Week 3)

Test blocks and nesting:

```bash
echo 'if (X > 5) { Y = 10 }' | tree-sitter parse
```

---

## Key Files to Edit

### Primary Files:
1. **`rshell-grammar/grammar_simple.js`** - Grammar rules
2. **`rshell-grammar/src/scanner.c`** - External scanner

### Supporting Files:
3. **`test_grammar_simple.py`** - Add tests as you go
4. **`rshell-grammar/package.json`** - Already set up

### Don't Edit:
- Generated files in `rshell-grammar/src/` (except scanner.c)
- `rshell-grammar/node_modules/`

---

## Progress Checklist

Use this to track your progress:

```bash
# Week 1: Scanner Foundation
[ ] Scanner compiles without errors
[ ] LINE_START token appears at line starts
[ ] NEWLINE token appears at line ends
[ ] Basic assignments parse: X = 42
[ ] Basic commands parse: echo hello

# Week 2: Mode Detection  
[ ] Assignments distinguished from commands
[ ] Control flow keywords recognized
[ ] Blocks parse correctly
[ ] Nested structures work

# Week 3: Expression Features
[ ] Arithmetic operators work
[ ] Comparisons work
[ ] Logical operators work
[ ] Property access works

# Week 4: Cross-Mode Features
[ ] shell() function works
[ ] {} interpolation in commands
[ ] {} blocks vs {} interpolation disambiguated
```

---

## Quick Reference Commands

```bash
# Generate grammar
cd rshell-grammar && tree-sitter generate && cd ..

# Test single input
echo 'X = 42' | cd rshell-grammar && tree-sitter parse

# Run test suite
python test_grammar_simple.py

# Verbose test
python test_grammar_simple.py --filter assignments --verbose

# Test specific category
python test_grammar_simple.py --filter commands

# Build and test loop (during development)
while true; do
  cd rshell-grammar
  tree-sitter generate && cd ..
  python test_grammar_simple.py --filter assignments
  read -p "Press enter to rebuild..."
done
```

---

## Getting Help

### Tree-Sitter Resources

- **Official Docs**: https://tree-sitter.github.io/tree-sitter/
- **Creating Parsers**: https://tree-sitter.github.io/tree-sitter/creating-parsers
- **External Scanners**: Look at other grammars (Python, Ruby, Bash)

### Example Scanners to Study

```bash
# Python scanner (indentation)
https://github.com/tree-sitter/tree-sitter-python/blob/master/src/scanner.c

# Bash scanner (heredocs)
https://github.com/tree-sitter/tree-sitter-bash/blob/master/src/scanner.c

# Ruby scanner (string interpolation)
https://github.com/tree-sitter/tree-sitter-ruby/blob/master/src/scanner.cc
```

---

## Summary

**Start Here**:
1. Read the 4 key docs above
2. Review examples to understand syntax
3. Implement scanner.c following template above
4. Add externals to grammar_simple.js
5. Test with `python test_grammar_simple.py --verbose`
6. Iterate!

**Remember**: Start simple, test often, add one feature at a time. The scanner is just for line boundaries - the grammar handles everything else!

Good luck! 🚀