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
      mode: :simulate,
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

  test "context is updated after variable assignment", %{parser: parser, runtime: runtime} do
    # Set variable
    IncrementalParser.append_fragment(parser, "export FOO=bar\n")

    # Wait for execution
    assert_receive {:execution_completed, _}, 1000

    # Should receive variable_set event
    assert_receive {:variable_set, %{name: "FOO", value: "bar"}}, 1000

    # Check context
    assert Runtime.get_variable(runtime, "FOO") == "bar"
  end

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

  test "completed structures execute", %{parser: parser} do
    # Build complete if statement
    IncrementalParser.append_fragment(parser, "if true; then\n")
    # Clear events
    flush_mailbox()

    IncrementalParser.append_fragment(parser, "echo in-if\n")
    # Clear events
    flush_mailbox()

    IncrementalParser.append_fragment(parser, "fi\n")

    # Should now execute the complete if statement
    assert_receive {:ast_updated, _}, 1000
    assert_receive {:executable_node, _, _}, 1000
    assert_receive {:execution_started, _}, 1000
    assert_receive {:execution_completed, _}, 1000
  end

  test "parser reset clears accumulated input but runtime context persists", %{parser: parser, runtime: runtime} do
    # Set a variable
    IncrementalParser.append_fragment(parser, "export TEST=value\n")
    assert_receive {:variable_set, %{name: "TEST"}}, 1000

    # Reset parser
    IncrementalParser.reset(parser)

    # Variable should still be in runtime context
    assert Runtime.get_variable(runtime, "TEST") == "value"

    # Buffer should be empty
    assert IncrementalParser.get_buffer_size(parser) == 0
  end

  test "runtime can change modes", %{parser: parser, runtime: runtime} do
    # Start in simulate mode
    context = Runtime.get_context(runtime)
    assert context.mode == :simulate

    # Change to capture mode
    Runtime.set_mode(runtime, :capture)

    # Execute command - echo is a builtin, so it actually runs in all modes
    IncrementalParser.append_fragment(parser, "echo capture-test\n")

    assert_receive {:execution_completed, _}, 1000
    assert_receive {:stdout, output}, 1000
    # Since echo is now a builtin, it executes the same way in all modes
    assert output =~ "capture-test"
  end

  # Helper to flush mailbox
  defp flush_mailbox do
    receive do
      _ -> flush_mailbox()
    after
      0 -> :ok
    end
  end
end
