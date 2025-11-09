defmodule RShell do
  @moduledoc """
  RShell provides Elixir bindings for parsing Bash scripts using tree-sitter.

  This module provides functionality to parse Bash scripts into Abstract Syntax
  Trees (AST) that can be manipulated and analyzed from Elixir.
  """

  alias BashParser.AST

  @doc """
  Parses a Bash script string and returns the AST.

  Returns `{:ok, ast}` on success or `{:error, reason}` on failure.
  """
  def parse(script) when is_binary(script) do
    case BashParser.parse_bash(script) do
      {:ok, ast_data} -> {:ok, AST.from_map(ast_data)}
      {:error, reason} -> {:error, reason}
      error -> {:error, "Unknown error: #{inspect(error)}"}
    end
  end

  @doc """
  Parses a Bash script file and returns the AST.

  Returns `{:ok, ast}` on success or `{:error, reason}` on failure.
  """
  def parse_file(path) when is_binary(path) do
    case File.read(path) do
      {:ok, content} -> parse(content)
      {:error, reason} -> {:error, "Cannot read file: #{:file.format_error(reason)}"}
    end
  end

  @doc """
  Finds specific types of nodes in the AST.

  Returns a list of nodes matching the specified type.
  """
  def find_nodes(%AST{} = ast, node_type) do
    AST.find_nodes(ast, node_type)
  end

  @doc """
  Traverses the AST and applies a function to each node.

  Returns `:ok`.
  """
  def traverse(%AST{} = ast, fun) do
    AST.traverse(ast, fun)
    :ok
  end

  @doc """
  Gets all variable assignments in the parsed script.
  """
  def variable_assignments(%AST{} = ast) do
    AST.variable_assignments(ast)
  end

  @doc """
  Gets all commands in the parsed script.
  """
  def commands(%AST{} = ast) do
    AST.commands(ast)
  end

  @doc """
  Gets all function definitions in the parsed script.
  """
  def function_definitions(%AST{} = ast) do
    AST.function_definitions(ast)
  end

  @doc """
  Checks if the parsed script has any syntax errors.
  """
  def has_errors?(script) when is_binary(script) do
    case parse(script) do
      {:ok, _} -> false
      {:error, _} -> true
    end
  end

  @doc """
  Print a string representation of the AST.
  """
  def print_ast(%AST{} = ast) do
    inspect(ast)
  end
end
