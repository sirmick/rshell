defmodule BashParser.AST.Operator do
  @moduledoc """
  Strongly-typed operator definitions for RShell.

  This module provides explicit type definitions for all operators used in
  RShell expressions and assignments, extracted from tree-sitter AST nodes.

  Instead of working with string literals like "+", "-", "+=", we convert
  them to proper Elixir atoms/types that can be pattern matched and type-checked.
  """

  # Binary Operators
  @type binary_arithmetic :: :add | :subtract | :multiply | :divide | :modulo
  @type binary_comparison :: :eq | :ne | :lt | :le | :gt | :ge
  @type binary_logical :: :and | :or
  @type binary_operator :: binary_arithmetic() | binary_comparison() | binary_logical()

  # Unary Operators
  @type unary_operator :: :negate | :positive | :not

  # Assignment Operators
  @type assignment_operator :: :assign | :add_assign | :sub_assign | :mul_assign | :div_assign | :mod_assign

  @type t :: binary_operator() | unary_operator() | assignment_operator()

  @doc """
  Extract operator from tree-sitter AST node and convert to strongly-typed atom.

  Takes the raw operator field from the AST (which is a map with source_info)
  and returns a typed operator atom.

  ## Examples

      iex> from_ast_node(%{source_info: %{text: "+"}})
      {:ok, :add}

      iex> from_ast_node(%{source_info: %{text: "+="}})
      {:ok, :add_assign}

      iex> from_ast_node(%{source_info: %{text: "invalid"}})
      {:error, "Unknown operator: invalid"}
  """
  @spec from_ast_node(map()) :: {:ok, t()} | {:error, String.t()}
  def from_ast_node(%{source_info: %{text: text}}) when is_binary(text) do
    from_string(text)
  end

  def from_ast_node(node) when is_map(node) do
    # Handle case where AST node doesn't have expected structure
    {:error, "Invalid operator node structure: #{inspect(node)}"}
  end

  @doc """
  Convert operator string to typed atom.

  ## Examples

      iex> from_string("+")
      {:ok, :add}

      iex> from_string("==")
      {:ok, :eq}
  """
  @spec from_string(String.t()) :: {:ok, t()} | {:error, String.t()}
  def from_string(op_text) when is_binary(op_text) do
    case op_text do
      # Binary Arithmetic
      "+" -> {:ok, :add}
      "-" -> {:ok, :subtract}
      "*" -> {:ok, :multiply}
      "/" -> {:ok, :divide}
      "%" -> {:ok, :modulo}

      # Binary Comparison
      "==" -> {:ok, :eq}
      "!=" -> {:ok, :ne}
      "<" -> {:ok, :lt}
      "<=" -> {:ok, :le}
      ">" -> {:ok, :gt}
      ">=" -> {:ok, :ge}

      # Binary Logical
      "&&" -> {:ok, :and}
      "and" -> {:ok, :and}
      "||" -> {:ok, :or}
      "or" -> {:ok, :or}

      # Unary
      "!" -> {:ok, :not}
      "not" -> {:ok, :not}
      # Note: "-" and "+" are context-dependent (binary vs unary)
      # The caller should use from_unary/1 explicitly for unary context

      # Assignment
      "=" -> {:ok, :assign}
      "+=" -> {:ok, :add_assign}
      "-=" -> {:ok, :sub_assign}
      "*=" -> {:ok, :mul_assign}
      "/=" -> {:ok, :div_assign}
      "%=" -> {:ok, :mod_assign}

      _ -> {:error, "Unknown operator: #{op_text}"}
    end
  end

  @doc """
  Convert unary operator string to typed atom.
  Explicitly handles unary context for operators that can be binary or unary.
  """
  @spec from_unary_string(String.t()) :: {:ok, unary_operator()} | {:error, String.t()}
  def from_unary_string(op_text) when is_binary(op_text) do
    case op_text do
      "-" -> {:ok, :negate}
      "+" -> {:ok, :positive}
      "!" -> {:ok, :not}
      "not" -> {:ok, :not}
      _ -> {:error, "Unknown unary operator: #{op_text}"}
    end
  end

  @doc """
  Convert typed operator back to string representation.

  ## Examples

      iex> to_string(:add)
      "+"

      iex> to_string(:add_assign)
      "+="
  """
  @spec to_string(t()) :: String.t()
  def to_string(operator) do
    case operator do
      # Binary Arithmetic
      :add -> "+"
      :subtract -> "-"
      :multiply -> "*"
      :divide -> "/"
      :modulo -> "%"

      # Binary Comparison
      :eq -> "=="
      :ne -> "!="
      :lt -> "<"
      :le -> "<="
      :gt -> ">"
      :ge -> ">="

      # Binary Logical
      :and -> "&&"
      :or -> "||"

      # Unary
      :negate -> "-"
      :positive -> "+"
      :not -> "!"

      # Assignment
      :assign -> "="
      :add_assign -> "+="
      :sub_assign -> "-="
      :mul_assign -> "*="
      :div_assign -> "/="
      :mod_assign -> "%="
    end
  end

  @doc """
  Check if operator is arithmetic.
  """
  @spec arithmetic?(t()) :: boolean()
  def arithmetic?(op) when op in [:add, :subtract, :multiply, :divide, :modulo], do: true
  def arithmetic?(_), do: false

  @doc """
  Check if operator is comparison.
  """
  @spec comparison?(t()) :: boolean()
  def comparison?(op) when op in [:eq, :ne, :lt, :le, :gt, :ge], do: true
  def comparison?(_), do: false

  @doc """
  Check if operator is logical.
  """
  @spec logical?(t()) :: boolean()
  def logical?(op) when op in [:and, :or], do: true
  def logical?(_), do: false

  @doc """
  Check if operator is unary.
  """
  @spec unary?(t()) :: boolean()
  def unary?(op) when op in [:negate, :positive, :not], do: true
  def unary?(_), do: false

  @doc """
  Check if operator is assignment (including compound).
  """
  @spec assignment?(t()) :: boolean()
  def assignment?(op) when op in [:assign, :add_assign, :sub_assign, :mul_assign, :div_assign, :mod_assign], do: true
  def assignment?(_), do: false

  @doc """
  Check if operator is compound assignment.
  """
  @spec compound_assignment?(t()) :: boolean()
  def compound_assignment?(op) when op in [:add_assign, :sub_assign, :mul_assign, :div_assign, :mod_assign], do: true
  def compound_assignment?(_), do: false

  @doc """
  Get the binary operator equivalent of a compound assignment operator.

  ## Examples

      iex> to_binary_op(:add_assign)
      {:ok, :add}

      iex> to_binary_op(:mul_assign)
      {:ok, :multiply}

      iex> to_binary_op(:assign)
      {:error, :not_compound}
  """
  @spec to_binary_op(assignment_operator()) :: {:ok, binary_arithmetic()} | {:error, :not_compound}
  def to_binary_op(op) do
    case op do
      :add_assign -> {:ok, :add}
      :sub_assign -> {:ok, :subtract}
      :mul_assign -> {:ok, :multiply}
      :div_assign -> {:ok, :divide}
      :mod_assign -> {:ok, :modulo}
      _ -> {:error, :not_compound}
    end
  end
end
