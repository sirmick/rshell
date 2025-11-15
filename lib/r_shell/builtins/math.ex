defmodule RShell.Builtins.Math do
  @moduledoc """
  Mathematical operations builtin namespace.

  All builtins in this module are accessed via the `math:` namespace prefix.

  Examples:
    - `math:add 5 3` - Addition
    - `math:sub 10 3` - Subtraction
    - `math:mul 2 5` - Multiplication
    - `math:div 10 2` - Division
  """

  use RShell.Builtins.Helpers, namespace: true
  alias RShell.Builtins.Utils

  @namespace "math"

  @doc """
  Get the namespace for this builtin module.
  """
  def namespace, do: @namespace

  @doc """
  add - add numbers

  Add two or more numbers and output the result to stdout as a native integer or float.

  Usage: math:add NUM1 NUM2 [NUM3...]

  Arguments are converted to numbers automatically:
    - Strings are parsed as integers or floats
    - Booleans: true=1, false=0
    - Native numbers are used directly

  Returns the sum on stdout as a native data type.
  On error, reports to stderr and returns exit code 1.

  ## Examples
      math:add 5 3
      math:add 10 20 30
      math:add 3.14 2.86
      env X=5
      math:add $X 10
  """
  @shell_add_opts :argv
  def shell_add([], _stdin, context) do
    stderr = "math:add: requires at least one argument\n"
    {context, Utils.stream(""), Utils.stream(stderr), 1}
  end

  def shell_add(argv, _stdin, context) do
    try do
      numbers = Enum.map(argv, &Utils.to_number/1)
      result = Enum.sum(numbers)
      # Output native type to stdout
      {context, Stream.concat([[result]]), Utils.stream(""), 0}
    rescue
      e ->
        stderr = "math:add: error: #{Exception.message(e)}\n"
        {context, Utils.stream(""), Utils.stream(stderr), 1}
    end
  end

  @doc """
  sub - subtract numbers

  Subtract numbers from left to right and output the result to stdout as a native integer or float.

  Usage: math:sub NUM1 NUM2 [NUM3...]

  With one argument, returns the negation.
  With multiple arguments, subtracts each subsequent number from the running total.

  Arguments are converted to numbers automatically.

  ## Examples
      math:sub 10 3
      math:sub 100 20 5
      math:sub 5
  """
  @shell_sub_opts :argv
  def shell_sub([], _stdin, context) do
    stderr = "math:sub: requires at least one argument\n"
    {context, Utils.stream(""), Utils.stream(stderr), 1}
  end

  def shell_sub([first], _stdin, context) do
    try do
      result = -Utils.to_number(first)
      {context, Stream.concat([[result]]), Utils.stream(""), 0}
    rescue
      e ->
        stderr = "math:sub: error: #{Exception.message(e)}\n"
        {context, Utils.stream(""), Utils.stream(stderr), 1}
    end
  end

  def shell_sub([first | rest], _stdin, context) do
    try do
      numbers = Enum.map(rest, &Utils.to_number/1)
      result = Enum.reduce(numbers, Utils.to_number(first), fn n, acc -> acc - n end)
      {context, Stream.concat([[result]]), Utils.stream(""), 0}
    rescue
      e ->
        stderr = "math:sub: error: #{Exception.message(e)}\n"
        {context, Utils.stream(""), Utils.stream(stderr), 1}
    end
  end

  @doc """
  mul - multiply numbers

  Multiply two or more numbers and output the result to stdout as a native integer or float.

  Usage: math:mul NUM1 NUM2 [NUM3...]

  Arguments are converted to numbers automatically.

  ## Examples
      math:mul 5 3
      math:mul 2 3 4
      math:mul 3.5 2
  """
  @shell_mul_opts :argv
  def shell_mul([], _stdin, context) do
    stderr = "math:mul: requires at least one argument\n"
    {context, Utils.stream(""), Utils.stream(stderr), 1}
  end

  def shell_mul(argv, _stdin, context) do
    try do
      numbers = Enum.map(argv, &Utils.to_number/1)
      result = Enum.reduce(numbers, 1, fn n, acc -> acc * n end)
      {context, Stream.concat([[result]]), Utils.stream(""), 0}
    rescue
      e ->
        stderr = "math:mul: error: #{Exception.message(e)}\n"
        {context, Utils.stream(""), Utils.stream(stderr), 1}
    end
  end

  @doc """
  div - divide numbers

  Divide numbers from left to right and output the result to stdout as a native float.

  Usage: math:div NUM1 NUM2 [NUM3...]

  Division always returns a float. Division by zero reports an error.

  Arguments are converted to numbers automatically.

  ## Examples
      math:div 10 2
      math:div 100 5 2
      math:div 7 2
  """
  @shell_div_opts :argv
  def shell_div([], _stdin, context) do
    stderr = "math:div: requires at least one argument\n"
    {context, Utils.stream(""), Utils.stream(stderr), 1}
  end

  def shell_div([_first], _stdin, context) do
    stderr = "math:div: requires at least two arguments\n"
    {context, Utils.stream(""), Utils.stream(stderr), 1}
  end

  def shell_div([first | rest], _stdin, context) do
    try do
      numbers = Enum.map(rest, &Utils.to_number/1)

      # Check for division by zero
      if Enum.any?(numbers, &(&1 == 0)) do
        stderr = "math:div: division by zero\n"
        {context, Utils.stream(""), Utils.stream(stderr), 1}
      else
        result = Enum.reduce(numbers, Utils.to_number(first) / 1.0, fn n, acc -> acc / n end)
        {context, Stream.concat([[result]]), Utils.stream(""), 0}
      end
    rescue
      e ->
        stderr = "math:div: error: #{Exception.message(e)}\n"
        {context, Utils.stream(""), Utils.stream(stderr), 1}
    end
  end

  @doc """
  eq - test numeric equality

  Compare two numbers for equality and output 1 (true) or 0 (false) to stdout.

  Usage: math:eq NUM1 NUM2

  Returns 1 if NUM1 equals NUM2, otherwise 0.
  Exit code is always 0 (success).

  Arguments are converted to numbers automatically.

  ## Examples
      math:eq 5 5
      math:eq 10 3
      env X=42
      math:eq $X 42
  """
  @shell_eq_opts :argv
  def shell_eq([], _stdin, context) do
    stderr = "math:eq: requires exactly two arguments\n"
    {context, Utils.stream(""), Utils.stream(stderr), 1}
  end

  def shell_eq([_first], _stdin, context) do
    stderr = "math:eq: requires exactly two arguments\n"
    {context, Utils.stream(""), Utils.stream(stderr), 1}
  end

  def shell_eq([first, second], _stdin, context) do
    try do
      left = Utils.to_number(first)
      right = Utils.to_number(second)
      result = if left == right, do: 1, else: 0
      {context, Stream.concat([[result]]), Utils.stream(""), 0}
    rescue
      e ->
        stderr = "math:eq: error: #{Exception.message(e)}\n"
        {context, Utils.stream(""), Utils.stream(stderr), 1}
    end
  end

  def shell_eq(_argv, _stdin, context) do
    stderr = "math:eq: requires exactly two arguments\n"
    {context, Utils.stream(""), Utils.stream(stderr), 1}
  end

  @doc """
  neq - test numeric inequality

  Compare two numbers for inequality and output 1 (true) or 0 (false) to stdout.

  Usage: math:neq NUM1 NUM2

  Returns 1 if NUM1 does not equal NUM2, otherwise 0.
  Exit code is always 0 (success).

  Arguments are converted to numbers automatically.

  ## Examples
      math:neq 5 3
      math:neq 10 10
      env X=42
      math:neq $X 100
  """
  @shell_neq_opts :argv
  def shell_neq([], _stdin, context) do
    stderr = "math:neq: requires exactly two arguments\n"
    {context, Utils.stream(""), Utils.stream(stderr), 1}
  end

  def shell_neq([_first], _stdin, context) do
    stderr = "math:neq: requires exactly two arguments\n"
    {context, Utils.stream(""), Utils.stream(stderr), 1}
  end

  def shell_neq([first, second], _stdin, context) do
    try do
      left = Utils.to_number(first)
      right = Utils.to_number(second)
      result = if left != right, do: 1, else: 0
      {context, Stream.concat([[result]]), Utils.stream(""), 0}
    rescue
      e ->
        stderr = "math:neq: error: #{Exception.message(e)}\n"
        {context, Utils.stream(""), Utils.stream(stderr), 1}
    end
  end

  def shell_neq(_argv, _stdin, context) do
    stderr = "math:neq: requires exactly two arguments\n"
    {context, Utils.stream(""), Utils.stream(stderr), 1}
  end

  @doc """
  mod - modulo operation

  Compute the modulo of two numbers and output the result to stdout.

  Usage: math:mod DIVIDEND DIVISOR

  The modulo operation returns the remainder with the sign of the divisor.
  For positive divisors, this ensures a non-negative result.

  Arguments are converted to integers automatically.

  ## Examples
      math:mod 10 3
      math:mod -10 3
      math:mod 10 -3
  """
  @shell_mod_opts :argv
  def shell_mod([], _stdin, context) do
    stderr = "math:mod: requires exactly two arguments\n"
    {context, Utils.stream(""), Utils.stream(stderr), 1}
  end

  def shell_mod([_first], _stdin, context) do
    stderr = "math:mod: requires exactly two arguments\n"
    {context, Utils.stream(""), Utils.stream(stderr), 1}
  end

  def shell_mod([first, second], _stdin, context) do
    try do
      dividend = Utils.to_integer(first)
      divisor = Utils.to_integer(second)

      if divisor == 0 do
        stderr = "math:mod: division by zero\n"
        {context, Utils.stream(""), Utils.stream(stderr), 1}
      else
        # Modulo: result has same sign as divisor
        result = Integer.mod(dividend, divisor)
        {context, Stream.concat([[result]]), Utils.stream(""), 0}
      end
    rescue
      e ->
        stderr = "math:mod: error: #{Exception.message(e)}\n"
        {context, Utils.stream(""), Utils.stream(stderr), 1}
    end
  end

  def shell_mod(_argv, _stdin, context) do
    stderr = "math:mod: requires exactly two arguments\n"
    {context, Utils.stream(""), Utils.stream(stderr), 1}
  end

  @doc """
  rem - remainder operation

  Compute the remainder of dividing two numbers and output the result to stdout.

  Usage: math:rem DIVIDEND DIVISOR

  The remainder operation returns the remainder with the sign of the dividend.

  Arguments are converted to integers automatically.

  ## Examples
      math:rem 10 3
      math:rem -10 3
      math:rem 10 -3
  """
  @shell_rem_opts :argv
  def shell_rem([], _stdin, context) do
    stderr = "math:rem: requires exactly two arguments\n"
    {context, Utils.stream(""), Utils.stream(stderr), 1}
  end

  def shell_rem([_first], _stdin, context) do
    stderr = "math:rem: requires exactly two arguments\n"
    {context, Utils.stream(""), Utils.stream(stderr), 1}
  end

  def shell_rem([first, second], _stdin, context) do
    try do
      dividend = Utils.to_integer(first)
      divisor = Utils.to_integer(second)

      if divisor == 0 do
        stderr = "math:rem: division by zero\n"
        {context, Utils.stream(""), Utils.stream(stderr), 1}
      else
        # Remainder: result has same sign as dividend
        result = rem(dividend, divisor)
        {context, Stream.concat([[result]]), Utils.stream(""), 0}
      end
    rescue
      e ->
        stderr = "math:rem: error: #{Exception.message(e)}\n"
        {context, Utils.stream(""), Utils.stream(stderr), 1}
    end
  end

  def shell_rem(_argv, _stdin, context) do
    stderr = "math:rem: requires exactly two arguments\n"
    {context, Utils.stream(""), Utils.stream(stderr), 1}
  end
end
