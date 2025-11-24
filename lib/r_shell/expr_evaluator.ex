defmodule RShell.ExprEvaluator do
  @moduledoc """
  Evaluates RShell EXPR mode AST nodes to native Elixir terms.

  This module bridges the gap between the RShell grammar's AST representation
  and native Elixir data structures. It converts:
  - Number nodes → integers/floats
  - String nodes → binary strings
  - Boolean nodes → true/false atoms
  - Array nodes → Elixir lists
  - Object nodes → Elixir maps
  - BinaryExpression nodes → evaluated results (arithmetic, comparison, etc.)
  - Identifier nodes → variable lookups from context

  ## Examples

      # Simple number
      evaluate(%Types.Number{source_info: %{text: "42"}}, context)
      # => 42

      # Map literal
      evaluate(%Types.Object{children: [...]}, context)
      # => %{"a" => 2, "b" => [2, 3, 4]}

      # Binary expression
      evaluate(%Types.BinaryExpression{...}, context)
      # => 15

  NO JSON PARSING - AST nodes directly convert to native types!
  """

  alias BashParser.AST.RShellTypes, as: Types
  require Logger

  @doc """
  Evaluate an EXPR mode AST node to a native Elixir value.

  Requires a context map with at least an `:env` key for variable lookups.
  """
  @spec evaluate(Types.t(), map()) :: term()

  # ============================================================================
  # Literals
  # ============================================================================

  # Numbers
  def evaluate(%Types.Number{source_info: %{text: text}}, _context) do
    case Integer.parse(text) do
      {int, ""} ->
        int

      _ ->
        case Float.parse(text) do
          {float, ""} -> float
          _ -> raise "Invalid number: #{text}"
        end
    end
  end

  # Strings
  def evaluate(%Types.String{source_info: %{text: text}}, _context) do
    # Remove surrounding quotes from string literals
    cond do
      String.starts_with?(text, "\"") and String.ends_with?(text, "\"") ->
        String.slice(text, 1..-2//1)

      String.starts_with?(text, "'") and String.ends_with?(text, "'") ->
        String.slice(text, 1..-2//1)

      true ->
        text
    end
  end

  # Boolean removed from grammar - true/false are now identifiers
  # See lines 181-191 for handling of true/false/null as special identifiers

  def evaluate(%Types.Array{children: children}, context) when is_list(children) do
    Enum.map(children, &evaluate(&1, context))
  end

  def evaluate(%Types.Object{children: children}, context) when is_list(children) do
    Enum.reduce(children, %{}, fn
      %Types.ObjectEntry{key: key_node, value: value_node}, acc ->
        key = extract_key(key_node, context)
        value = evaluate(value_node, context)
        Map.put(acc, key, value)

      _, acc ->
        acc
    end)
  end

  # ============================================================================
  # Expressions
  # ============================================================================

  def evaluate(%Types.BinaryExpression{left: left, operator: operator, right: right, source_info: source_info}, context) do
    # Extract operator text - it can be a struct with source_info or a plain token
    op_text = case operator do
      %{source_info: %{text: text}} -> text
      text when is_binary(text) -> text
      nil ->
        # Operator not in field - extract from source text by analyzing the expression
        source_text = source_info.text || ""
        # Find the operator in the source text by checking for known operators
        cond do
          String.contains?(source_text, " == ") -> "=="
          String.contains?(source_text, " != ") -> "!="
          String.contains?(source_text, " <= ") -> "<="
          String.contains?(source_text, " >= ") -> ">="
          String.contains?(source_text, " < ") -> "<"
          String.contains?(source_text, " > ") -> ">"
          String.contains?(source_text, " && ") -> "&&"
          String.contains?(source_text, " || ") -> "||"
          String.contains?(source_text, " and ") -> "and"
          String.contains?(source_text, " or ") -> "or"
          String.contains?(source_text, " + ") -> "+"
          String.contains?(source_text, " - ") -> "-"
          String.contains?(source_text, " * ") -> "*"
          String.contains?(source_text, " / ") -> "/"
          String.contains?(source_text, " % ") -> "%"
          true ->
            Logger.warning("BinaryExpression: could not extract operator from: #{inspect(source_text)}")
            nil
        end
      _ ->
        Logger.warning("BinaryExpression operator is unexpected format: #{inspect(operator)}")
        nil
    end

    if op_text do
      left_val = evaluate(left, context)
      right_val = evaluate(right, context)
      apply_binary_operator(op_text, left_val, right_val)
    else
      Logger.error("Cannot evaluate BinaryExpression without operator")
      nil
    end
  end

  # Unary expressions (grouped here with other expressions)
  def evaluate(%Types.UnaryExpression{operator: operator, argument: argument}, context) do
    # Extract operator text - it can be a struct with source_info or a plain token
    op_text = case operator do
      %{source_info: %{text: text}} -> text
      text when is_binary(text) -> text
      _ -> nil
    end

    if op_text do
      argument_val = evaluate(argument, context)
      apply_unary_operator(op_text, argument_val)
    else
      Logger.error("Cannot evaluate UnaryExpression without operator")
      nil
    end
  end

  # Parenthesized expressions
  def evaluate(%Types.ParenthesizedExpression{children: children}, context) when is_list(children) do
    # ParenthesizedExpression may have tokens like '(' and ')' as children
    # Find the actual expression node (not plain text tokens)
    expr = Enum.find(children, fn child ->
      is_struct(child) and not match?(%{source_info: %{text: text}} when text in ["(", ")"], child)
    end)

    if expr, do: evaluate(expr, context), else: nil
  end

  # ============================================================================
  # Variables and Property Access
  # ============================================================================

  def evaluate(%Types.Identifier{source_info: %{text: "true"}}, _context) do
    true
  end

  def evaluate(%Types.Identifier{source_info: %{text: "false"}}, _context) do
    false
  end

  def evaluate(%Types.Identifier{source_info: %{text: "null"}}, _context) do
    nil
  end

  def evaluate(%Types.Identifier{source_info: %{text: name}}, context) do
    # Handle nil context or nil env gracefully
    env = case context do
      %{env: env} when is_map(env) -> env
      _ -> %{}
    end
    Map.get(env, name)
  end

  def evaluate(%Types.VariableReference{children: children}, context) do
    # Handle nil context or nil env gracefully
    env = case context do
      %{env: env} when is_map(env) -> env
      _ -> %{}
    end

    case children do
      [%Types.Identifier{source_info: %{text: name}}] ->
        Map.get(env, name)

      _ ->
        nil
    end
  end

  def evaluate(%Types.PropertyAccess{object: object_node, children: property_nodes}, context) do
    # Start with base object
    base_value = evaluate(object_node, context)

    # Apply each property access in sequence
    Enum.reduce(property_nodes, base_value, fn property_node, acc_value ->
      apply_property_access(acc_value, property_node, context)
    end)
  end

  # ============================================================================
  # Wrapper Nodes
  # ============================================================================

  def evaluate(%Types.Expression{children: [child]}, context) do
    evaluate(child, context)
  end

  def evaluate(%Types.Literal{children: [child]}, context) do
    evaluate(child, context)
  end

  def evaluate(%Types.Parenthesized{children: [child]}, context) do
    evaluate(child, context)
  end

  # ============================================================================
  # Word/Path (for keys in object literals)
  # ============================================================================

  def evaluate(%Types.Word{source_info: %{text: text}}, _context) do
    text
  end

  def evaluate(%Types.Path{source_info: %{text: text}}, _context) do
    text
  end

  # ============================================================================
  # Fallback
  # ============================================================================

  def evaluate(node, _context) do
    node_type = if is_struct(node), do: node.__struct__ |> Module.split() |> List.last(), else: "unknown"
    Logger.warning("ExprEvaluator: Unhandled node type #{node_type}, returning nil")
    nil
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================


  # Extract key from ObjectEntry key node
  defp extract_key(%Types.String{source_info: %{text: text}}, _context) do
    # Remove quotes
    cond do
      String.starts_with?(text, "\"") and String.ends_with?(text, "\"") ->
        String.slice(text, 1..-2//1)

      String.starts_with?(text, "'") and String.ends_with?(text, "'") ->
        String.slice(text, 1..-2//1)

      true ->
        text
    end
  end

  defp extract_key(%Types.Word{source_info: %{text: text}}, _context), do: text
  defp extract_key(%Types.Identifier{source_info: %{text: text}}, _context), do: text
  defp extract_key(%{source_info: %{text: text}}, _context), do: text
  defp extract_key(_, _context), do: ""

  # Apply binary operators
  defp apply_binary_operator("+", left, right) when is_number(left) and is_number(right), do: left + right
  defp apply_binary_operator("-", left, right) when is_number(left) and is_number(right), do: left - right
  defp apply_binary_operator("*", left, right) when is_number(left) and is_number(right), do: left * right
  defp apply_binary_operator("/", left, right) when is_number(left) and is_number(right), do: left / right
  defp apply_binary_operator("%", left, right) when is_integer(left) and is_integer(right), do: rem(left, right)

  # Comparison operators
  defp apply_binary_operator("==", left, right), do: left == right
  defp apply_binary_operator("!=", left, right), do: left != right
  defp apply_binary_operator("<", left, right), do: left < right
  defp apply_binary_operator("<=", left, right), do: left <= right
  defp apply_binary_operator(">", left, right), do: left > right
  defp apply_binary_operator(">=", left, right), do: left >= right

  # Logical operators
  defp apply_binary_operator("&&", left, right), do: truthy?(left) and truthy?(right)
  defp apply_binary_operator("||", left, right), do: truthy?(left) or truthy?(right)

  # String concatenation
  defp apply_binary_operator("+", left, right) when is_binary(left) and is_binary(right), do: left <> right

  defp apply_binary_operator(op, left, right) do
    raise "Unsupported binary operator '#{op}' for types #{type_name(left)} and #{type_name(right)}"
  end

  # Apply unary operators
  defp apply_unary_operator("-", operand) when is_number(operand), do: -operand
  defp apply_unary_operator("+", operand) when is_number(operand), do: operand
  defp apply_unary_operator("!", operand), do: not truthy?(operand)

  defp apply_unary_operator(op, operand) do
    raise "Unsupported unary operator '#{op}' for type #{type_name(operand)}"
  end

  # Property access on native values
  defp apply_property_access(map, %{source_info: %{text: key}}, _context) when is_map(map) do
    # Remove quotes if present
    clean_key = String.trim(key, "\"")
    Map.get(map, clean_key)
  end

  defp apply_property_access(list, %{source_info: %{text: index_str}}, _context) when is_list(list) do
    case Integer.parse(index_str) do
      {index, ""} -> Enum.at(list, index)
      _ -> nil
    end
  end

  defp apply_property_access(_value, _property, _context), do: nil

  # Truthiness for logical operators (PUBLIC for use in Runtime)
  def truthy?(nil), do: false
  def truthy?(false), do: false
  def truthy?(0), do: false
  def truthy?(n) when is_float(n) and (n == 0.0 or n == -0.0), do: false
  def truthy?(""), do: false
  def truthy?([]), do: false
  def truthy?(%{} = map) when map == %{}, do: false
  def truthy?(_), do: true

  # Type name for error messages
  defp type_name(val) when is_integer(val), do: "integer"
  defp type_name(val) when is_float(val), do: "float"
  defp type_name(val) when is_binary(val), do: "string"
  defp type_name(val) when is_boolean(val), do: "boolean"
  defp type_name(val) when is_list(val), do: "list"
  defp type_name(val) when is_map(val), do: "map"
  defp type_name(nil), do: "nil"
  defp type_name(_), do: "unknown"
end
