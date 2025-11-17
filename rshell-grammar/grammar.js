/**
 * @file RShell grammar - Experimental fix for multiline structures
 * @author RShell Team
 * @license MIT
 */

module.exports = grammar({
  name: 'rshell',

  // External tokens for line-based mode detection
  externals: $ => [
    $._newline,           // Track newlines
    $.line_start,         // Mark start of new line (generic)
    $.expr_line_start,    // Expression mode line start
    $.cmd_line_start,     // Command mode line start
    $.command_substitution, // NEW: $(...) command substitution
  ],

  // Precedence for resolving ambiguities
  precedences: $ => [
    [$.list, $._statement],
    [$.map, $._statement],
  ],

  extras: $ => [
    $.comment,
    /[ \t]/,  // Spaces and tabs (but NOT newlines!)
  ],

  conflicts: $ => [
    [$._statement],
    [$.list],
    [$.map],
    [$.command],  // Add conflict for command
  ],

  rules: {
    // ===== TOP LEVEL =====
    program: $ => repeat($._statement),

    _statement: $ => choice(
      // Expression mode statements 
      seq($.expr_line_start, $.assignment, optional($._newline)),
      seq($.expr_line_start, $.control_flow, optional($._newline)),
      seq($.line_start, $.assignment, optional($._newline)),
      seq($.line_start, $.control_flow, optional($._newline)),
      
      // Command mode statements
      seq($.cmd_line_start, $.command, optional($._newline)),
      seq($.cmd_line_start, $.pipeline, optional($._newline)),
      seq($.line_start, $.command, optional($._newline)),
      seq($.line_start, $.pipeline, optional($._newline)),
      
      // Comments
      seq($.line_start, $.comment, optional($._newline)),
      seq($.expr_line_start, $.comment, optional($._newline)),
      seq($.cmd_line_start, $.comment, optional($._newline)),
      
      // Empty line
      $._newline,
    ),

    // ===== COMMANDS =====
    command: $ => seq(
      field('name', $.command_name),
      repeat(field('argument', $._command_argument))
    ),
    
    // Command name - can be identifier, string, or path literal
    command_name: $ => choice(
      $.identifier,
      $.string,
      $.path_literal,  // Allow path literals as command names
    ),
    
    // Command arguments
    _command_argument: $ => choice(
      $.command_flag,
      $.string,
      $.number,
      $.identifier,
      $.variable_reference,
      $.command_interpolation,  // NEW: {} interpolation
      $.path_literal,           // NEW: path literals
      /[a-zA-Z0-9_\-\.]+[:]/,  // Allow words ending with colon (like Total:)
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
      $.command_substitution,  // NEW: $(...) command substitution (replaces shell())
      $.template_string,       // NEW: template strings
      $.path_literal,          // NEW: path literals
      $.function_call,         // NEW: generic function calls
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

    // Lists - FIXED to handle internal structure
    list: $ => seq(
      '[',
      optional($._list_content),
      ']'
    ),

    // List content that can span multiple lines
    _list_content: $ => seq(
      $._list_item,
      repeat(seq(',', $._list_item)),
      optional(',')  // Allow trailing comma
    ),

    // List item that can have line starts inside
    _list_item: $ => seq(
      repeat(choice($._newline, $.line_start, $.expr_line_start, $.cmd_line_start)),
      $._value,
      repeat(choice($._newline, $.line_start, $.expr_line_start, $.cmd_line_start))
    ),

    // Maps - FIXED to handle internal structure  
    map: $ => seq(
      '{',
      optional($._map_content),
      '}'
    ),

    // Map content that can span multiple lines
    _map_content: $ => seq(
      $._map_item,
      repeat(seq(',', $._map_item)),
      optional(',')  // Allow trailing comma
    ),

    // Map item that can have line starts inside
    _map_item: $ => seq(
      repeat(choice($._newline, $.line_start, $.expr_line_start, $.cmd_line_start)),
      $.map_entry,
      repeat(choice($._newline, $.line_start, $.expr_line_start, $.cmd_line_start))
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
    property_access: $ => prec.left(20, seq(
      field('object', choice(
        $.identifier,
        $.command_substitution,  // Allow property access on command results
        $.function_call,         // Allow property access on function results
      )),
      field('properties', $.property_chain)
    )),

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
      $.return_statement,
      $.continue_statement,
      $.break_statement,
    ),
    
    // Return statement
    return_statement: $ => prec.right(seq(
      'return',
      optional($._value)
    )),
    
    // Continue statement
    continue_statement: $ => 'continue',
    
    // Break statement
    break_statement: $ => 'break',

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
      repeat(choice(
        $._block_statement,
        $._newline,
        $.line_start,
        $.expr_line_start,
        $.cmd_line_start
      )),
      '}'
    ),

    // Statements inside blocks - without line_start prefix
    _block_statement: $ => choice(
      $.assignment,
      $.control_flow,
      $.command,
      $.pipeline,
      $.comment,
    ),

    // Identifier
    identifier: $ => /[a-zA-Z_][a-zA-Z0-9_]*/,

    // Comment
    comment: $ => token(seq('#', /.*/)),

    // ===== PHASE 3 FEATURES =====
    
    // Command substitution - $(...) captures command and returns result
    // The scanner handles tokenizing the full $(...) construct
    // This replaces the shell() function with a more natural syntax

    // Template strings with ${} interpolation
    template_string: $ => seq(
      '`',
      repeat(choice(
        $.template_chars,
        $.template_interpolation
      )),
      '`'
    ),

    template_chars: $ => /[^`$]+/,
    
    template_interpolation: $ => seq(
      '$',
      '{',
      $._value,  // Any expression
      '}'
    ),

    // {} interpolation in command mode
    command_interpolation: $ => seq(
      '{',
      $._value,  // Any expression
      '}'
    ),

    // Path literals for commands
    path_literal: $ => choice(
      // Absolute paths
      /\/[a-zA-Z0-9_\-\.\/]+/,
      // Relative paths starting with ./ or ../
      /\.\.?\/[a-zA-Z0-9_\-\.\/]+/,
      // Home paths
      /~\/[a-zA-Z0-9_\-\.\/]*/
    ),

    // Generic function calls (for future builtins)
    function_call: $ => seq(
      field('name', $.identifier),
      '(',
      optional($._function_arguments),
      ')'
    ),

    _function_arguments: $ => seq(
      $._value,
      repeat(seq(',', $._value))
    ),
  }
});