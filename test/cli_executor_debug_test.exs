defmodule RShell.CLIExecutorDebugTest do
  use ExUnit.Case, async: true

  alias RShell.CLI.State
  alias RShell.{IncrementalParser, Runtime, PubSub}

  describe "debug event collection" do
    test "manually verify events are broadcast" do
      # Create session
      session_id = "test_#{System.unique_integer([:positive])}"

      # Start parser and runtime
      {:ok, parser} = IncrementalParser.start_link(
        session_id: session_id,
        broadcast: true
      )

      {:ok, runtime} = Runtime.start_link(
        session_id: session_id,
        auto_execute: true,
        env: System.get_env(),
        cwd: File.cwd!()
      )

      # Subscribe to ALL events
      PubSub.subscribe(session_id, :all)

      # Parse a simple command
      {:ok, _ast} = IncrementalParser.append_fragment(parser, "echo hello\n")

      # Collect events with detailed logging
      events = collect_all_events(5000, [])

      IO.puts("\n=== Collected #{length(events)} events ===")
      Enum.each(events, fn {event_name, _data} ->
        IO.puts("  - #{inspect(event_name)}")
      end)

      # Check what we got
      has_ast = Enum.any?(events, fn {name, _} -> name == :ast_incremental end)
      has_executable = Enum.any?(events, fn {name, _} -> name == :executable_node end)
      has_result = Enum.any?(events, fn {name, _} -> name == :execution_result end)

      IO.puts("\nEvent summary:")
      IO.puts("  AST event: #{has_ast}")
      IO.puts("  Executable event: #{has_executable}")
      IO.puts("  Result event: #{has_result}")

      if has_result do
        {_, result} = Enum.find(events, fn {name, _} -> name == :execution_result end)
        IO.puts("\nExecution result:")
        IO.puts("  Status: #{inspect(result.status)}")
        IO.puts("  Stdout: #{inspect(result.stdout)}")
        IO.puts("  Exit code: #{inspect(result.exit_code)}")
      end

      # Assertions
      assert has_ast, "Should receive AST event"
      assert has_executable, "Should receive executable node event"
      assert has_result, "Should receive execution result event"
    end

    test "verify State.new/1 works" do
      {:ok, state} = State.new()

      assert is_struct(state, State)
      assert is_pid(state.parser_pid)
      assert is_pid(state.runtime_pid)
      assert is_binary(state.session_id)
      assert state.history == []
    end

    test "verify parser can parse simple command" do
      session_id = "test_#{System.unique_integer([:positive])}"

      {:ok, parser} = IncrementalParser.start_link(
        session_id: session_id,
        broadcast: false
      )

      {:ok, ast} = IncrementalParser.append_fragment(parser, "echo test\n")

      assert ast != nil
      IO.puts("\nParsed AST: #{inspect(ast.__struct__)}")
    end
  end

  # Helper to collect all events
  defp collect_all_events(timeout, acc) do
    receive do
      {:executable_node, node, count} ->
        # 3-tuple format for executable nodes
        collect_all_events(timeout, [{:executable_node, {node, count}} | acc])
      {event_name, data} when is_atom(event_name) ->
        collect_all_events(timeout, [{event_name, data} | acc])
      other ->
        IO.puts("Unexpected message: #{inspect(other)}")
        collect_all_events(timeout, acc)
    after
      timeout ->
        Enum.reverse(acc)
    end
  end
end
