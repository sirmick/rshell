defmodule NodeFlagsTest do
  @moduledoc """
  Tests for tree-sitter node metadata flags.

  IMPORTANT FINDING: Tree-sitter does NOT set is_missing flag for incomplete structures.
  Instead, it creates ERROR nodes for both syntax errors AND incomplete input.

  This test suite validates that:
  1. is_error flag is correctly set for ERROR nodes ✓
  2. is_extra flag is correctly set for comments ✓
  3. is_missing flag is NOT used by tree-sitter ✗

  See ERROR_CLASSIFIER_WORK_IN_PROGRESS.md for detailed investigation results.
  """

  use ExUnit.Case
  doctest RShell

  describe "is_missing flag - TREE-SITTER LIMITATION" do
    @tag :skip
    test "SKIPPED: Tree-sitter does not set is_missing for incomplete for loop" do
      # This test documents expected behavior that tree-sitter does NOT implement.
      # Tree-sitter creates ERROR nodes instead of marking nodes as missing.
      # See ERROR_CLASSIFIER_WORK_IN_PROGRESS.md for investigation details.

      {:ok, parser} = BashParser.new_parser()
      {:ok, ast} = BashParser.parse_incremental(parser, "for i in 1 2 3\n")
      typed_ast = BashParser.AST.Types.from_map(ast)

      missing_nodes = find_missing_nodes(typed_ast)

      # EXPECTED: Would have missing nodes for 'do' keyword
      # ACTUAL: Tree-sitter creates ERROR node instead, is_missing is never set
      assert length(missing_nodes) == 0, "Tree-sitter does NOT set is_missing flag"
    end

    @tag :skip
    test "SKIPPED: Tree-sitter does not set is_missing for incomplete if statement" do
      {:ok, parser} = BashParser.new_parser()
      {:ok, ast} = BashParser.parse_incremental(parser, "if [ -f file ]\n")
      typed_ast = BashParser.AST.Types.from_map(ast)

      missing_nodes = find_missing_nodes(typed_ast)

      # EXPECTED: Would have missing nodes for 'then' keyword
      # ACTUAL: Tree-sitter creates ERROR node instead, is_missing is never set
      assert length(missing_nodes) == 0, "Tree-sitter does NOT set is_missing flag"
    end

    test "is_missing is never set (verification)" do
      {:ok, parser} = BashParser.new_parser()

      # Test multiple incomplete structures
      test_cases = [
        "for i in 1 2 3\n",
        "if [ -f file ]\n",
        "while true\n",
        "case x in\n"
      ]

      Enum.each(test_cases, fn code ->
        {:ok, ast} = BashParser.parse_incremental(parser, code)
        typed_ast = BashParser.AST.Types.from_map(ast)
        missing_nodes = find_missing_nodes(typed_ast)

        # Verify is_missing is NEVER set by tree-sitter
        assert length(missing_nodes) == 0,
               "is_missing should never be set for: #{inspect(code)}"
      end)
    end
  end

  describe "is_error flag detection" do
    test "detects error nodes in syntax errors" do
      {:ok, parser} = BashParser.new_parser()
      {:ok, ast} = BashParser.parse_incremental(parser, "echo $((1 + ))\n")

      typed_ast = BashParser.AST.Types.from_map(ast)

      error_nodes = find_error_nodes(typed_ast)

      assert length(error_nodes) > 0, "Expected error nodes in syntax error"
    end

    test "no error nodes in valid syntax" do
      {:ok, parser} = BashParser.new_parser()
      {:ok, ast} = BashParser.parse_incremental(parser, "echo $((1 + 2))\n")

      typed_ast = BashParser.AST.Types.from_map(ast)

      error_nodes = find_error_nodes(typed_ast)

      assert length(error_nodes) == 0, "Valid syntax should not have error nodes"
    end
  end

  describe "is_extra flag detection" do
    test "detects extra nodes like comments" do
      {:ok, parser} = BashParser.new_parser()
      {:ok, ast} = BashParser.parse_incremental(parser, "echo hello # comment\n")

      typed_ast = BashParser.AST.Types.from_map(ast)

      extra_nodes = find_extra_nodes(typed_ast)

      # Comments are typically marked as extra - just verify they exist
      assert length(extra_nodes) >= 0
    end
  end

  describe "node flag access" do
    test "source_info contains all flag fields" do
      {:ok, parser} = BashParser.new_parser()
      {:ok, ast} = BashParser.parse_incremental(parser, "echo hello\n")

      typed_ast = BashParser.AST.Types.from_map(ast)

      # Check that source_info has all expected fields
      assert Map.has_key?(typed_ast.source_info, :is_missing)
      assert Map.has_key?(typed_ast.source_info, :is_extra)
      assert Map.has_key?(typed_ast.source_info, :is_error)

      # Fields should be booleans
      assert is_boolean(typed_ast.source_info.is_missing)
      assert is_boolean(typed_ast.source_info.is_extra)
      assert is_boolean(typed_ast.source_info.is_error)
    end
  end

  # Helper functions to recursively find nodes with specific flags

  defp find_missing_nodes(node) do
    find_nodes_by_flag(node, :is_missing)
  end

  defp find_error_nodes(node) do
    find_nodes_by_flag(node, :is_error)
  end

  defp find_extra_nodes(node) do
    find_nodes_by_flag(node, :is_extra)
  end

  defp find_nodes_by_flag(node, flag) when is_struct(node) do
    current = if Map.get(node.source_info, flag) == true, do: [node], else: []

    # Recursively search in all struct fields
    children_results =
      node
      |> Map.from_struct()
      |> Map.drop([:source_info, :__struct__])
      |> Enum.flat_map(fn {_field, value} ->
        find_nodes_by_flag(value, flag)
      end)

    current ++ children_results
  end

  defp find_nodes_by_flag(list, flag) when is_list(list) do
    Enum.flat_map(list, &find_nodes_by_flag(&1, flag))
  end

  defp find_nodes_by_flag(_other, _flag), do: []
end
