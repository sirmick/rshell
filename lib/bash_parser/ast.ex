defmodule BashParser.AST do
  @moduledoc """
  AST (Abstract Syntax Tree) data structure for representing parsed Bash scripts.

  This module provides functionality to traverse and manipulate the parsed AST.
  """

  defstruct [:kind, :text, :start_row, :start_col, :end_row, :end_col, :children]

  @type t :: %__MODULE__{
    kind: String.t(),
    text: String.t(),
    start_row: non_neg_integer(),
    start_col: non_neg_integer(),
    end_row: non_neg_integer(),
    end_col: non_neg_integer(),
    children: list(t())
  }

  @doc """
  Converts a map from the Rust NIF to an AST struct.
  """
  def from_map(map) when is_map(map) do
    %__MODULE__{
      kind: Map.get(map, "kind", ""),
      text: Map.get(map, "text", ""),
      start_row: Map.get(map, "start_row", 0),
      start_col: Map.get(map, "start_col", 0),
      end_row: Map.get(map, "end_row", 0),
      end_col: Map.get(map, "end_col", 0),
      children: Map.get(map, "children", []) |> Enum.map(&from_map/1)
    }
  end

  @doc """
  Finds all nodes of a specific type in the AST.
  """
  def find_nodes(%__MODULE__{} = node, node_type) do
    find_nodes(node, node_type, [])
  end

  defp find_nodes(%__MODULE__{kind: kind, children: children} = node, node_type, acc) when kind == node_type do
    acc = [node | acc]
    Enum.reduce(children, acc, &find_nodes(&1, node_type, &2))
  end

  defp find_nodes(%__MODULE__{children: children}, node_type, acc) do
    Enum.reduce(children, acc, &find_nodes(&1, node_type, &2))
  end

  @doc """
  Gets all variable assignments in the AST.
  """
  def variable_assignments(%__MODULE__{} = ast) do
    ast
    |> find_nodes("variable_assignment")
    |> Enum.map(fn assignment -> assignment.text end)
  end

  @doc """
  Gets all commands in the AST.
  """
  def commands(%__MODULE__{} = ast) do
    ast
    |> find_nodes("command")
    |> Enum.map(fn command -> command.text end)
  end

  @doc """
  Traverses the AST and applies a function to each node.

  Returns `:ok`.
  """
  def traverse(%__MODULE__{} = node, fun) do
    traverse(node, fun, :pre)
  end

  def traverse(%__MODULE__{} = node, fun, order) when order in [:pre, :post] do
    traverse_node(node, fun, order)
    :ok
  end

  defp traverse_node(%__MODULE__{children: children} = node, fun, :pre) do
    fun.(node)
    Enum.each(children, &traverse_node(&1, fun, :pre))
  end

  defp traverse_node(%__MODULE__{children: children} = node, fun, :post) do
    Enum.each(children, &traverse_node(&1, fun, :post))
    fun.(node)
  end

  @doc """
  Gets all function definitions in the AST.
  """
  def function_definitions(%__MODULE__{} = ast) do
    ast
    |> find_nodes("function_definition")
    |> Enum.map(fn func -> func.text end)
  end
end

defimpl Inspect, for: BashParser.AST do
  import Inspect.Algebra

  def inspect(%BashParser.AST{kind: kind, children: _}, _opts) do
    concat(["#BashParser.AST<", kind, ">"])
  end
end
