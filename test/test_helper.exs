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
  def has_error_in_children?(%{__struct__: :error_node}), do: true
  def has_error_in_children?(%{"type" => "ERROR"}), do: true
  def has_error_in_children?(node) do
    children = get_children(node)
    Enum.any?(children, &has_error_in_children?/1)
  end
end

ExUnit.start()
