/**
 * RShell Grammar - Simplified with only 6 scanner tokens
 * The scanner emits mode boundaries, grammar handles everything else
 */

module.exports = grammar({
  name: 'rshell',

  // Only 4 external tokens from scanner for mode boundaries!
  externals: $ => [
    $.cmd_start,      // 0: Entering CMD mode ($rsh()
    $.cmd_end,        // 1: Exiting CMD mode )
    $.expr_start,     // 2: Entering EXPR mode ${
    $.expr_end,       // 3: Exiting EXPR mode }
  ],

  extras: $ => [
    $.comment,
    /\s/,  // All whitespace including newlines
  ],

  conflicts: $ => [
    [$.assignment, $.command],
    [$.property_access],
  ],

  rules: {
    // ===== TOP LEVEL =====
    program: $ => repeat($._item),

    _item: $ => choice(
      $.expr_section,
      $.cmd_section,
      $.comment,
    ),

    // ===== MODE SECTIONS =====
    
    // Expression mode section
    expr_section: $ => prec.left(seq(
      $.expr_start,
      repeat1($._expr_content),
      optional($.expr_end)
    )),

    // Command mode section
    cmd_section: $ => prec.left(seq(
      $.cmd_start,
      repeat1($._cmd_content),
      optional($.cmd_end)
    )),

    // ===== EXPRESSION MODE CONTENT =====
    
    _expr_content: $ => choice(
      $.assignment,
      $.control_flow,
      $.expression,
      $.comment,
    ),

    // Assignments
    assignment: $ => seq(
      field('name', $.identifier),
      field('operator', choice('=', '+=', '-=', '*=', '/=', '%=')),
      field('value', $.expression)
    ),

    // Control flow
    control_flow: $ => choice(
      $.if_statement,
      $.for_statement,
      $.while_statement,
      $.return_statement,
      $.break_statement,
      $.continue_statement,
    ),

    if_statement: $ => seq(
      'if',
      '(',
      field('condition', $.expression),
      ')',
      field('body', $.block)
    ),

    for_statement: $ => seq(
      'for',
      field('variable', $.identifier),
      'in',
      field('iterable', $.expression),
      field('body', $.block)
    ),

    while_statement: $ => seq(
      'while',
      '(',
      field('condition', $.expression),
      ')',
      field('body', $.block)
    ),

    return_statement: $ => prec.right(seq('return', optional($.expression))),
    break_statement: $ => 'break',
    continue_statement: $ => 'continue',

    block: $ => seq(
      '{',
      repeat($._item),
      '}'
    ),

    // Expressions
    expression: $ => choice(
      $.literal,
      $.identifier,
      $.variable_reference,
      $.property_access,
      $.binary_expression,
      $.unary_expression,
      $.parenthesized,
      $.rsh_execution,  // $rsh() in EXPR mode
      $.array,
      $.object,
      $.function_call,
    ),

    literal: $ => choice(
      $.number,
      $.string,
      $.boolean,
    ),

    number: $ => /\-?\d+(\.\d+)?/,
    
    string: $ => choice(
      seq('"', repeat(choice(/[^"\\]+/, /\\./)), '"'),
      seq("'", repeat(choice(/[^'\\]+/, /\\./)), "'"),
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
        $.rsh_execution,
        $.parenthesized,
      )),
      repeat1(seq('.', field('property', $.identifier)))
    )),

    binary_expression: $ => choice(
      // Arithmetic
      prec.left(2, seq($.expression, '+', $.expression)),
      prec.left(2, seq($.expression, '-', $.expression)),
      prec.left(3, seq($.expression, '*', $.expression)),
      prec.left(3, seq($.expression, '/', $.expression)),
      prec.left(3, seq($.expression, '%', $.expression)),
      
      // Comparison
      prec.left(1, seq($.expression, '>', $.expression)),
      prec.left(1, seq($.expression, '<', $.expression)),
      prec.left(1, seq($.expression, '>=', $.expression)),
      prec.left(1, seq($.expression, '<=', $.expression)),
      prec.left(1, seq($.expression, '==', $.expression)),
      prec.left(1, seq($.expression, '!=', $.expression)),
      
      // Logical - both word and symbol forms
      prec.left(0, seq($.expression, choice('and', '&&'), $.expression)),
      prec.left(0, seq($.expression, choice('or', '||'), $.expression)),
    ),

    unary_expression: $ => choice(
      prec(4, seq(choice('not', '!'), $.expression)),
      prec(4, seq('-', $.expression)),
    ),

    parenthesized: $ => seq('(', $.expression, ')'),

    function_call: $ => prec(10, seq(
      field('name', $.identifier),
      '(',
      optional(seq(
        $.expression,
        repeat(seq(',', $.expression))
      )),
      ')'
    )),

    // $rsh() - command execution from EXPR mode
    rsh_execution: $ => seq(
      '$rsh',
      '(',
      // Scanner will emit CMD_START here
      optional($.cmd_section),
      ')'
      // Scanner will emit EXPR_START here to return to EXPR
    ),

    // ===== COMMAND MODE CONTENT =====

    _cmd_content: $ => choice(
      $.command,
      $.pipeline,
      $.comment,
    ),

    command: $ => prec.left(1, seq(
      field('name', $.command_name),
      repeat(field('argument', $.command_argument))
    )),

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
      $.expr_interpolation,  // ${} in CMD mode
      $.cmd_substitution,    // $() in CMD mode
    ),

    command_flag: $ => /\-\-?[a-zA-Z0-9\-_]+/,
    
    word: $ => /[a-zA-Z0-9_\-\.]+/,

    path: $ => choice(
      /\/[a-zA-Z0-9_\-\.\/]+/,        // Absolute paths
      /\.\.?\/[a-zA-Z0-9_\-\.\/]+/,   // Relative paths
      /~\/[a-zA-Z0-9_\-\.\/]*/,        // Home paths
    ),

    pipeline: $ => prec(2, seq(
      $.command,
      repeat1(seq('|', $.command))
    )),

    // ${} - expression interpolation in CMD mode
    expr_interpolation: $ => seq(
      '${',
      // Scanner will emit EXPR_START here
      optional($.expr_section),
      '}'
      // Scanner will emit CMD_START here to return to CMD
    ),

    // $() - command substitution in CMD mode  
    cmd_substitution: $ => seq(
      '$(',
      repeat(choice(
        $.command,
        $.pipeline,
        '|'
      )),
      ')'
    ),

    // ===== COMMON =====
    
    identifier: $ => /[a-zA-Z_][a-zA-Z0-9_]*/,
    
    comment: $ => token(seq('#', /.*/)),
  }
});