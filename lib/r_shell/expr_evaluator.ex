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

  def evaluate(%Types.Boolean{source_info: %{text: text}}, _context) do
    text == "true"
  end

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

  def evaluate(%Types.BinaryExpression{source_info: source_info, children: children}, context) do
    # The operator is in the source_info.text of the BinaryExpression node
    # Extract it by finding non-whitespace characters that aren't part of operands
    # OR look for operator nodes in children

    # Try pattern: [left, operator_node, right] or [left, right] with operator in source_info
    {op, left, right} = case children do
      # Three children: [left, operator, right]
      [left, %{source_info: %{text: op_text}}, right] when op_text in ["==", "!=", "<", "<=", ">", ">=", "&&", "||", "+", "-", "*", "/", "%"] ->
        {op_text, left, right}

      # Two children: operator must be extracted differently
      [left, right] ->
        # The operator might be in the BinaryExpression's own text
        # Extract by looking at what's between the operands
        op_text = extract_operator_from_text(source_info.text)
        {op_text, left, right}

      _ ->
        {nil, nil, nil}
    end

    if op && left && right do
      left_val = evaluate(left, context)
      right_val = evaluate(right, context)
      apply_binary_operator(op, left_val, right_val)
    else
      Logger.error("Invalid binary expression structure")
      Logger.error("  source_info.text: #{inspect(source_info.text)}")
      Logger.error("  children count: #{length(children)}")
      Enum.with_index(children) |> Enum.each(fn {child, idx} ->
        Logger.error("  child #{idx}: #{inspect(child.__struct__)}")
      end)
      raise "Invalid binary expression structure"
    end
  end

  # Extract operator from binary expression text (e.g., "X == 5" -> "==")
  defp extract_operator_from_text(text) when is_binary(text) do
    cond do
      String.contains?(text, "==") -> "=="
      String.contains?(text, "!=") -> "!="
      String.contains?(text, "<=") -> "<="
      String.contains?(text, ">=") -> ">="
      String.contains?(text, "&&") -> "&&"
      String.contains?(text, "||") -> "||"
      String.contains?(text, "<") -> "<"
      String.contains?(text, ">") -> ">"
      String.contains?(text, "+") -> "+"
      String.contains?(text, "-") -> "-"
      String.contains?(text, "*") -> "*"
      String.contains?(text, "/") -> "/"
      String.contains?(text, "%") -> "%"
      true -> nil
    end
  end

  defp extract_operator_from_text(_), do: nil

  def evaluate(%Types.UnaryExpression{children: children}, context) do
    case children do
      [%{source_info: %{text: op}}, operand] ->
        operand_val = evaluate(operand, context)
        apply_unary_operator(op, operand_val)

      _ ->
        raise "Invalid unary expression structure"
    end
  end

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
    Map.get(context.env || %{}, name)
  end

  def evaluate(%Types.VariableReference{children: children}, context) do
    case children do
      [%Types.Identifier{source_info: %{text: name}}] ->
        Map.get(context.env || %{}, name)

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
  def truthy?(0.0), do: false
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
