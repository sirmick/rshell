defmodule RShell.ErrorClassifier do
  @moduledoc """
  Classifies parse states to distinguish between:
  1. Complete & valid AST (ready to execute)
  2. Incomplete structures (waiting for closing keywords)
  3. Syntax errors (invalid bash syntax)

  Uses tree-sitter's ERROR nodes as the authoritative signal for syntax errors.

  ## Classification Logic

  - `has_errors=false` → Complete and valid
  - `has_errors=true` AND has ERROR nodes → Syntax error
  - `has_errors=true` AND no ERROR nodes → Incomplete structure

  ## Examples

      # Complete
      {:complete, %{has_errors: false}}

      # Incomplete
      {:incomplete, %{
        has_error_nodes: false,
        incomplete_info: %{type: "if_statement", expecting: "fi"}
      }}

      # Syntax error
      {:syntax_error, %{
        has_error_nodes: true,
        error_info: %{start_row: 0, text: "..."}
      }}
  """

  @doc """
  Classify the parse state based on AST and parser resource.

  Returns `{state, info}` tuple where state is:
  - `:complete` - Ready to execute
  - `:incomplete` - Waiting for more input
  - `:syntax_error` - Invalid syntax
  """
  @spec classify_parse_state(map(), reference()) ::
    {:complete, map()} | {:incomplete, map()} | {:syntax_error, map()}
  def classify_parse_state(ast, resource) do
    has_errors = BashParser.has_errors(resource)

    cond do
      # No errors - tree is complete and valid
      not has_errors ->
        {:complete, %{has_errors: false}}

      # Has ERROR nodes - syntax error (tree-sitter couldn't parse it)
      has_error_nodes?(ast) ->
        {:syntax_error, %{
          has_error_nodes: true,
          error_info: extract_error_info(ast)
        }}

      # No ERROR nodes but has_errors - incomplete structure
      true ->
        {:incomplete, %{
          has_error_nodes: false,
          incomplete_info: identify_incomplete_structure(ast)
        }}
    end
  end

  @doc """
  Recursively check if AST contains ERROR nodes.

  ERROR nodes are tree-sitter's way of marking syntax it couldn't parse.
  """
  @spec has_error_nodes?(term()) :: boolean()
  def has_error_nodes?(node) when is_map(node) do
    if node["type"] == "ERROR" do
      true
    else
      children = node["children"] || []
      Enum.any?(children, &has_error_nodes?/1)
    end
  end
  def has_error_nodes?(_), do: false

  @doc """
  Extract error information from AST for user feedback.

  Finds the first ERROR node and returns its location and text.
  """
  @spec extract_error_info(map()) :: map()
  def extract_error_info(ast) do
    case find_error_node(ast) do
      nil ->
        %{start_row: 0, end_row: 0, text: "unknown"}

      error_node ->
        %{
          start_row: error_node["start_row"] || 0,
          end_row: error_node["end_row"] || 0,
          start_col: error_node["start_col"] || 0,
          end_col: error_node["end_col"] || 0,
          text: error_node["text"] || "unknown"
        }
    end
  end

  @doc """
  Identify which structure is incomplete and what keyword is expected.

  Analyzes typed nodes (if_statement, for_statement, etc.) to determine
  what closing keyword is needed.
  """
  @spec identify_incomplete_structure(map()) :: map()
  def identify_incomplete_structure(ast) do
    children = ast["children"] || []

    # Find the first incomplete structure
    incomplete = Enum.find_value(children, fn child ->
      case child["type"] do
        "if_statement" -> %{type: "if", expecting: "fi"}
        "for_statement" -> %{type: "for", expecting: "done"}
        "while_statement" -> %{type: "while", expecting: "done"}
        "until_statement" -> %{type: "until", expecting: "done"}
        "case_statement" -> %{type: "case", expecting: "esac"}
        _ -> nil
      end
    end)

    incomplete || %{type: "unknown", expecting: "unknown"}
  end

  # Private helpers

  # Find the first ERROR node in the tree
  defp find_error_node(node) when is_map(node) do
    if node["type"] == "ERROR" do
      node
    else
      children = node["children"] || []
      Enum.find_value(children, &find_error_node/1)
    end
  end
  defp find_error_node(_), do: nil
end
