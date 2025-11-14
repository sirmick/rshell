defmodule RShell.ErrorClassifierTest do
  use ExUnit.Case, async: false

  alias RShell.{ErrorClassifier, IncrementalParser}

  setup do
    {:ok, _} = Application.ensure_all_started(:rshell)
    :ok
  end

  describe "classify/1 with typed AST" do
    test "returns :complete for valid bash command" do
      {:ok, parser} = IncrementalParser.start_link(session_id: "test_#{:rand.uniform(1_000_000)}")
      {:ok, _} = IncrementalParser.append_fragment(parser, "echo hello\n")
      {:ok, typed_ast} = IncrementalParser.get_current_ast(parser)

      assert ErrorClassifier.classify(typed_ast) == :complete
    end

    test "returns :syntax_error for invalid syntax (if then fi)" do
      {:ok, parser} = IncrementalParser.start_link(session_id: "test_#{:rand.uniform(1_000_000)}")
      {:ok, _} = IncrementalParser.append_fragment(parser, "if then fi\n")
      {:ok, typed_ast} = IncrementalParser.get_current_ast(parser)

      assert ErrorClassifier.classify(typed_ast) == :syntax_error
    end

    test "returns :incomplete for if without fi" do
      {:ok, parser} = IncrementalParser.start_link(session_id: "test_#{:rand.uniform(1_000_000)}")
      {:ok, _} = IncrementalParser.append_fragment(parser, "if true; then\n")
      {:ok, typed_ast} = IncrementalParser.get_current_ast(parser)

      assert ErrorClassifier.classify(typed_ast) == :incomplete
    end

    test "returns :incomplete for for loop without done" do
      {:ok, parser} = IncrementalParser.start_link(session_id: "test_#{:rand.uniform(1_000_000)}")
      {:ok, _} = IncrementalParser.append_fragment(parser, "for i in 1 2 3; do\n")
      {:ok, typed_ast} = IncrementalParser.get_current_ast(parser)

      assert ErrorClassifier.classify(typed_ast) == :incomplete
    end

    test "returns :complete for complete for loop" do
      {:ok, parser} = IncrementalParser.start_link(session_id: "test_#{:rand.uniform(1_000_000)}")
      {:ok, _} = IncrementalParser.append_fragment(parser, "for i in 1 2 3; do echo $i; done\n")
      {:ok, typed_ast} = IncrementalParser.get_current_ast(parser)

      assert ErrorClassifier.classify(typed_ast) == :complete
    end

    test "multi-line command building up" do
      {:ok, parser} = IncrementalParser.start_link(session_id: "test_#{:rand.uniform(1_000_000)}")

      # First line - incomplete
      {:ok, _} = IncrementalParser.append_fragment(parser, "if true; then\n")
      {:ok, ast1} = IncrementalParser.get_current_ast(parser)
      assert ErrorClassifier.classify(ast1) == :incomplete

      # Add body - still incomplete
      {:ok, _} = IncrementalParser.append_fragment(parser, "  echo hello\n")
      {:ok, ast2} = IncrementalParser.get_current_ast(parser)
      assert ErrorClassifier.classify(ast2) == :incomplete

      # Complete it
      {:ok, _} = IncrementalParser.append_fragment(parser, "fi\n")
      {:ok, ast3} = IncrementalParser.get_current_ast(parser)
      assert ErrorClassifier.classify(ast3) == :complete
    end

    test "distinguishes unclosed quote (syntax error) from incomplete structure" do
      # Unclosed quote - syntax error
      {:ok, parser1} =
        IncrementalParser.start_link(session_id: "test_#{:rand.uniform(1_000_000)}")

      {:ok, _} = IncrementalParser.append_fragment(parser1, "echo \"unclosed\n")
      {:ok, ast1} = IncrementalParser.get_current_ast(parser1)
      assert ErrorClassifier.classify(ast1) == :syntax_error

      # Incomplete structure - not a syntax error
      {:ok, parser2} =
        IncrementalParser.start_link(session_id: "test_#{:rand.uniform(1_000_000)}")

      {:ok, _} = IncrementalParser.append_fragment(parser2, "if true; then\n")
      {:ok, ast2} = IncrementalParser.get_current_ast(parser2)
      assert ErrorClassifier.classify(ast2) == :incomplete
    end
  end

  describe "has_error_nodes?/1 with typed AST" do
    test "returns false for valid command" do
      {:ok, parser} = IncrementalParser.start_link(session_id: "test_#{:rand.uniform(1_000_000)}")
      {:ok, _} = IncrementalParser.append_fragment(parser, "echo hello\n")
      {:ok, typed_ast} = IncrementalParser.get_current_ast(parser)

      assert ErrorClassifier.has_error_nodes?(typed_ast) == false
    end

    test "returns true for invalid syntax" do
      {:ok, parser} = IncrementalParser.start_link(session_id: "test_#{:rand.uniform(1_000_000)}")
      {:ok, _} = IncrementalParser.append_fragment(parser, "if then fi\n")
      {:ok, typed_ast} = IncrementalParser.get_current_ast(parser)

      assert ErrorClassifier.has_error_nodes?(typed_ast) == true
    end

    test "returns false for incomplete but valid structure" do
      {:ok, parser} = IncrementalParser.start_link(session_id: "test_#{:rand.uniform(1_000_000)}")
      {:ok, _} = IncrementalParser.append_fragment(parser, "if true; then\n")
      {:ok, typed_ast} = IncrementalParser.get_current_ast(parser)

      assert ErrorClassifier.has_error_nodes?(typed_ast) == false
    end
  end

  describe "has_incomplete_structure?/1 with typed AST" do
    test "returns false for complete command" do
      {:ok, parser} = IncrementalParser.start_link(session_id: "test_#{:rand.uniform(1_000_000)}")
      {:ok, _} = IncrementalParser.append_fragment(parser, "echo hello\n")
      {:ok, typed_ast} = IncrementalParser.get_current_ast(parser)

      assert ErrorClassifier.has_incomplete_structure?(typed_ast) == false
    end

    test "returns true for incomplete if statement" do
      {:ok, parser} = IncrementalParser.start_link(session_id: "test_#{:rand.uniform(1_000_000)}")
      {:ok, _} = IncrementalParser.append_fragment(parser, "if true; then\n")
      {:ok, typed_ast} = IncrementalParser.get_current_ast(parser)

      assert ErrorClassifier.has_incomplete_structure?(typed_ast) == true
    end

    test "returns false for complete if statement" do
      {:ok, parser} = IncrementalParser.start_link(session_id: "test_#{:rand.uniform(1_000_000)}")
      {:ok, _} = IncrementalParser.append_fragment(parser, "if true; then echo hi; fi\n")
      {:ok, typed_ast} = IncrementalParser.get_current_ast(parser)

      assert ErrorClassifier.has_incomplete_structure?(typed_ast) == false
    end
  end

  describe "identify_incomplete_structure/1 with typed AST" do
    test "identifies incomplete if statement" do
      {:ok, parser} = IncrementalParser.start_link(session_id: "test_#{:rand.uniform(1_000_000)}")
      {:ok, _} = IncrementalParser.append_fragment(parser, "if true; then\n")
      {:ok, typed_ast} = IncrementalParser.get_current_ast(parser)

      info = ErrorClassifier.identify_incomplete_structure(typed_ast)

      assert info.type == :if_statement
      assert info.expecting == "fi"
    end

    test "identifies incomplete for loop" do
      {:ok, parser} = IncrementalParser.start_link(session_id: "test_#{:rand.uniform(1_000_000)}")
      {:ok, _} = IncrementalParser.append_fragment(parser, "for i in 1 2 3; do\n")
      {:ok, typed_ast} = IncrementalParser.get_current_ast(parser)

      info = ErrorClassifier.identify_incomplete_structure(typed_ast)

      assert info.type == :for_statement
      assert info.expecting == "done"
    end

    test "returns nil for complete command" do
      {:ok, parser} = IncrementalParser.start_link(session_id: "test_#{:rand.uniform(1_000_000)}")
      {:ok, _} = IncrementalParser.append_fragment(parser, "echo hello\n")
      {:ok, typed_ast} = IncrementalParser.get_current_ast(parser)

      assert ErrorClassifier.identify_incomplete_structure(typed_ast) == nil
    end
  end

  describe "count_structure_nodes/1" do
    test "counts if statement" do
      {:ok, parser} = IncrementalParser.start_link(session_id: "test_#{:rand.uniform(1_000_000)}")
      {:ok, _} = IncrementalParser.append_fragment(parser, "if true; then echo hi; fi\n")
      {:ok, typed_ast} = IncrementalParser.get_current_ast(parser)

      assert ErrorClassifier.count_structure_nodes(typed_ast) == 1
    end

    test "counts nested structures" do
      {:ok, parser} = IncrementalParser.start_link(session_id: "test_#{:rand.uniform(1_000_000)}")

      {:ok, _} =
        IncrementalParser.append_fragment(
          parser,
          "if true; then for i in 1; do echo $i; done; fi\n"
        )

      {:ok, typed_ast} = IncrementalParser.get_current_ast(parser)

      # Should count both if and for
      assert ErrorClassifier.count_structure_nodes(typed_ast) == 2
    end

    test "returns 0 for simple command" do
      {:ok, parser} = IncrementalParser.start_link(session_id: "test_#{:rand.uniform(1_000_000)}")
      {:ok, _} = IncrementalParser.append_fragment(parser, "echo hello\n")
      {:ok, typed_ast} = IncrementalParser.get_current_ast(parser)

      assert ErrorClassifier.count_structure_nodes(typed_ast) == 0
    end
  end

  describe "count_error_nodes/1" do
    test "returns 0 for valid command" do
      {:ok, parser} = IncrementalParser.start_link(session_id: "test_#{:rand.uniform(1_000_000)}")
      {:ok, _} = IncrementalParser.append_fragment(parser, "echo hello\n")
      {:ok, typed_ast} = IncrementalParser.get_current_ast(parser)

      assert ErrorClassifier.count_error_nodes(typed_ast) == 0
    end

    test "counts ERROR nodes in syntax error" do
      {:ok, parser} = IncrementalParser.start_link(session_id: "test_#{:rand.uniform(1_000_000)}")
      {:ok, _} = IncrementalParser.append_fragment(parser, "if then fi\n")
      {:ok, typed_ast} = IncrementalParser.get_current_ast(parser)

      # Should have at least one ERROR node
      assert ErrorClassifier.count_error_nodes(typed_ast) > 0
    end

    test "returns 0 for incomplete but valid structure" do
      {:ok, parser} = IncrementalParser.start_link(session_id: "test_#{:rand.uniform(1_000_000)}")
      {:ok, _} = IncrementalParser.append_fragment(parser, "if true; then\n")
      {:ok, typed_ast} = IncrementalParser.get_current_ast(parser)

      assert ErrorClassifier.count_error_nodes(typed_ast) == 0
    end
  end
end
