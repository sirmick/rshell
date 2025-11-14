defmodule TestHelperTypedAST do
  @moduledoc """
  Helper functions for accessing typed AST structs in tests.

  These helpers allow tests to work with both old map-based AST
  and new typed struct AST with a consistent interface.
  """

  @doc """
  Get the type string from a typed AST node.
  """
  def get_type(node) when is_struct(node) do
    node.__struct__ |> Module.split() |> List.last() |> Macro.underscore()
  end

  def get_type(%{type: type}), do: type
  def get_type(_), do: nil

  @doc """
  Get text from a typed AST node.
  """
  def get_text(%{source_info: %{text: text}}), do: text
  def get_text(%{"text" => text}), do: text
  def get_text(_), do: nil

  @doc """
  Get children from a typed AST node.
  """
  def get_children(%{children: children}) when is_list(children), do: children
  def get_children(%{"children" => children}) when is_list(children), do: children
  def get_children(_), do: []

  @doc """
  Get end_row from a typed AST node.
  """
  def get_end_row(%{source_info: %{end_line: line}}), do: line
  def get_end_row(%{"end_row" => row}), do: row
  def get_end_row(_), do: nil

  @doc """
  Get start_row from a typed AST node.
  """
  def get_start_row(%{source_info: %{start_line: line}}), do: line
  def get_start_row(%{"start_row" => row}), do: row
  def get_start_row(_), do: nil

  @doc """
  Check if node or its children contain ERROR nodes.
  """
  def has_error_in_children?(%BashParser.AST.Types.ErrorNode{}), do: true
  def has_error_in_children?(%{"type" => "ERROR"}), do: true

  def has_error_in_children?(node) do
    children = get_children(node)
    Enum.any?(children, &has_error_in_children?/1)
  end

  @doc """
  Parse input and assert type, with helpful error output on failure.

  Returns the parsed AST on success.
  Outputs input + full AST structure on failure.
  """
  def assert_parse(input, expected_type) do
    case RShell.parse(input) do
      {:ok, ast} ->
        actual_type = get_type(ast)

        if actual_type != expected_type do
          ExUnit.Assertions.flunk("""
          Parse type mismatch

          Input:
          #{input}

          Expected type: #{inspect(expected_type)}
          Actual type: #{inspect(actual_type)}

          Full AST:
          #{inspect(ast, limit: :infinity, pretty: true)}
          """)
        end

        ast

      {:error, reason} ->
        ExUnit.Assertions.flunk("""
        Parse failed

        Input:
        #{input}

        Error: #{inspect(reason)}
        """)
    end
  end

  @doc """
  Assert exact AST structure match for better error messages.
  """
  def assert_ast_structure(ast, expected_structure) do
    actual = simplify_ast(ast)

    if actual != expected_structure do
      ExUnit.Assertions.flunk("""
      AST structure mismatch

      Expected:
      #{inspect(expected_structure, pretty: true)}

      Actual:
      #{inspect(actual, pretty: true)}

      Full AST:
      #{inspect(ast, limit: :infinity, pretty: true)}
      """)
    end
  end

  # Simplify AST to comparable structure (type + children types)
  defp simplify_ast(node) when is_struct(node) do
    type = get_type(node)
    children = get_children(node) |> Enum.map(&simplify_ast/1)
    if children == [], do: type, else: {type, children}
  end

  defp simplify_ast(_), do: nil
end

# Compile test helper modules
Code.require_file("test_helpers/execution_helper.ex", __DIR__)
Code.require_file("support/cli_test_helper.ex", __DIR__)

# Suppress debug logs during tests
Logger.configure(level: :warning)

# Set global test timeout to prevent any test from hanging
# Individual tests can override with @tag timeout: <ms>
# 2 seconds per test
ExUnit.start(timeout: 2000)
