# RShell Clean Scanner & Dual Grammar Design

**Date**: 2025-11-19  
**Author**: Design Session  
**Goal**: Super clean, maintainable scanner + grammar for EXPR/CMD dual modes

---

## Core Insight from tree-sitter-python

After studying the Python scanner/grammar, the key insights are:

### 1. Scanner's ONLY Job: Track Structural Boundaries

The Python scanner emits:
- `NEWLINE` - Line boundaries
- `INDENT`/`DEDENT` - Block structure
- `STRING_START`/`STRING_END` - String boundaries

**Critical**: The scanner does NOT try to parse. It just marks boundaries and lets the grammar do the parsing.

### 2. Grammar Handles ALL Syntax

The Python grammar uses scanner tokens to understand structure, then has complete rules for all syntax within those boundaries.

### 3. valid_symbols[] is Sacred

The scanner ONLY emits tokens when `valid_symbols[TOKEN] == true`. This prevents conflicts and infinite loops.

---

## RShell Design: The Clean Way

### Scanner Tokens (Just 2!)

```c
enum TokenType {
    NEWLINE,        // Line boundary (like Python)
    BLOCK_START,    // { in EXPR mode (like Python INDENT)
};
```

**That's it.** No `expr_start`, `cmd_start`, `expr_end`, `cmd_end`.

### Why This Works

The grammar can distinguish EXPR vs CMD by looking at the first token of each line:
- Keyword (`if`, `for`, `while`, `return`, etc.) → EXPR
- Assignment pattern (`identifier =`) → EXPR  
- Everything else → CMD

**The grammar does the detection, not the scanner.**

---

## Complete Scanner Implementation

```c
#include "tree_sitter/parser.h"
#include <ctype.h>
#include <string.h>

enum TokenType {
    NEWLINE,
    BLOCK_START,
};

typedef struct {
    int expr_block_depth;  // Track { } nesting in EXPR mode
} Scanner;

void* tree_sitter_rshell_external_scanner_create() {
    Scanner* scanner = calloc(1, sizeof(Scanner));
    return scanner;
}

void tree_sitter_rshell_external_scanner_destroy(void* payload) {
    free(payload);
}

unsigned tree_sitter_rshell_external_scanner_serialize(
    void* payload, 
    char* buffer
) {
    Scanner* scanner = (Scanner*)payload;
    buffer[0] = (char)(scanner->expr_block_depth & 0xFF);
    buffer[1] = (char)((scanner->expr_block_depth >> 8) & 0xFF);
    return 2;
}

void tree_sitter_rshell_external_scanner_deserialize(
    void* payload,
    const char* buffer,
    unsigned length
) {
    Scanner* scanner = (Scanner*)payload;
    if (length >= 2) {
        scanner->expr_block_depth = 
            (unsigned char)buffer[0] | 
            ((unsigned char)buffer[1] << 8);
    }
}

bool tree_sitter_rshell_external_scanner_scan(
    void* payload,
    TSLexer* lexer,
    const bool* valid_symbols
) {
    Scanner* scanner = (Scanner*)payload;
    
    // Skip whitespace (except newlines)
    while (lexer->lookahead == ' ' || 
           lexer->lookahead == '\t' || 
           lexer->lookahead == '\r') {
        lexer->advance(lexer, true);
    }
    
    // === NEWLINE TOKEN ===
    if (valid_symbols[NEWLINE] && lexer->lookahead == '\n') {
        lexer->advance(lexer, false);
        lexer->mark_end(lexer);
        lexer->result_symbol = NEWLINE;
        return true;
    }
    
    // === BLOCK_START TOKEN ===
    // Only emit when { appears in EXPR context
    // Grammar will request this via valid_symbols
    if (valid_symbols[BLOCK_START] && lexer->lookahead == '{') {
        scanner->expr_block_depth++;
        lexer->advance(lexer, false);
        lexer->mark_end(lexer);
        lexer->result_symbol = BLOCK_START;
        return true;
    }
    
    // Track } for block depth (but don't emit token)
    if (lexer->lookahead == '}' && scanner->expr_block_depth > 0) {
        scanner->expr_block_depth--;
    }
    
    return false;
}
```

**That's the entire scanner!** ~100 lines.

---

## Complete Grammar Implementation

