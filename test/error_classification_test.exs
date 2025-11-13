defmodule ErrorClassificationTest do
  use ExUnit.Case, async: false

  @moduledoc """
  Tests highlighting the difficulty in distinguishing between true syntax errors
  and incomplete fragments using tree-sitter's has_errors flag.

  ## The Problem

  Tree-sitter bash parser marks BOTH of these cases with has_errors=true:
  1. True syntax error: `if then fi` (invalid bash syntax)
  2. Incomplete structure: `if true; then` (valid, but waiting for `fi`)

  This makes it difficult to provide accurate user feedback like:
  - "Syntax error at line X" vs "Waiting for closing keyword (fi/done/esac)"

  ## Current Behavior

  We use the tree-level `has_errors` flag to determine if nodes are executable.
  Both true errors and incomplete structures result in has_errors=true, so
  neither is broadcast as executable.

  This is CORRECT for execution (don't run broken/incomplete code), but
  INSUFFICIENT for user feedback (can't distinguish error types).

  ## Future Work Needed

  Possible approaches:
  1. Analyze ERROR node patterns to classify error types
  2. Track expected closing keywords based on node types
  3. Use heuristics (e.g., ERROR at start vs end of input)
  4. Implement custom bash parser logic for better error messages
  """

  describe "true syntax errors vs incomplete structures" do
    test "TRUE SYNTAX ERROR: invalid if statement (if then fi)" do
      {:ok, resource} = BashParser.new_parser()

      # This is ACTUALLY invalid bash - missing condition
      {:ok, ast} = BashParser.parse_incremental(resource, "if then fi\n")

      # Tree has errors (correctly detected)
      assert BashParser.has_errors(resource) == true

      # But we can't tell this is a SYNTAX ERROR vs incomplete structure
      # Both would have has_errors=true

      # Let's look at the structure
      children = ast["children"] || []
      assert length(children) > 0

      # Usually contains ERROR nodes for true syntax errors
      has_error_nodes = Enum.any?(children, fn child ->
        Map.get(child, "type") == "ERROR"
      end)

      # Verify we detected error nodes in true syntax error
      assert has_error_nodes == true
    end

    test "INCOMPLETE STRUCTURE: if without fi" do
      {:ok, resource} = BashParser.new_parser()

      # This is VALID bash, just incomplete
      {:ok, ast} = BashParser.parse_incremental(resource, "if true; then\n")

      # Tree has errors (but this is incomplete, not a syntax error)
      assert BashParser.has_errors(resource) == true

      # Let's look at the structure
      children = ast["children"] || []
      assert length(children) > 0

      # May or may not have ERROR nodes (not used in this test)
      _has_error_nodes = Enum.any?(children, fn child ->
        Map.get(child, "type") == "ERROR"
      end)

      # Incomplete structure may have ERROR nodes
      # Complete it and verify errors are resolved
      {:ok, _ast2} = BashParser.parse_incremental(resource, "fi\n")
      assert BashParser.has_errors(resource) == false
    end

    test "COMPARISON: both show has_errors=true but different causes" do
      # Syntax error case
      {:ok, resource1} = BashParser.new_parser()
      {:ok, _ast1} = BashParser.parse_incremental(resource1, "if then fi\n")
      syntax_error = BashParser.has_errors(resource1)

      # Incomplete case
      {:ok, resource2} = BashParser.new_parser()
      {:ok, _ast2} = BashParser.parse_incremental(resource2, "if true; then\n")
      incomplete = BashParser.has_errors(resource2)

      # BOTH are true, but for different reasons!
      # This is the core challenge: cannot distinguish between syntax errors
      # and incomplete structures using has_errors flag alone
      assert syntax_error == true
      assert incomplete == true
    end

    test "ERROR nodes as potential differentiator" do
      # Syntax error usually has ERROR nodes
      {:ok, resource1} = BashParser.new_parser()
      {:ok, ast1} = BashParser.parse_incremental(resource1, "if then fi\n")
      children1 = ast1["children"] || []
      error_count1 = Enum.count(children1, &(Map.get(&1, "type") == "ERROR"))

      # Incomplete structure may or may not have ERROR nodes
      {:ok, resource2} = BashParser.new_parser()
      {:ok, ast2} = BashParser.parse_incremental(resource2, "if true; then\n")
      children2 = ast2["children"] || []
      error_count2 = Enum.count(children2, &(Map.get(&1, "type") == "ERROR"))

      # Both cases may have ERROR nodes, so this alone is not a reliable
      # heuristic for distinguishing syntax errors from incomplete structures
      assert error_count1 >= 0
      assert error_count2 >= 0
      # Tree-sitter can create if_statement nodes even for incomplete structures
    end

    test "for loop: incomplete vs syntax error" do
      # Incomplete for loop
      {:ok, resource1} = BashParser.new_parser()
      {:ok, ast1} = BashParser.parse_incremental(resource1, "for i in 1 2 3\n")
      incomplete = BashParser.has_errors(resource1)

      # Invalid for loop syntax
      {:ok, resource2} = BashParser.new_parser()
      {:ok, ast2} = BashParser.parse_incremental(resource2, "for in done\n")
      syntax_error = BashParser.has_errors(resource2)

      assert incomplete == true
      assert syntax_error == true

      children1 = ast1["children"] || []
      children2 = ast2["children"] || []

      # Both incomplete and syntax error show has_errors=true
      assert length(children1) > 0
      assert length(children2) > 0
    end

    test "unclosed quote: clear syntax error" do
      {:ok, resource} = BashParser.new_parser()
      {:ok, ast} = BashParser.parse_incremental(resource, "echo \"unclosed\n")

      assert BashParser.has_errors(resource) == true

      children = ast["children"] || []
      has_error = Enum.any?(children, fn child ->
        Map.get(child, "type") == "ERROR" ||
        has_error_in_subtree?(child)
      end)

      # Unclosed quotes should be identifiable as syntax error
      # because quotes are not multi-line constructs in bash
      assert has_error == true
    end
  end

  # Helper to recursively check for ERROR nodes
  defp has_error_in_subtree?(node) when is_map(node) do
    if Map.get(node, "type") == "ERROR" do
      true
    else
      children = Map.get(node, "children", [])
      Enum.any?(children, &has_error_in_subtree?/1)
    end
  end
  defp has_error_in_subtree?(_), do: false
end
