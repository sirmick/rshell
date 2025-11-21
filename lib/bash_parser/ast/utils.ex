defmodule BashParser.AST.Utils do
  @moduledoc """
  Shared AST utilities for working with typed AST nodes (bash and RShell).

  Provides common operations:
  - Node type checking (executable?, node type extraction)
  - Safe field access (text, line number)
  - AST pretty-printing
  """

  alias BashParser.AST.Types
  alias BashParser.AST.RShellTypes

  @doc """
  Check if an AST node is executable.

  Returns `true` for nodes that can be executed by the runtime:
  - Commands, pipelines, lists
  - Control structures (if, for, while, case)
  - Variable assignments
  - Function definitions

  ## Examples

      iex> BashParser.AST.Utils.executable?(%Types.Command{})
      true

      iex> BashParser.AST.Utils.executable?(%RShellTypes.CmdLine{})
      true

      iex> BashParser.AST.Utils.executable?(%Types.Comment{})
      false
  """
  def executable?(typed_node) do
    case typed_node do
      # Bash types
      %Types.Command{} -> true
      %Types.Pipeline{} -> true
      %Types.List{} -> true
      %Types.Subshell{} -> true
      %Types.CompoundStatement{} -> true
      %Types.ForStatement{} -> true
      %Types.WhileStatement{} -> true
      %Types.IfStatement{} -> true
      %Types.CaseStatement{} -> true
      %Types.FunctionDefinition{} -> true
      %Types.DeclarationCommand{} -> true
      %Types.VariableAssignment{} -> true
      %Types.UnsetCommand{} -> true
      %Types.TestCommand{} -> true
      %Types.CStyleForStatement{} -> true

      # RShell types
      %RShellTypes.CmdLine{} -> true
      %RShellTypes.ExprLine{} -> true
      %RShellTypes.Command{} -> true
      %RShellTypes.Pipeline{} -> true
      %RShellTypes.Assignment{} -> true
      %RShellTypes.ForStatement{} -> true
      %RShellTypes.WhileStatement{} -> true
      %RShellTypes.IfStatement{} -> true

      _ -> false
    end
  end

  @doc """
  Extract node type as a string.

  Converts the struct module name to a simple string representation.

  ## Examples

      iex> BashParser.AST.Utils.node_type(%Types.Command{})
      "Command"

      iex> BashParser.AST.Utils.node_type(%Types.IfStatement{})
      "IfStatement"
  """
  def node_type(node) when is_struct(node) do
    node.__struct__ |> Module.split() |> List.last()
  end

  def node_type(_), do: "Unknown"

  @doc """
  Get the source text of a node safely.

  Returns the original source text for the node, or `nil` if not available.

  ## Examples

      iex> node = %Types.Command{source_info: %{text: "echo hello"}}
      iex> BashParser.AST.Utils.node_text(node)
      "echo hello"
  """
  def node_text(%{source_info: %{text: text}}) when is_binary(text), do: text
  def node_text(_), do: nil

  @doc """
  Get the starting line number of a node safely.

  Returns the line number where the node starts, or `nil` if not available.

  ## Examples

      iex> node = %Types.Command{source_info: %{start_line: 5}}
      iex> BashParser.AST.Utils.node_line(node)
      5
  """
  def node_line(%{source_info: %{start_line: line}}) when is_integer(line), do: line
  def node_line(_), do: nil

  @doc """
  Pretty-print an AST node to stdout.

  Recursively prints the AST with indentation showing structure.

  ## Options

  - `:indent` - Starting indentation level (default: 0)

  ## Examples

      BashParser.AST.Utils.print(ast)
      # [Program] "echo hello"
      #   [Command] "echo hello"
      #     .parts: [2 items]
      #       [Word] "echo"
      #       [Word] "hello"
  """
  def print(typed_node, opts \\ [])

  def print(typed_node, opts) when is_atom(typed_node) do
    # Handle error nodes (atoms like :error_node)
    indent = Keyword.get(opts, :indent, 0)
    prefix = String.duplicate("  ", indent)
    IO.puts("#{prefix}[ERROR_NODE] #{inspect(typed_node)}")
  end

  def print(typed_node, opts) when is_struct(typed_node) do
    indent = Keyword.get(opts, :indent, 0)
    prefix = String.duplicate("  ", indent)

    type = node_type(typed_node)
    text = node_text(typed_node) || ""

    # Truncate long text
    display_text =
      if String.length(text) > 40 do
        String.slice(text, 0, 37) <> "..."
      else
        text
      end

    IO.puts("#{prefix}[#{type}] #{inspect(display_text)}")

    # Print children recursively if present
    if Map.has_key?(typed_node, :children) && is_list(typed_node.children) do
      Enum.each(typed_node.children, fn child ->
        print(child, indent: indent + 1)
      end)
    end

    # Also print named fields that contain nodes
    typed_node
    |> Map.from_struct()
    |> Map.drop([:__struct__, :source_info, :children])
    |> Enum.each(fn
      {key, value} when is_struct(value) ->
        IO.puts("#{prefix}  .#{key}:")
        print(value, indent: indent + 2)

      {key, values} when is_list(values) ->
        # Check if it's a list of nodes
        if Enum.all?(values, &is_struct/1) && values != [] do
          IO.puts("#{prefix}  .#{key}: [#{length(values)} items]")

          Enum.each(values, fn item ->
            print(item, indent: indent + 2)
          end)
        end

      _ ->
        :skip
    end)
  end
end