```javascript
module.exports = grammar({
  name: 'rshell',

  externals: $ => [
    $.newline,
    $.block_start,  // { in EXPR mode
  ],

  extras: $ => [
    $.comment,
    /[ \t\r]/,  // Whitespace (NOT newlines - scanner handles those)
  ],

  rules: {
    // === TOP LEVEL ===
    
    program: $ => repeat(seq(
      $._line,
      optional($.newline)
    )),

    _line: $ => choice(
      $.expr_line,
      $.cmd_line,
      $.comment,
    ),

    // === MODE DETECTION IN GRAMMAR ===
    
    // EXPR line: keyword or assignment at start
    expr_line: $ => choice(
      $.assignment,
      $.control_flow,
      $.return_statement,
      $.break_statement,
      $.continue_statement,
      $.expression,  // Standalone expression
    ),
    
    // CMD line: everything else
    cmd_line: $ => choice(
      $.pipeline,
      $.command,
    ),

    // === EXPRESSION MODE ===
    
    assignment: $ => seq(
      field('name', $.identifier),
      field('operator', choice('=', '+=', '-=', '*=', '/=', '%=')),
      field('value', $.expression)
    ),

    control_flow: $ => choice(
      $.if_statement,
      $.for_statement,
      $.while_statement,
    ),

    if_statement: $ => seq(
      'if',
      '(',
      field('condition', $.expression),
      ')',
      field('body', $.expr_block)
    ),

    for_statement: $ => seq(
      'for',
      field('variable', $.identifier),
      'in',
      field('iterable', $.expression),
      field('body', $.expr_block)
    ),

    while_statement: $ => seq(
      'while',
      '(',
      field('condition', $.expression),
      ')',
      field('body', $.expr_block)
    ),

    // EXPR block: { followed by lines
    expr_block: $ => seq(
      $.block_start,  // Scanner token
      repeat(seq(
        $._line,
        optional($.newline)
      )),
      '}'
    ),

    return_statement: $ => prec.right(seq(
      'return', 
      optional($.expression)
    )),
    
    break_statement: $ => 'break',
    continue_statement: $ => 'continue',

    expression: $ => choice(
      $.literal,
      $.identifier,
      $.variable_reference,
      $.property_access,
      $.binary_expression,
      $.unary_expression,
      $.parenthesized,
      $.array,
      $.object,
      $.function_call,
      $.cmd_execution,  // $rsh(...)
    ),

    literal: $ => choice(
      $.number,
      $.string,
      $.boolean,
    ),

    number: $ => /-?\d+(\.\d+)?/,
    
    string: $ => choice(
      seq('"', repeat(/[^"\\]/), '"'),
      seq("'", repeat(/[^'\\]/), "'"),
    ),
    
    boolean: $ => choice('true', 'false'),

    array: $ => seq(
      '[',
      optional(seq(
        $.expression,
        repeat(seq(',', $.expression)),
        optional(',')
      )),
      ']'
    ),

    object: $ => seq(
      '{',
      optional(seq(
        $.object_entry,
        repeat(seq(',', $.object_entry)),
        optional(',')
      )),
      '}'
    ),

    object_entry: $ => seq(
      field('key', $.string),
      ':',
      field('value', $.expression)
    ),

    variable_reference: $ => seq('$', $.identifier),

    property_access: $ => prec.left(1, seq(
      field('object', choice(
        $.identifier,
        $.variable_reference,
      )),
      repeat1(seq('.', field('property', $.identifier)))
    )),

    binary_expression: $ => choice(
      // Arithmetic
      prec.left(2, seq($.expression, '+', $.expression)),
      prec.left(2, seq($.expression, '-', $.expression)),
      prec.left(3, seq($.expression, '*', $.expression)),
      prec.left(3, seq($.expression, '/', $.expression)),
      
      // Comparison
      prec.left(1, seq($.expression, '>', $.expression)),
      prec.left(1, seq($.expression, '<', $.expression)),
      prec.left(1, seq($.expression, '==', $.expression)),
      
      // Logical
      prec.left(0, seq($.expression, 'and', $.expression)),
      prec.left(0, seq($.expression, 'or', $.expression)),
    ),

    unary_expression: $ => prec(4, seq(
      choice('not', '-'),
      $.expression
    )),

    parenthesized: $ => seq('(', $.expression, ')'),

    function_call: $ => seq(
      field('name', $.identifier),
      '(',
      optional(seq(
        $.expression,
        repeat(seq(',', $.expression))
      )),
      ')'
    ),

    // Command execution from EXPR mode
    cmd_execution: $ => seq(
      '$rsh',
      '(',
      optional(choice(
        $.command,
        $.pipeline
      )),
      ')'
    ),

    // === COMMAND MODE ===

    command: $ => seq(
      field('name', $.command_name),
      repeat(field('argument', $.command_argument))
    ),

    command_name: $ => choice(
      $.identifier,
      $.path,
      $.string,
    ),

    command_argument: $ => choice(
      $.command_flag,
      $.word,
      $.string,
      $.variable_reference,
      $.expr_interpolation,  // ${expr}
    ),

    command_flag: $ => /--?[a-zA-Z0-9\-_]+/,
    
    word: $ => /[a-zA-Z0-9_\-\.]+/,

    path: $ => choice(
      /\/[a-zA-Z0-9_\-\.\/]+/,
      /\.\.?\/[a-zA-Z0-9_\-\.\/]+/,
    ),

    pipeline: $ => prec.right(seq(
      $.command,
      repeat1(seq('|', $.command))
    )),

    // Expression interpolation in CMD mode
    expr_interpolation: $ => seq(
      '${',
      $.expression,
      '}'
    ),

    // === COMMON ===
    
    identifier: $ => /[a-zA-Z_][a-zA-Z0-9_]*/,
    
    comment: $ => token(seq('#', /.*/)),
  }
});
```

