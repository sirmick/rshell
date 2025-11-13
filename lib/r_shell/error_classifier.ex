defmodule RShell.ErrorClassifier do
  @moduledoc """
  Classifies parse states for typed AST structs to distinguish between:
  1. Complete & valid AST (ready to execute)
  2. Incomplete structures (waiting for closing keywords like fi, done, esac)
  3. Syntax errors (invalid bash syntax)

  Uses tree-sitter's ERROR nodes as the authoritative signal for syntax errors.

  ## Classification Logic

  - No ERROR nodes, no incomplete structures → `:complete`
  - Has ERROR nodes → `:syntax_error`
  - Has structure nodes (IfStatement, ForStatement) but no ERROR nodes → `:incomplete`

  ## Examples

      # Using typed AST (from IncrementalParser.get_current_ast)
      {:ok, typed_ast} = IncrementalParser.get_current_ast(parser_pid)

      case ErrorClassifier.classify(typed_ast) do
        :complete -> "rshell> "
        :incomplete -> "     > "  # Awaiting closing keyword
        :syntax_error -> "  err> "
      end

  ## Usage in CLI

      prompt = case ErrorClassifier.classify(typed_ast) do
        :complete -> "rshell> "
        :incomplete -> "     > "
        :syntax_error -> "  err> "
      end
  """

  @doc """
  Classify a typed AST struct.

  Returns one of:
  - `:complete` - Ready to execute, no errors
  - `:incomplete` - Awaiting closing keyword (fi, done, esac, etc.)
  - `:syntax_error` - Invalid syntax detected

  ## Examples

      iex> ErrorClassifier.classify(complete_ast)
      :complete

      iex> ErrorClassifier.classify(if_without_fi_ast)
      :incomplete

      iex> ErrorClassifier.classify(invalid_syntax_ast)
      :syntax_error
  """
  @spec classify(term()) :: :complete | :incomplete | :syntax_error
  def classify(ast) do
    cond do
      # Check incomplete structures FIRST (softer error state)
      # This catches cases like "for i in 1 2 3\ndo" which have ForStatement + tree errors
      has_incomplete_structure?(ast) ->
        :incomplete

      # THEN check for ERROR nodes (true syntax errors)
      # This catches cases like "for i in 1 2 3" (no ForStatement, only ERROR)
      has_error_nodes?(ast) ->
        :syntax_error

      # No errors, no incomplete structures - complete
      true ->
        :complete
    end
  end

  @doc """
  Check if typed AST has incomplete structures.

  An AST is incomplete if it has control flow structure nodes
  (IfStatement, ForStatement, WhileStatement, etc.) that are
  awaiting closing keywords.

  ## Examples

      # if true; then (no fi) - incomplete
      iex> ErrorClassifier.has_incomplete_structure?(if_stmt_ast)
      true

      # if true; then echo hi; fi - complete
      iex> ErrorClassifier.has_incomplete_structure?(complete_if_ast)
      false
  """
  @spec has_incomplete_structure?(term()) :: boolean()
  def has_incomplete_structure?(ast) do
    # Check if we have an incomplete structure by looking for structure nodes
    # that don't have their expected closing
    identify_incomplete_structure(ast) != nil
  end

  @doc """
  Check if typed AST struct contains ERROR nodes.

  ERROR nodes indicate tree-sitter couldn't parse the syntax.

  ## Examples

      # if then fi (invalid) - has ERROR nodes
      iex> ErrorClassifier.has_error_nodes?(syntax_error_ast)
      true

      # if true; then (incomplete but valid) - no ERROR nodes
      iex> ErrorClassifier.has_error_nodes?(incomplete_ast)
      false
  """
  @spec has_error_nodes?(term()) :: boolean()
  def has_error_nodes?(%BashParser.AST.Types.ErrorNode{}), do: true

  def has_error_nodes?(node) when is_struct(node) do
    # Check all fields recursively (includes :children and other fields)
    node
    |> Map.from_struct()
    |> Map.values()
    |> Enum.any?(&has_error_nodes?/1)
  end

  def has_error_nodes?(list) when is_list(list) do
    Enum.any?(list, &has_error_nodes?/1)
  end

  def has_error_nodes?(_), do: false

  @doc """
  Count structure nodes in typed AST (control flow that needs closing).

  Structure nodes are control flow constructs that require closing keywords:
  - IfStatement (needs fi)
  - ForStatement (needs done)
  - WhileStatement (needs done)
  - UntilStatement (needs done)
  - CaseStatement (needs esac)
  - FunctionDefinition (needs closing brace)
  """
  @spec count_structure_nodes(term()) :: non_neg_integer()
  def count_structure_nodes(%BashParser.AST.Types.IfStatement{} = node), do: 1 + count_children_structures(node)
  def count_structure_nodes(%BashParser.AST.Types.ForStatement{} = node), do: 1 + count_children_structures(node)
  def count_structure_nodes(%BashParser.AST.Types.WhileStatement{} = node), do: 1 + count_children_structures(node)
  def count_structure_nodes(%BashParser.AST.Types.CaseStatement{} = node), do: 1 + count_children_structures(node)
  def count_structure_nodes(%BashParser.AST.Types.FunctionDefinition{} = node), do: 1 + count_children_structures(node)

  def count_structure_nodes(node) when is_struct(node), do: count_children_structures(node)
  def count_structure_nodes(_), do: 0

  defp count_children_structures(node) do
    if Map.has_key?(node, :children) && is_list(node.children) do
      Enum.reduce(node.children, 0, fn child, acc ->
        acc + count_structure_nodes(child)
      end)
    else
      0
    end
  end

  @doc """
  Count ERROR nodes in typed AST.

  Returns the total number of ERROR nodes found in the AST tree.
  """
  @spec count_error_nodes(term()) :: non_neg_integer()
  def count_error_nodes(%BashParser.AST.Types.ErrorNode{}), do: 1

  def count_error_nodes(node) when is_struct(node) do
    node
    |> Map.from_struct()
    |> Map.values()
    |> Enum.map(&count_error_nodes/1)
    |> Enum.sum()
  end

  def count_error_nodes(list) when is_list(list) do
    list
    |> Enum.map(&count_error_nodes/1)
    |> Enum.sum()
  end

  def count_error_nodes(_), do: 0

  @doc """
  Identify which structure is incomplete and what keyword is expected.

  Analyzes the AST to determine what closing keyword is needed.
  A structure is incomplete if it's missing its closing keyword.

  Returns a map with `:type` and `:expecting` keys, or `nil` if
  no incomplete structure is found.

  ## Examples

      iex> ErrorClassifier.identify_incomplete_structure(if_ast_without_fi)
      %{type: :if_statement, expecting: "fi"}

      iex> ErrorClassifier.identify_incomplete_structure(complete_if_ast)
      nil
  """
  @spec identify_incomplete_structure(term()) :: map() | nil
  def identify_incomplete_structure(%BashParser.AST.Types.IfStatement{} = node) do
    if is_if_incomplete?(node) do
      %{type: :if_statement, expecting: "fi"}
    else
      check_children_for_incomplete(node)
    end
  end

  def identify_incomplete_structure(%BashParser.AST.Types.ForStatement{} = node) do
    if is_for_incomplete?(node) do
      %{type: :for_statement, expecting: "done"}
    else
      check_children_for_incomplete(node)
    end
  end

  def identify_incomplete_structure(%BashParser.AST.Types.WhileStatement{}), do: %{type: :while_statement, expecting: "done"}
  def identify_incomplete_structure(%BashParser.AST.Types.CaseStatement{}), do: %{type: :case_statement, expecting: "esac"}
  def identify_incomplete_structure(%BashParser.AST.Types.FunctionDefinition{}), do: %{type: :function_definition, expecting: "}"}

  def identify_incomplete_structure(%BashParser.AST.Types.Program{} = node), do: check_children_for_incomplete(node)
  def identify_incomplete_structure(node) when is_struct(node), do: check_children_for_incomplete(node)
  def identify_incomplete_structure(_), do: nil

  # Check if an IfStatement is incomplete
  defp is_if_incomplete?(node) do
    # An IfStatement from tree-sitter is complete if it parsed successfully
    # The only way it's incomplete is if the source text doesn't end with "fi"
    source_text = node.source_info.text || ""
    not String.ends_with?(String.trim(source_text), "fi")
  end

  # Check if a ForStatement is incomplete
  defp is_for_incomplete?(node) do
    source_text = node.source_info.text || ""
    not String.ends_with?(String.trim(source_text), "done")
  end

  # Helper to check children for incomplete structures
  defp check_children_for_incomplete(node) do
    if Map.has_key?(node, :children) && is_list(node.children) do
      Enum.find_value(node.children, &identify_incomplete_structure/1)
    else
      nil
    end
  end
end
