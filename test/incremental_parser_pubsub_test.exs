defmodule RShell.IncrementalParserPubSubTest do
  use ExUnit.Case, async: false

  alias RShell.{IncrementalParser, PubSub}
  import TestHelperTypedAST

  setup do
    # Ensure application is started
    {:ok, _} = Application.ensure_all_started(:rshell)

    session_id = "parser_test_#{:erlang.unique_integer([:positive])}"

    # Subscribe to all topics for this session
    PubSub.subscribe(session_id, :all)

    # Start parser with session_id
    {:ok, parser} = IncrementalParser.start_link(
      session_id: session_id,
      broadcast: true
    )

    on_exit(fn ->
      PubSub.unsubscribe(session_id, [:ast, :executable, :runtime, :output, :context])
    end)

    {:ok, session_id: session_id, parser: parser}
  end

  describe "AST broadcasting" do
    test "broadcasts AST update after each fragment", %{parser: parser} do
      {:ok, ast} = IncrementalParser.append_fragment(parser, "echo hello\n")

      # Should receive AST update
      assert_receive {:ast_updated, received_ast}, 200
      assert get_type(received_ast) == "program"
      assert received_ast == ast
    end

    test "broadcasts multiple AST updates for multiple fragments", %{parser: parser} do
      {:ok, ast1} = IncrementalParser.append_fragment(parser, "echo hello\n")
      assert_receive {:ast_updated, ^ast1}, 200

      {:ok, ast2} = IncrementalParser.append_fragment(parser, "echo world\n")
      assert_receive {:ast_updated, ^ast2}, 200

      # AST should accumulate both commands
      assert length(get_children(ast2)) == 2
    end

    test "does not broadcast when broadcast is disabled" do
      session_id = "no_broadcast_session"
      PubSub.subscribe(session_id, [:ast])

      {:ok, parser} = IncrementalParser.start_link(
        session_id: session_id,
        broadcast: false
      )

      {:ok, _ast} = IncrementalParser.append_fragment(parser, "echo test\n")

      # Should not receive any broadcasts
      refute_receive {:ast_updated, _}, 200

      PubSub.unsubscribe(session_id, [:ast])
    end

    test "does not broadcast when session_id is nil" do
      {:ok, parser} = IncrementalParser.start_link(
        session_id: nil,
        broadcast: true
      )

      {:ok, _ast} = IncrementalParser.append_fragment(parser, "echo test\n")

      # Should not receive any broadcasts (no session topic)
      refute_receive {:ast_updated, _}, 200
    end
  end

  describe "executable node detection and broadcasting" do
    test "broadcasts executable command", %{parser: parser} do
      {:ok, _ast} = IncrementalParser.append_fragment(parser, "echo hello\n")

      # Should receive AST update first
      assert_receive {:ast_updated, _}, 200

      # Then executable node
      assert_receive {:executable_node, node, 1}, 200
      assert get_type(node) == "command"
      assert get_text(node) =~ "echo hello"
    end

    test "broadcasts multiple executable commands with incremental counts", %{parser: parser} do
      {:ok, _} = IncrementalParser.append_fragment(parser, "echo one\n")
      assert_receive {:ast_updated, _}, 200
      assert_receive {:executable_node, node1, 1}, 200
      assert get_text(node1) =~ "echo one"

      {:ok, _} = IncrementalParser.append_fragment(parser, "echo two\n")
      assert_receive {:ast_updated, _}, 200
      assert_receive {:executable_node, node2, 2}, 200
      assert get_text(node2) =~ "echo two"

      {:ok, _} = IncrementalParser.append_fragment(parser, "echo three\n")
      assert_receive {:ast_updated, _}, 200
      assert_receive {:executable_node, node3, 3}, 200
      assert get_text(node3) =~ "echo three"
    end

    test "broadcasts pipeline as executable", %{parser: parser} do
      {:ok, _} = IncrementalParser.append_fragment(parser, "ls -la | grep test\n")

      assert_receive {:ast_updated, _}, 200
      assert_receive {:executable_node, node, 1}, 200
      assert get_type(node) == "pipeline"
    end

    test "broadcasts list (commands with && or ||) as executable", %{parser: parser} do
      {:ok, _} = IncrementalParser.append_fragment(parser, "echo first && echo second\n")

      assert_receive {:ast_updated, _}, 200
      assert_receive {:executable_node, node, 1}, 200
      assert get_type(node) == "list"
    end

    test "broadcasts subshell as executable", %{parser: parser} do
      {:ok, _} = IncrementalParser.append_fragment(parser, "(echo nested)\n")

      assert_receive {:ast_updated, _}, 200
      assert_receive {:executable_node, node, 1}, 200
      assert get_type(node) == "subshell"
    end

    test "broadcasts variable declaration as executable", %{parser: parser} do
      {:ok, _} = IncrementalParser.append_fragment(parser, "export FOO=bar\n")

      assert_receive {:ast_updated, _}, 200
      assert_receive {:executable_node, node, 1}, 200
      assert get_type(node) == "declaration_command"
    end

    test "broadcasts function definition as executable", %{parser: parser} do
      {:ok, _} = IncrementalParser.append_fragment(parser, "function myfunc() { echo hello; }\n")

      assert_receive {:ast_updated, _}, 200
      assert_receive {:executable_node, node, 1}, 200
      assert get_type(node) == "function_definition"
    end
  end

  describe "incomplete command handling" do
    test "does not broadcast incomplete command", %{parser: parser} do
      # Incomplete command (no newline)
      {:ok, _} = IncrementalParser.append_fragment(parser, "echo hello")

      # Should receive AST update but no executable node
      assert_receive {:ast_updated, _}, 200
      refute_receive {:executable_node, _, _}, 200
    end

    test "broadcasts when incomplete command becomes complete", %{parser: parser} do
      # Start with incomplete
      {:ok, _} = IncrementalParser.append_fragment(parser, "echo ")
      assert_receive {:ast_updated, _}, 200
      refute_receive {:executable_node, _, _}, 100

      # Complete it
      {:ok, _} = IncrementalParser.append_fragment(parser, "hello\n")
      assert_receive {:ast_updated, _}, 200
      assert_receive {:executable_node, node, 1}, 200
      assert get_text(node) =~ "echo"
      assert get_text(node) =~ "hello"
    end

    test "does not broadcast command with syntax errors", %{parser: parser} do
      # Invalid syntax (unclosed quote)
      {:ok, _} = IncrementalParser.append_fragment(parser, "echo \"unclosed\n")

      # Should receive AST update but no executable node (has ERROR nodes)
      assert_receive {:ast_updated, ast}, 200

      # Verify there's an ERROR node
      has_error = get_children(ast)
        |> Enum.any?(&has_error_in_children?/1)

      assert has_error, "Expected ERROR node in AST"
      refute_receive {:executable_node, _, _}, 200
    end

    test "broadcasts multi-line command when complete", %{parser: parser} do
      # Start multi-line
      {:ok, _} = IncrementalParser.append_fragment(parser, "if true; then\n")
      assert_receive {:ast_updated, _}, 200
      refute_receive {:executable_node, _, _}, 100

      # Continue
      {:ok, _} = IncrementalParser.append_fragment(parser, "  echo hello\n")
      assert_receive {:ast_updated, _}, 200
      refute_receive {:executable_node, _, _}, 100

      # Complete
      {:ok, _} = IncrementalParser.append_fragment(parser, "fi\n")
      assert_receive {:ast_updated, _}, 200
      assert_receive {:executable_node, node, 1}, 200
      assert get_type(node) == "if_statement"
    end
  end

  describe "reset behavior" do
    test "resets command count after reset", %{parser: parser} do
      {:ok, _} = IncrementalParser.append_fragment(parser, "echo one\n")
      assert_receive {:ast_updated, _}, 200
      assert_receive {:executable_node, _, 1}, 200

      {:ok, _} = IncrementalParser.append_fragment(parser, "echo two\n")
      assert_receive {:ast_updated, _}, 200
      assert_receive {:executable_node, _, 2}, 200

      # Reset
      :ok = IncrementalParser.reset(parser)

      # Next command should be count 1 again
      {:ok, _} = IncrementalParser.append_fragment(parser, "echo three\n")
      assert_receive {:ast_updated, _}, 200
      assert_receive {:executable_node, _, 1}, 200
    end

    test "clears accumulated input after reset", %{parser: parser} do
      {:ok, _} = IncrementalParser.append_fragment(parser, "echo hello\n")
      assert_receive {:ast_updated, _}, 200
      assert_receive {:executable_node, _, 1}, 200

      :ok = IncrementalParser.reset(parser)

      # Check accumulated input is empty
      accumulated = IncrementalParser.get_accumulated_input(parser)
      assert accumulated == ""
    end
  end

  describe "duplicate detection" do
    test "does not broadcast same executable node twice", %{parser: parser} do
      # First fragment
      {:ok, _} = IncrementalParser.append_fragment(parser, "echo hello\n")
      assert_receive {:ast_updated, _}, 200
      assert_receive {:executable_node, _, 1}, 200

      # Add another fragment after the first (should only broadcast new one)
      {:ok, _} = IncrementalParser.append_fragment(parser, "echo world\n")
      assert_receive {:ast_updated, _}, 200
      assert_receive {:executable_node, node, 2}, 200

      # Should only receive one executable node event (the new one)
      assert get_text(node) =~ "echo world"
      refute_receive {:executable_node, _, _}, 100
    end

    test "tracks last executable row correctly", %{parser: parser} do
      # Line 0
      {:ok, _} = IncrementalParser.append_fragment(parser, "echo line0\n")
      assert_receive {:ast_updated, _}, 200
      assert_receive {:executable_node, node1, 1}, 200
      assert get_end_row(node1) == 0

      # Line 1
      {:ok, _} = IncrementalParser.append_fragment(parser, "echo line1\n")
      assert_receive {:ast_updated, _}, 200
      assert_receive {:executable_node, node2, 2}, 200
      assert get_end_row(node2) == 1

      # Should not receive first node again
      refute_receive {:executable_node, _, 1}, 100
    end
  end

  describe "complex command structures" do
    test "broadcasts for loop when complete", %{parser: parser} do
      {:ok, _} = IncrementalParser.append_fragment(parser, "for i in 1 2 3\n")
      assert_receive {:ast_updated, _}, 200
      refute_receive {:executable_node, _, _}, 100

      {:ok, _} = IncrementalParser.append_fragment(parser, "do\n")
      assert_receive {:ast_updated, _}, 200
      refute_receive {:executable_node, _, _}, 100

      {:ok, _} = IncrementalParser.append_fragment(parser, "  echo $i\n")
      assert_receive {:ast_updated, _}, 200
      refute_receive {:executable_node, _, _}, 100

      {:ok, _} = IncrementalParser.append_fragment(parser, "done\n")
      assert_receive {:ast_updated, _}, 200
      assert_receive {:executable_node, node, 1}, 200
      assert get_type(node) == "for_statement"
    end

    test "broadcasts while loop when complete", %{parser: parser} do
      {:ok, _} = IncrementalParser.append_fragment(parser, "while true; do echo loop; done\n")

      assert_receive {:ast_updated, _}, 200
      assert_receive {:executable_node, node, 1}, 200
      assert get_type(node) == "while_statement"
    end

    test "broadcasts case statement when complete", %{parser: parser} do
      fragments = [
        "case $VAR in\n",
        "  pattern1)\n",
        "    echo one\n",
        "    ;;\n",
        "  pattern2)\n",
        "    echo two\n",
        "    ;;\n",
        "esac\n"
      ]

      # Send all fragments except last
      for fragment <- Enum.slice(fragments, 0..-2) do
        {:ok, _} = IncrementalParser.append_fragment(parser, fragment)
        assert_receive {:ast_updated, _}, 200
        refute_receive {:executable_node, _, _}, 100
      end

      # Send last fragment
      {:ok, _} = IncrementalParser.append_fragment(parser, "esac\n")
      assert_receive {:ast_updated, _}, 200
      assert_receive {:executable_node, node, 1}, 200
      assert get_type(node) == "case_statement"
    end
  end

  describe "executable node ordering" do
    test "broadcasts multiple commands in correct order", %{parser: parser} do
      {:ok, _} = IncrementalParser.append_fragment(parser, "echo first\necho second\necho third\n")

      assert_receive {:ast_updated, _}, 200

      # Should receive three executable nodes in order
      assert_receive {:executable_node, node1, 1}, 200
      assert get_text(node1) =~ "echo first"

      assert_receive {:executable_node, node2, 2}, 200
      assert get_text(node2) =~ "echo second"

      assert_receive {:executable_node, node3, 3}, 200
      assert get_text(node3) =~ "echo third"

      # No more executable nodes
      refute_receive {:executable_node, _, _}, 100
    end

    test "broadcasts commands added incrementally in correct order", %{parser: parser} do
      {:ok, _} = IncrementalParser.append_fragment(parser, "echo first\n")
      assert_receive {:ast_updated, _}, 200
      assert_receive {:executable_node, node1, 1}, 200
      assert get_start_row(node1) == 0

      {:ok, _} = IncrementalParser.append_fragment(parser, "echo second\n")
      assert_receive {:ast_updated, _}, 200
      assert_receive {:executable_node, node2, 2}, 200
      assert get_start_row(node2) == 1

      {:ok, _} = IncrementalParser.append_fragment(parser, "echo third\n")
      assert_receive {:ast_updated, _}, 200
      assert_receive {:executable_node, node3, 3}, 200
      assert get_start_row(node3) == 2
    end
  end

end
