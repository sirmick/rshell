defmodule RShell do
  @moduledoc """
  Enhanced RShell provides comprehensive Elixir bindings for parsing Bash scripts.

  This module offers type-safe AST parsing with precise source position tracking,
  comprehensive node analysis, and advanced Bash script manipulation capabilities.
  """

  alias BashParser.AST.Types
  # alias BashParser.AST  # Unused alias

  @doc """
  Parses a Bash script string and returns a strongly-typed AST.

  ## Parameters
    - `script` - The Bash script content as a string
    - `opts` - Options (currently unused, reserved for future enhancements)

  ## Returns
    - `{:ok, ast}` - Successfully parsed AST with typed structs
    - `{:error, reason}` - Parse error with descriptive message

  ## Examples

      iex> {:ok, ast} = RShell.parse("echo 'Hello World'")
      iex> ast.__struct__
      BashParser.AST.Types.Program

      iex> RShell.parse(123)
      {:error, "Script must be a string, got: 123"}
  """
  @spec parse(String.t(), keyword()) :: {:ok, Types.Program.t()} | {:error, String.t()}
  def parse(script, _opts \\ []) do
    if not is_binary(script) do
      {:error, "Script must be a string, got: #{inspect(script)}"}
    else
      case BashParser.parse_bash(script) do
        {:ok, ast_data} ->
          # Convert the generic map AST to strongly-typed structs
          typed_ast = convert_to_typed(ast_data)
          {:ok, typed_ast}

        {:error, reason} when is_binary(reason) ->
          {:error, "Parse failed: #{reason}"}

        {:error, reason} ->
          {:error, "Parse failed: #{inspect(reason)}"}

        other ->
          {:error, "Unexpected parser response: #{inspect(other, limit: :infinity)}"}
      end
    end
  end

  # Recursively convert generic map AST to typed structs
  defp convert_to_typed(node) when is_map(node) do
    # Use the generated from_map function
    Types.from_map(node)
  end

  defp convert_to_typed(value), do: value

  @doc """
  Parses a Bash script file and returns the enhanced AST.

  Options same as `parse/2`.
  """
  def parse_file(path, opts \\ []) when is_binary(path) do
    case File.read(path) do
      {:ok, content} -> parse(content, opts)
      {:error, reason} -> {:error, "Cannot read file: #{:file.format_error(reason)}"}
    end
  end

  def find_nodes(ast, node_type) do
    cond do
      is_struct(ast) ->
        # Typed structs - use generic traversal
        find_typed_nodes(ast, node_type, [])

      true ->
        []
    end
  end

  defp find_typed_nodes(node, target_type, acc) when is_struct(node) do
    node_type = get_node_type(node)
    acc = if node_type == target_type, do: [node | acc], else: acc

    # Traverse all fields that might contain child nodes
    node
    |> Map.from_struct()
    |> Enum.reduce(acc, fn {_key, value}, acc ->
      traverse_value_for_nodes(value, target_type, acc)
    end)
  end

  defp find_typed_nodes(_node, _target_type, acc), do: acc

  defp traverse_value_for_nodes(value, target_type, acc) when is_struct(value) do
    find_typed_nodes(value, target_type, acc)
  end

  defp traverse_value_for_nodes(values, target_type, acc) when is_list(values) do
    Enum.reduce(values, acc, fn value, acc ->
      traverse_value_for_nodes(value, target_type, acc)
    end)
  end

  defp traverse_value_for_nodes(_value, _target_type, acc), do: acc

  defp get_node_type(node) when is_struct(node) do
    module = node.__struct__
    # Extract the type name from the module name
    # e.g., BashParser.AST.Types.VariableAssignment -> "variable_assignment"
    module
    |> Module.split()
    |> List.last()
    |> Macro.underscore()
  end

  defp get_node_type(_), do: nil

  @doc """
  Finds all nodes of specific types (plural version).
  """
  def find_nodes_multi(ast, node_types) when is_list(node_types) do
    Enum.flat_map(node_types, fn type -> find_nodes(ast, type) end)
    |> Enum.uniq()
  end

  @doc """
  Enhanced traversal function with source position awareness.
  """
  def traverse(ast, fun, opts \\ []) do
    order = Keyword.get(opts, :order, :pre)

    cond do
      is_struct(ast) ->
        traverse_typed(ast, fun, order)
        :ok

      true ->
        {:error, "Invalid AST for traversal"}
    end
  end

  defp traverse_typed(node, fun, :pre) when is_struct(node) do
    fun.(node)
    traverse_typed_children(node, fun, :pre)
  end

  defp traverse_typed(node, fun, :post) when is_struct(node) do
    traverse_typed_children(node, fun, :post)
    fun.(node)
  end

  defp traverse_typed(_node, _fun, _order), do: :ok

  defp traverse_typed_children(node, fun, order) when is_struct(node) do
    node
    |> Map.from_struct()
    |> Enum.each(fn {_key, value} ->
      traverse_typed_value(value, fun, order)
    end)
  end

  defp traverse_typed_value(value, fun, order) when is_struct(value) do
    traverse_typed(value, fun, order)
  end

  defp traverse_typed_value(values, fun, order) when is_list(values) do
    Enum.each(values, fn value -> traverse_typed_value(value, fun, order) end)
  end

  defp traverse_typed_value(_value, _fun, _order), do: :ok

  @doc """
  Gets variable assignments with comprehensive source information.

  Returns list of maps with:
  - `node` - The AST node
  - `source_info` - Position tracking info
  - `name` - Assignment name if available
  - `value` - Assignment value if available
  - `text` - Raw text content
  """
  def variable_assignments(ast) do
    if is_struct(ast) do
      find_nodes(ast, "variable_assignment")
    else
      []
    end
  end

  @doc """
  Gets commands with field extraction (name, arguments, redirects).
  """
  def commands(ast) do
    if is_struct(ast) do
      find_nodes(ast, "command")
    else
      []
    end
  end

  @doc """
  Gets function definitions with enhanced source tracking.
  """
  def function_definitions(ast) do
    if is_struct(ast) do
      find_nodes(ast, "function_definition")
    else
      []
    end
  end

  @doc """
  Gets all binary expressions for analysis.
  """
  def binary_expressions(ast) do
    find_nodes(ast, "binary_expression")
  end

  @doc """
  Gets all arithmetic expressions.
  """
  def arithmetic_expressions(ast) do
    [
      "binary_expression",
      "unary_expression",
      "arithmetic_expansion",
      "arithmetic_parenthesized_expression"
    ]
    |> Enum.flat_map(fn type -> find_nodes(ast, type) end)
  end

  @doc """
  Checks if the parsed script has syntax errors.
  """
  def has_errors?(script) when is_binary(script) do
    case parse(script, field_extraction: false, type_discovery: false) do
      {:ok, _} -> false
      {:error, _} -> true
    end
  end

  @doc """
  Enhanced has_errors? with custom options.
  """
  def has_errors?(script, opts) when is_binary(script) and is_list(opts) do
    case parse(script, opts) do
      {:ok, _} -> false
      {:error, _} -> true
    end
  end

  @doc """
  Extracts all unique node types from the AST.
  Returns a map of node type => field names present.
  """
  def analyze_types(ast) do
    if is_struct(ast) do
      analyze_typed_ast(ast)
    else
      %{node_types: [], type_summary: %{}, total_diverse_types: 0}
    end
  end

  defp analyze_typed_ast(ast) do
    types = collect_typed_types(ast, %{})

    %{
      node_types: Map.keys(types),
      type_summary: types,
      total_diverse_types: map_size(types)
    }
  end

  defp collect_typed_types(node, acc) when is_struct(node) do
    node_type = get_node_type(node)
    acc = Map.put(acc, node_type, true)

    node
    |> Map.from_struct()
    |> Enum.reduce(acc, fn {_key, value}, acc ->
      collect_typed_types_value(value, acc)
    end)
  end

  defp collect_typed_types(_node, acc), do: acc

  defp collect_typed_types_value(value, acc) when is_struct(value) do
    collect_typed_types(value, acc)
  end

  defp collect_typed_types_value(values, acc) when is_list(values) do
    Enum.reduce(values, acc, fn value, acc ->
      collect_typed_types_value(value, acc)
    end)
  end

  defp collect_typed_types_value(_value, acc), do: acc

  @doc """
  Format a node with source position for display.
  """
  def format_node(node, _opts \\ []) do
    if is_struct(node) do
      format_typed_node(node)
    else
      "Unknown node format"
    end
  end

  defp format_typed_node(node) when is_struct(node) do
    node_type = get_node_type(node)
    source_info = Map.get(node, :source_info)

    if source_info do
      """
      #{node_type} [#{source_info.start_row}:#{source_info.start_col}-#{source_info.end_row}:#{source_info.end_col}]
      """
    else
      node_type
    end
  end
end
