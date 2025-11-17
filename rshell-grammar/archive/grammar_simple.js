/**
 * @file RShell grammar - Clean, purpose-built shell with structured data
 * @author RShell Team
 * @license MIT
 */

module.exports = grammar({
  name: 'rshell',

  // NEW: Declare external tokens for line-based mode detection
  externals: $ => [
    $._newline,           // Track newlines
    $.expr_line_start,    // Expression mode line start
    $.cmd_line_start,     // Command mode line start
  ],

  extras: $ => [
    $.comment,
    /[ \t]/,  // Spaces and tabs (but NOT newlines!)
  ],

  rules: {
    // ===== TOP LEVEL =====
    program: $ => repeat($._statement),

    _statement: $ => choice(
      // Expression mode statements (start with EXPR_LINE_START)
      seq($.expr_line_start, $.assignment, optional($._newline)),
      seq($.expr_line_start, $.control_flow, optional($._newline)),
      
      // Command mode statements (start with CMD_LINE_START)
      seq($.cmd_line_start, $.command, optional($._newline)),
      seq($.cmd_line_start, $.pipeline, optional($._newline)),
      
      // Empty line
      $._newline,
      
      $.comment,
    ),

    // ===== COMMANDS =====
    command: $ => seq(
      field('name', $.command_name),
      repeat(field('argument', $._command_argument))
    ),
    
    // Command name - can be identifier or string
    command_name: $ => choice(
      $.identifier,
      $.string,
    ),
    
    // Command arguments - more permissive than expression values
    _command_argument: $ => choice(
      $.command_flag,      // -la, --verbose, etc.
      $.string,
      $.number,
      $.identifier,
      $.variable_reference,
      // Note: no lists/maps in command arguments
    ),
    
    // Command flags (start with - or --)
    command_flag: $ => token(/--?[a-zA-Z0-9_-]+/),

    pipeline: $ => seq(
      $.command,
      repeat1(seq(
        '|',
        $.command
      ))
    ),

    // ===== ASSIGNMENTS =====
    assignment: $ => seq(
      field('name', $.identifier),
      field('operator', choice(
        '=',
        '+=',
        '-=',
        '*=',
        '/='
      )),
      field('value', $._value)
    ),

    // ===== VALUES =====
    _value: $ => choice(
      $.number,
      $.string,
      $.boolean,
      $.list,
      $.map,
      $.identifier,
      $.variable_reference,
      $.property_access,
      $.binary_expression,
      $.unary_expression,
      $.parenthesized_expression,
    ),

    // ===== DATA TYPES =====
    
    // Numbers
    number: $ => /[-]?\d+(\.\d+)?/,

    // Strings
    string: $ => choice(
      seq('"', repeat(choice(/[^"\\]+/, /\\./)), '"'),
      seq("'", repeat(/[^']+/), "'"),
    ),

    // Booleans
    boolean: $ => choice('true', 'false'),

    // Lists
    list: $ => seq(
      '[',
      optional(seq(
        $._value,
        repeat(seq(',', $._value))
      )),
      ']'
    ),

    // Maps
    map: $ => seq(
      '{',
      optional(seq(
        $.map_entry,
        repeat(seq(',', $.map_entry))
      )),
      '}'
    ),

    map_entry: $ => seq(
      field('key', $.string),
      ':',
      field('value', $._value)
    ),

    // Variable reference with optional property access
    variable_reference: $ => seq(
      '$',
      field('name', $.identifier),
      optional($.property_chain)
    ),

    // Property access for expressions (without $)
    property_access: $ => seq(
      field('object', $.identifier),
      field('properties', $.property_chain)
    ),

    // Chain of property accesses (.field)
    property_chain: $ => repeat1(seq(
      '.',
      field('property', $.identifier)
    )),

    // Binary expressions for arithmetic and logic
    binary_expression: $ => choice(
      // Arithmetic
      prec.left(10, seq($._value, '+', $._value)),
      prec.left(10, seq($._value, '-', $._value)),
      prec.left(20, seq($._value, '*', $._value)),
      prec.left(20, seq($._value, '/', $._value)),
      
      // Comparison
      prec.left(5, seq($._value, '>', $._value)),
      prec.left(5, seq($._value, '<', $._value)),
      prec.left(5, seq($._value, '==', $._value)),
      prec.left(5, seq($._value, '!=', $._value)),
      prec.left(5, seq($._value, '>=', $._value)),
      prec.left(5, seq($._value, '<=', $._value)),
      
      // Logical
      prec.left(3, seq($._value, 'and', $._value)),
      prec.left(2, seq($._value, 'or', $._value)),
    ),

    // Unary expressions (not, negative)
    unary_expression: $ => choice(
      prec(30, seq('not', $._value)),
      prec(30, seq('-', $._value)),
    ),

    // Parenthesized expressions
    parenthesized_expression: $ => seq(
      '(',
      $._value,
      ')'
    ),

    // ===== CONTROL FLOW =====
    
    control_flow: $ => choice(
      $.if_statement,
      $.for_statement,
      $.while_statement,
    ),

    // If statement with optional elif and else
    if_statement: $ => seq(
      'if',
      field('condition', $.parenthesized_expression),
      field('consequence', $.block),
      repeat(field('alternative', $.elif_clause)),
      optional(field('alternative', $.else_clause))
    ),

    elif_clause: $ => seq(
      'elif',
      field('condition', $.parenthesized_expression),
      field('consequence', $.block)
    ),

    else_clause: $ => seq(
      'else',
      field('consequence', $.block)
    ),

    // For loop
    for_statement: $ => seq(
      'for',
      field('variable', $.identifier),
      'in',
      field('iterable', $._value),
      field('body', $.block)
    ),

    // While loop
    while_statement: $ => seq(
      'while',
      field('condition', $.parenthesized_expression),
      field('body', $.block)
    ),

    // Block of statements
    block: $ => seq(
      '{',
      optional($._newline),
      repeat(seq(
        $._statement,
        optional($._newline)
      )),
      '}'
    ),

    // Identifier
    identifier: $ => /[a-zA-Z_][a-zA-Z0-9_]*/,

    // Comment
    comment: $ => token(seq('#', /.*/)),
  }
});