---

## How It Works: Example Parse

### Input
```rshell
if (X > 10) {
  Y = 1
  echo done
}
```

### Parse Flow

1. **Line 1**: `if (X > 10) {`
   - Grammar sees `if` keyword → matches `if_statement` (EXPR)
   - Consumes `if`, `(`, expression, `)`, then expects `expr_block`
   - `expr_block` rule expects `block_start` token
   - Scanner sees `{`, `valid_symbols[BLOCK_START] == true`, emits token
   - Scanner increments `expr_block_depth = 1`

2. **Line 2**: `Y = 1`
   - Grammar in `expr_block`, expects `_line`
   - Sees `Y` (identifier) followed by `=` → matches `assignment` (EXPR)
   - Grammar requests `newline` token
   - Scanner emits `NEWLINE`

3. **Line 3**: `echo done`
   - Grammar in `expr_block`, expects `_line`
   - Sees `echo` (not a keyword, not assignment) → matches `cmd_line`
   - Specifically matches `command` rule
   - Grammar requests `newline` token
   - Scanner emits `NEWLINE`

4. **Line 4**: `}`
   - Grammar in `expr_block`, expecting repeat or `}`
   - Sees `}` → matches literal `}` in `expr_block` rule
   - Scanner decrements `expr_block_depth = 0`

### Parse Tree
```
program
  if_statement
    condition: binary_expression (X > 10)
    body: expr_block
      assignment (Y = 1)
      command (echo done)
```

---

## Key Design Principles

### 1. Scanner is Dumb
- Only emits `NEWLINE` and `BLOCK_START`
- Tracks `expr_block_depth` for state
- Never tries to detect EXPR vs CMD

### 2. Grammar is Smart
- Uses lookahead to distinguish EXPR vs CMD lines
- Different rule paths for each mode
- `_line` choice handles the branching

### 3. No Mode Tokens
- No `expr_start`, `cmd_start`, `expr_end`, `cmd_end`
- Grammar figures out mode from syntax

### 4. Follows Python Pattern
- Scanner handles structural boundaries (like INDENT/DEDENT)
- Grammar handles all parsing decisions
- `valid_symbols[]` prevents conflicts

---

## Advantages

1. **Simple Scanner**: ~100 lines, easy to debug
2. **No Infinite Loops**: Scanner only emits when asked
3. **Grammar is Self-Documenting**: Mode detection visible in rules
4. **Easier to Extend**: Add features in grammar, scanner unchanged
5. **Better Error Messages**: Grammar knows context

---

## Implementation Plan

### Phase 1: Scanner (1 hour)
1. Implement minimal scanner (NEWLINE + BLOCK_START only)
2. Test serialization/deserialization
3. Verify no infinite loops

### Phase 2: Grammar (2 hours)
1. Implement `_line` choice for mode detection
2. Add EXPR rules (assignment, control flow)
3. Add CMD rules (command, pipeline)
4. Add `expr_block` with `block_start` token

### Phase 3: Testing (1 hour)
1. Test simple assignments (EXPR mode)
2. Test simple commands (CMD mode)
3. Test control flow blocks
4. Test mixed mode in blocks

---

## Migration from Current Implementation

### What to Keep
- Test suite structure
- Build scripts
- Documentation

### What to Replace
- Current scanner (too complex, emits too many tokens)
- Current grammar (relies on scanner mode detection)

### Migration Strategy
1. Create new scanner in `src/scanner_v3.c`
2. Create new grammar in `grammar_v3.js`
3. Run tests side-by-side
4. Switch over when v3 passes more tests

---

**Status**: Design complete, ready for implementation  
**Estimated Time**: 4-5 hours total  
**Risk Level**: Low (following proven Python pattern)