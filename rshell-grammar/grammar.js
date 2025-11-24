/**
 * RShell Grammar V3 - Clean Dual-Mode Implementation
 * 
 * Mode detection happens in the grammar, not the scanner.
 * Scanner only provides structural tokens (NEWLINE, BLOCK_START).
 * 
 * EXPR mode: Keywords (if/for/while) or assignments (X = ...)
 * CMD mode: Everything else (shell commands, pipelines)
 */

module.exports = grammar({
  name: 'rshell',

  externals: $ => [
    $.newline,       // Line boundary from scanner
    $.block_start,   // { in EXPR mode from scanner
  ],

  extras: $ => [
    $.comment,
    /[ \t\r]/,  // Whitespace (NOT newlines - scanner handles those)
  ],

  conflicts: $ => [
    [$.assignment, $.command],
    [$.expression, $.command_name],
    [$.property_access],
    [$.command_argument, $.raw_argument],  // raw_argument can contain variable_reference
    [$.expr_line, $.cmd_line],  // Top-level ambiguity between EXPR and CMD mode
  ],

  rules: {
    // ===== TOP LEVEL =====
    
    program: $ => repeat(choice(
      seq($._line, optional($.newline)),
      $.newline,  // Empty lines
    )),

    _line: $ => choice(
      seq(
        $._statement,
        repeat(seq(';', $._statement))
      ),
      $.comment,
    ),

    // ===== MODE DETECTION IN GRAMMAR =====
    
    // EXPR line: starts with keyword or assignment pattern
    // Note: Bare identifiers are commands, not expressions
    expr_line: $ => choice(
      $.assignment,
      $.control_flow,
      $.return_statement,
      $.break_statement,
      $.continue_statement,
      // Specific expression types only (not bare identifiers)
      $.function_call,
      $.cmd_execution,
    ),
    
    // CMD line: shell commands and pipelines
    cmd_line: $ => choice(
      $.pipeline,
      $.command,
    ),

    // Semicolon-separated statements on one line
    _statement: $ => choice(
      $.expr_line,
      $.cmd_line,
    ),

    // ===== EXPRESSION MODE =====
    
    // Assignment with high precedence to win conflicts with command
    // Note: No token.immediate() to allow spaces: X = 42
    assignment: $ => prec.dynamic(15, seq(
      field('name', $.identifier),
      field('operator', choice('=', '+=', '-=', '*=', '/=', '%=')),
      field('value', $.expression)
    )),

    control_flow: $ => choice(
      $.if_statement,
      $.for_statement,
      $.while_statement,
    ),

    if_statement: $ => seq(
      'if',
      field('condition', $.parenthesized),
      field('body', $.expr_block),
      repeat(field('alternative', $.elif_clause)),
      optional(field('alternative', $.else_clause)),
    ),

    elif_clause: $ => seq(
      'elif',
      field('condition', $.parenthesized),
      field('body', $.expr_block)
    ),

    else_clause: $ => seq(
      'else',
      field('body', $.expr_block)
    ),

    for_statement: $ => seq(
      'for',
      '(',
      field('variable', $.identifier),
      'in',
      field('iterable', $.expression),
      ')',
      field('body', $.expr_block)
    ),

    while_statement: $ => seq(
      'while',
      field('condition', $.parenthesized),
      field('body', $.expr_block)
    ),

    // EXPR block: Uses scanner's block_start token, then mixed content
    // Aliased as 'block' for test compatibility
    expr_block: $ => alias(seq(
      $.block_start,  // Scanner emits this for { in EXPR context
      repeat(choice(
        seq($._line, optional($.newline)),
        $.newline,
      )),
      '}'
    ), $.block),

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
      // Note: boolean removed - true/false are now parsed as regular identifiers/commands
      // Future: Add $true/$false as read-only variables for expression context
    ),

    number: $ => /-?\d+(\.\d+)?/,
    
    string: $ => choice(
      seq('"', repeat(choice(/[^"\\]+/, /\\./)), '"'),
      seq("'", repeat(choice(/[^'\\]+/, /\\./)), "'"),
    ),

    array: $ => seq(
      '[',
      optional($.newline),  // Allow newline after [
      optional(seq(
        $.expression,
        repeat(seq(
          optional($.newline),  // Allow newline before comma
          ',',
          optional($.newline),  // Allow newline after comma
          $.expression
        )),
        optional(','),
        optional($.newline)  // Allow trailing newline before ]
      )),
      optional($.newline),
      ']'
    ),

    object: $ => seq(
      '{',
      optional($.newline),  // Allow newline after {
      optional(seq(
        $.object_entry,
        repeat(seq(
          optional($.newline),  // Allow newline before comma
          ',',
          optional($.newline),  // Allow newline after comma
          $.object_entry
        )),
        optional(','),
        optional($.newline)  // Allow trailing newline before }
      )),
      optional($.newline),
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
        $.cmd_execution,
        $.parenthesized,
      )),
      alias(repeat1(seq('.', field('property', $.identifier))), $.property_chain)
    )),

    binary_expression: $ => choice(
      // Arithmetic
      prec.left(2, seq(field('left', $.expression), field('operator', '+'), field('right', $.expression))),
      prec.left(2, seq(field('left', $.expression), field('operator', '-'), field('right', $.expression))),
      prec.left(3, seq(field('left', $.expression), field('operator', '*'), field('right', $.expression))),
      prec.left(3, seq(field('left', $.expression), field('operator', '/'), field('right', $.expression))),
      prec.left(3, seq(field('left', $.expression), field('operator', '%'), field('right', $.expression))),
      
      // Comparison
      prec.left(1, seq(field('left', $.expression), field('operator', '>'), field('right', $.expression))),
      prec.left(1, seq(field('left', $.expression), field('operator', '<'), field('right', $.expression))),
      prec.left(1, seq(field('left', $.expression), field('operator', '>='), field('right', $.expression))),
      prec.left(1, seq(field('left', $.expression), field('operator', '<='), field('right', $.expression))),
      prec.left(1, seq(field('left', $.expression), field('operator', '=='), field('right', $.expression))),
      prec.left(1, seq(field('left', $.expression), field('operator', '!='), field('right', $.expression))),
      
      // Logical
      prec.left(0, seq(field('left', $.expression), field('operator', choice('and', '&&')), field('right', $.expression))),
      prec.left(0, seq(field('left', $.expression), field('operator', choice('or', '||')), field('right', $.expression))),
    ),

    unary_expression: $ => choice(
      prec(4, seq(field('operator', choice('not', '!')), field('argument', $.expression))),
      prec(4, seq(field('operator', '-'), field('argument', $.expression))),
    ),

    parenthesized: $ => alias(
      seq('(', $.expression, ')'),
      $.parenthesized_expression
    ),

    function_call: $ => prec(10, seq(
      field('name', $.identifier),
      '(',
      optional(seq(
        $.expression,
        repeat(seq(',', $.expression))
      )),
      ')'
    )),

    // Command execution from EXPR mode
    cmd_execution: $ => seq(
      '$rsh',
      '(',
      optional(choice(
        $.pipeline,
        $.command
      )),
      ')'
    ),

    // ===== COMMAND MODE =====

    // Command with low precedence to lose conflicts with assignment
    command: $ => prec.left(-1, seq(
      field('name', $.command_name),
      repeat(field('argument', $.command_argument))
    )),

    command_name: $ => choice(
      $.identifier,
      $.path,
    ),

    command_argument: $ => prec.left(choice(
      $.command_flag,
      $.raw_argument,        // Higher priority - matches complex patterns first
      $.word,
      $.string,
      $.variable_reference,
      $.expr_interpolation,  // ${expr}
      $.cmd_substitution,    // $()
    )),

    command_flag: $ => /--?[a-zA-Z0-9\-_]+/,
    
    word: $ => /[a-zA-Z0-9_\-\.]+/,
    
    // Raw argument: Can contain special chars (: / =) and ${} interpolations
    // Matches patterns like: https://${HOST}:${PORT}/api
    // Note: Starts with non-operator to avoid conflicting with assignments
    raw_argument: $ => prec.left(seq(
      /[a-zA-Z0-9_\-\.\/:%@&+]/,  // First char: NOT = or assignment operators
      optional(repeat(choice(
        /[a-zA-Z0-9_\-\.\/:=@%&+]+/,  // Rest can include = for URLs, etc.
        $.expr_interpolation,          // ${...} embedded
        $.variable_reference,          // $VAR embedded
      )))
    )),

    path: $ => choice(
      /\/[a-zA-Z0-9_\-\.\/]+/,              // Absolute paths: /bin/ls
      /\.\.?\/[a-zA-Z0-9_\-\.\/]*/,         // Relative paths: ./script or ../dir
      /~\/[a-zA-Z0-9_\-\.\/]*/,             // Home paths: ~/file
    ),

    pipeline: $ => prec(2, seq(
      $.command,
      repeat1(seq('|', $.command))
    )),

    // Expression interpolation in CMD mode
    expr_interpolation: $ => seq(
      '${',
      $.expression,
      '}'
    ),

    // Bash-style command substitution
    cmd_substitution: $ => seq(
      '$(',
      optional(choice(
        $.command,
        $.pipeline
      )),
      ')'
    ),

    // ===== COMMON =====
    
    identifier: $ => /[a-zA-Z_][a-zA-Z0-9_]*/,
    
    comment: $ => token(seq('#', /.*/)),
  }
});