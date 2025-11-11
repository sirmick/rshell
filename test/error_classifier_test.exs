defmodule RShell.ErrorClassifierTest do
  use ExUnit.Case, async: false

  alias RShell.ErrorClassifier

  setup do
    {:ok, _} = Application.ensure_all_started(:rshell)
    :ok
  end

  describe "has_error_nodes?/1" do
    test "returns true when node type is ERROR" do
      node = %{"type" => "ERROR", "text" => "bad syntax"}
      assert ErrorClassifier.has_error_nodes?(node) == true
    end

    test "returns false for valid node without children" do
      node = %{"type" => "command", "text" => "echo hello"}
      assert ErrorClassifier.has_error_nodes?(node) == false
    end

    test "returns true when ERROR node is in children" do
      node = %{
        "type" => "program",
        "children" => [
          %{"type" => "command", "text" => "echo hello"},
          %{"type" => "ERROR", "text" => "bad"}
        ]
      }
      assert ErrorClassifier.has_error_nodes?(node) == true
    end

    test "returns true when ERROR node is deeply nested" do
      node = %{
        "type" => "program",
        "children" => [
          %{
            "type" => "if_statement",
            "children" => [
              %{"type" => "ERROR", "text" => "bad"}
            ]
          }
        ]
      }
      assert ErrorClassifier.has_error_nodes?(node) == true
    end

    test "returns false for non-map input" do
      assert ErrorClassifier.has_error_nodes?(nil) == false
      assert ErrorClassifier.has_error_nodes?("string") == false
      assert ErrorClassifier.has_error_nodes?(123) == false
    end
  end

  describe "extract_error_info/1" do
    test "extracts location and text from ERROR node" do
      ast = %{
        "type" => "program",
        "children" => [
          %{
            "type" => "ERROR",
            "text" => "then fi",
            "start_row" => 0,
            "end_row" => 0,
            "start_col" => 3,
            "end_col" => 10
          }
        ]
      }

      info = ErrorClassifier.extract_error_info(ast)

      assert info.start_row == 0
      assert info.end_row == 0
      assert info.start_col == 3
      assert info.end_col == 10
      assert info.text == "then fi"
    end

    test "returns default info when no ERROR node found" do
      ast = %{
        "type" => "program",
        "children" => [
          %{"type" => "command", "text" => "echo hello"}
        ]
      }

      info = ErrorClassifier.extract_error_info(ast)

      assert info.start_row == 0
      assert info.end_row == 0
      assert info.text == "unknown"
    end

    test "finds ERROR node in nested structure" do
      ast = %{
        "type" => "program",
        "children" => [
          %{
            "type" => "if_statement",
            "children" => [
              %{
                "type" => "ERROR",
                "text" => "bad",
                "start_row" => 5
              }
            ]
          }
        ]
      }

      info = ErrorClassifier.extract_error_info(ast)
      assert info.start_row == 5
      assert info.text == "bad"
    end
  end

  describe "identify_incomplete_structure/1" do
    test "identifies incomplete if statement" do
      ast = %{
        "type" => "program",
        "children" => [
          %{"type" => "if_statement", "text" => "if true; then"}
        ]
      }

      info = ErrorClassifier.identify_incomplete_structure(ast)

      assert info.type == "if"
      assert info.expecting == "fi"
    end

    test "identifies incomplete for loop" do
      ast = %{
        "type" => "program",
        "children" => [
          %{"type" => "for_statement", "text" => "for i in 1 2 3"}
        ]
      }

      info = ErrorClassifier.identify_incomplete_structure(ast)

      assert info.type == "for"
      assert info.expecting == "done"
    end

    test "identifies incomplete while loop" do
      ast = %{
        "type" => "program",
        "children" => [
          %{"type" => "while_statement", "text" => "while true"}
        ]
      }

      info = ErrorClassifier.identify_incomplete_structure(ast)

      assert info.type == "while"
      assert info.expecting == "done"
    end

    test "identifies incomplete until loop" do
      ast = %{
        "type" => "program",
        "children" => [
          %{"type" => "until_statement", "text" => "until false"}
        ]
      }

      info = ErrorClassifier.identify_incomplete_structure(ast)

      assert info.type == "until"
      assert info.expecting == "done"
    end

    test "identifies incomplete case statement" do
      ast = %{
        "type" => "program",
        "children" => [
          %{"type" => "case_statement", "text" => "case $x in"}
        ]
      }

      info = ErrorClassifier.identify_incomplete_structure(ast)

      assert info.type == "case"
      assert info.expecting == "esac"
    end

    test "returns unknown when no recognized incomplete structure" do
      ast = %{
        "type" => "program",
        "children" => [
          %{"type" => "command", "text" => "echo hello"}
        ]
      }

      info = ErrorClassifier.identify_incomplete_structure(ast)

      assert info.type == "unknown"
      assert info.expecting == "unknown"
    end

    test "returns first incomplete structure when multiple present" do
      ast = %{
        "type" => "program",
        "children" => [
          %{"type" => "if_statement", "text" => "if true; then"},
          %{"type" => "for_statement", "text" => "for i in 1"}
        ]
      }

      info = ErrorClassifier.identify_incomplete_structure(ast)

      # Should return first one found
      assert info.type == "if"
      assert info.expecting == "fi"
    end
  end

  describe "classify_parse_state/2" do
    test "returns :complete when has_errors=false" do
      {:ok, resource} = BashParser.new_parser()
      {:ok, ast} = BashParser.parse_incremental(resource, "echo hello\n")

      {state, info} = ErrorClassifier.classify_parse_state(ast, resource)

      assert state == :complete
      assert info.has_errors == false
    end

    test "returns :syntax_error when has ERROR nodes" do
      {:ok, resource} = BashParser.new_parser()
      {:ok, ast} = BashParser.parse_incremental(resource, "if then fi\n")

      {state, info} = ErrorClassifier.classify_parse_state(ast, resource)

      assert state == :syntax_error
      assert info.has_error_nodes == true
      assert is_map(info.error_info)
    end

    test "returns :incomplete when no ERROR nodes but has_errors=true" do
      {:ok, resource} = BashParser.new_parser()
      {:ok, ast} = BashParser.parse_incremental(resource, "if true; then\n")

      {state, info} = ErrorClassifier.classify_parse_state(ast, resource)

      assert state == :incomplete
      assert info.has_error_nodes == false
      assert info.incomplete_info.type == "if"
      assert info.incomplete_info.expecting == "fi"
    end

    test "correctly classifies complete for loop" do
      {:ok, resource} = BashParser.new_parser()
      {:ok, ast} = BashParser.parse_incremental(resource, "for i in 1 2 3; do echo $i; done\n")

      {state, _info} = ErrorClassifier.classify_parse_state(ast, resource)

      assert state == :complete
    end

    test "correctly classifies incomplete for loop" do
      {:ok, resource} = BashParser.new_parser()
      # Need semicolon + do to create for_statement node (vs ERROR node)
      {:ok, ast} = BashParser.parse_incremental(resource, "for i in 1 2 3; do\n")

      {state, info} = ErrorClassifier.classify_parse_state(ast, resource)

      assert state == :incomplete
      assert info.incomplete_info.type == "for"
      assert info.incomplete_info.expecting == "done"
    end

    test "correctly classifies syntax error in for loop" do
      {:ok, resource} = BashParser.new_parser()
      # Missing semicolon + do creates ERROR node
      {:ok, ast} = BashParser.parse_incremental(resource, "for i in 1 2 3\n")

      {state, info} = ErrorClassifier.classify_parse_state(ast, resource)

      assert state == :syntax_error
      assert info.has_error_nodes == true
    end

    test "correctly classifies incomplete case statement" do
      {:ok, resource} = BashParser.new_parser()
      # case requires at least one pattern to create case_statement node
      {:ok, ast} = BashParser.parse_incremental(resource, "case $x in\n  *)\n")

      {state, info} = ErrorClassifier.classify_parse_state(ast, resource)

      assert state == :incomplete
      assert info.incomplete_info.type == "case"
      assert info.incomplete_info.expecting == "esac"
    end

    test "classifies multi-line command building up" do
      {:ok, resource} = BashParser.new_parser()

      # First line - incomplete
      {:ok, ast1} = BashParser.parse_incremental(resource, "if true; then\n")
      {state1, info1} = ErrorClassifier.classify_parse_state(ast1, resource)
      assert state1 == :incomplete
      assert info1.incomplete_info.expecting == "fi"

      # Add body - still incomplete
      {:ok, ast2} = BashParser.parse_incremental(resource, "  echo hello\n")
      {state2, info2} = ErrorClassifier.classify_parse_state(ast2, resource)
      assert state2 == :incomplete
      assert info2.incomplete_info.expecting == "fi"

      # Complete it
      {:ok, ast3} = BashParser.parse_incremental(resource, "fi\n")
      {state3, _info3} = ErrorClassifier.classify_parse_state(ast3, resource)
      assert state3 == :complete
    end

    test "distinguishes unclosed quote (syntax error) from incomplete structure" do
      # Unclosed quote - syntax error
      {:ok, resource1} = BashParser.new_parser()
      {:ok, ast1} = BashParser.parse_incremental(resource1, "echo \"unclosed\n")
      {state1, info1} = ErrorClassifier.classify_parse_state(ast1, resource1)
      assert state1 == :syntax_error
      assert info1.has_error_nodes == true

      # Incomplete structure - no syntax error
      {:ok, resource2} = BashParser.new_parser()
      {:ok, ast2} = BashParser.parse_incremental(resource2, "if true; then\n")
      {state2, info2} = ErrorClassifier.classify_parse_state(ast2, resource2)
      assert state2 == :incomplete
      assert info2.has_error_nodes == false
    end
  end
end
