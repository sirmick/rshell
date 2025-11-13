defmodule ParserRuntimeIntegrationTest do
  use ExUnit.Case, async: false

  alias RShell.{IncrementalParser, Runtime, PubSub}

  setup do
    session_id = "test_#{:rand.uniform(1000000)}"

    {:ok, parser} = IncrementalParser.start_link(
      session_id: session_id,
      broadcast: true
    )
    {:ok, runtime} = Runtime.start_link(
      session_id: session_id,
      auto_execute: true  # Auto-execute for integration
    )

    PubSub.subscribe(session_id, :all)

    {:ok, parser: parser, runtime: runtime, session_id: session_id}
  end

  test "end-to-end: parse and execute simple command", %{parser: parser} do
    # Submit command
    IncrementalParser.append_fragment(parser, "echo hello\n")

    # Should see events in order
    assert_receive {:ast_updated, _}, 1000
    assert_receive {:executable_node, _, _}, 1000
    assert_receive {:execution_started, _}, 1000
    assert_receive {:execution_completed, _}, 1000
    assert_receive {:stdout, output}, 1000
    assert output =~ "hello"
  end

  # DeclarationCommand execution not yet implemented

  test "multiple commands execute in sequence", %{parser: parser, runtime: runtime} do
    # Submit multiple commands
    IncrementalParser.append_fragment(parser, "echo first\n")
    # Clear mailbox
    :timer.sleep(100)
    flush_mailbox()

    IncrementalParser.append_fragment(parser, "echo second\n")
    # Clear mailbox
    :timer.sleep(100)
    flush_mailbox()

    IncrementalParser.append_fragment(parser, "echo third\n")

    # Should receive events for third command
    assert_receive {:ast_updated, _}, 1000
    assert_receive {:executable_node, _, _}, 1000
    assert_receive {:execution_started, _}, 1000
    assert_receive {:execution_completed, _}, 1000
    assert_receive {:stdout, output}, 1000
    assert output =~ "third"

    # Check command count
    context = Runtime.get_context(runtime)
    assert context.command_count == 3
  end

  test "incomplete structures don't execute", %{parser: parser} do
    # Submit incomplete if statement
    IncrementalParser.append_fragment(parser, "if true; then\n")

    # Should get AST update but no executable node
    assert_receive {:ast_updated, _}, 1000
    refute_receive {:executable_node, _, _}, 500
    refute_receive {:execution_started, _}, 100
  end

  # IfStatement execution not yet implemented

  # DeclarationCommand execution not yet implemented

  # Mode system removed - this test is no longer applicable

  # Helper to flush mailbox
  defp flush_mailbox do
    receive do
      _ -> flush_mailbox()
    after
      0 -> :ok
    end
  end
end
