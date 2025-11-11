defmodule RShell.RuntimeTest do
  use ExUnit.Case, async: false

  alias RShell.{Runtime, PubSub}
  alias BashParser.AST.Types

  setup do
    session_id = "test_#{:rand.uniform(1000000)}"
    {:ok, runtime} = Runtime.start_link(
      session_id: session_id,
      mode: :simulate,
      auto_execute: false  # Manual execution for tests
    )

    PubSub.subscribe(session_id, :all)

    {:ok, runtime: runtime, session_id: session_id}
  end

  test "starts with correct initial context", %{runtime: runtime} do
    context = Runtime.get_context(runtime)

    assert context.mode == :simulate
    assert context.exit_code == 0
    assert context.command_count == 0
    assert context.cwd != nil
    assert is_map(context.env)
  end

  test "executes node and broadcasts events", %{runtime: runtime} do
    node = %Types.Command{
      source_info: %Types.SourceInfo{
        start_line: 0,
        start_column: 0,
        end_line: 0,
        end_column: 10,
        text: "echo hello"
      },
      name: nil,
      argument: [],
      redirect: [],
      children: []
    }

    {:ok, _} = Runtime.execute_node(runtime, node)

    assert_receive {:execution_started, _}, 1000
    assert_receive {:execution_completed, %{exit_code: 0}}, 1000
    assert_receive {:stdout, output}, 1000
    assert output =~ "hello"
  end

  test "tracks context", %{runtime: runtime} do
    context = Runtime.get_context(runtime)

    assert context.cwd != nil
    assert context.command_count == 0

    # Execute a node
    node = %Types.Command{
      source_info: %Types.SourceInfo{
        start_line: 0, start_column: 0, end_line: 0, end_column: 9,
        text: "echo test"
      },
      name: nil, argument: [], redirect: [], children: []
    }
    Runtime.execute_node(runtime, node)

    # Check command count increased
    new_context = Runtime.get_context(runtime)
    assert new_context.command_count == 1
  end

  test "get/set cwd", %{runtime: runtime} do
    old_cwd = Runtime.get_cwd(runtime)
    assert old_cwd != nil

    Runtime.set_cwd(runtime, "/tmp")

    assert_receive {:cwd_changed, %{old: ^old_cwd, new: "/tmp"}}, 1000
    assert Runtime.get_cwd(runtime) == "/tmp"
  end

  test "handles variable assignments", %{runtime: runtime, session_id: _session_id} do
    node = %Types.DeclarationCommand{
      source_info: %Types.SourceInfo{
        start_line: 0, start_column: 0, end_line: 0, end_column: 14,
        text: "export FOO=bar"
      },
      children: []
    }

    Runtime.execute_node(runtime, node)

    assert_receive {:variable_set, %{name: "FOO", value: "bar"}}, 1000

    # Check variable was set
    assert Runtime.get_variable(runtime, "FOO") == "bar"
  end

  test "changes execution mode", %{runtime: runtime} do
    context = Runtime.get_context(runtime)
    assert context.mode == :simulate

    Runtime.set_mode(runtime, :capture)

    new_context = Runtime.get_context(runtime)
    assert new_context.mode == :capture
  end

  test "auto-executes when receiving executable_node event", %{runtime: _runtime, session_id: session_id} do
    # Create runtime with auto_execute: true
    {:ok, auto_runtime} = Runtime.start_link(
      session_id: session_id <> "_auto",
      mode: :simulate,
      auto_execute: true
    )

    PubSub.subscribe(session_id <> "_auto", [:runtime, :output])

    # Simulate parser sending executable node
    node = %Types.Command{
      source_info: %Types.SourceInfo{
        start_line: 0, start_column: 0, end_line: 0, end_column: 13,
        text: "echo autoexec"
      },
      name: nil, argument: [], redirect: [], children: []
    }
    send(auto_runtime, {:executable_node, node, 1})

    # Should receive execution events
    assert_receive {:execution_started, _}, 1000
    assert_receive {:execution_completed, _}, 1000
    assert_receive {:stdout, output}, 1000
    assert output =~ "autoexec"
  end

  test "handles pipeline nodes", %{runtime: runtime} do
    node = %Types.Pipeline{
      source_info: %Types.SourceInfo{
        start_line: 0, start_column: 0, end_line: 0, end_column: 19,
        text: "echo foo | grep foo"
      },
      children: []
    }

    {:ok, _} = Runtime.execute_node(runtime, node)

    assert_receive {:stdout, output}, 1000
    assert output =~ "PIPELINE"
    assert output =~ "grep"
  end

  test "tracks output in context", %{runtime: runtime} do
    context_before = Runtime.get_context(runtime)
    assert length(context_before.output) == 0

    node = %Types.Command{
      source_info: %Types.SourceInfo{
        start_line: 0, start_column: 0, end_line: 0, end_column: 9,
        text: "echo test"
      },
      name: nil, argument: [], redirect: [], children: []
    }
    Runtime.execute_node(runtime, node)

    context_after = Runtime.get_context(runtime)
    assert length(context_after.output) > 0
  end
end
