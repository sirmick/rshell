defmodule RShell.CLIExecuteStringTest do
  use ExUnit.Case, async: true

  alias RShell.CLI
  alias RShell.CLI.{State, ExecutionRecord}

  describe "execute_string/2" do
    test "executes a simple echo command" do
      {:ok, state} = CLI.execute_string("echo hello\n")

      assert is_struct(state, State)
      assert length(state.history) == 1

      record = List.last(state.history)
      assert is_struct(record, ExecutionRecord)
      assert record.fragment == "echo hello\n"
      assert record.exit_code == 0
      assert record.stdout == ["hello\n"]
      assert record.stderr == []
    end

    test "collects parse and execution metrics" do
      {:ok, state} = CLI.execute_string("echo test\n")

      record = List.last(state.history)
      assert record.parse_metrics.duration_us > 0
      assert record.exec_metrics.duration_us > 0
      assert is_integer(record.parse_metrics.memory_delta)
      assert is_integer(record.exec_metrics.memory_delta)
    end

    test "accumulates state across multiple executions" do
      {:ok, state1} = CLI.execute_string("X=5\n")
      {:ok, state2} = CLI.execute_string("echo $X\n", state: state1)

      assert length(state2.history) == 2

      record = List.last(state2.history)
      assert record.stdout == ["5\n"]
      assert record.exit_code == 0
    end

    test "stores full AST and incremental AST" do
      {:ok, state} = CLI.execute_string("echo test\n")

      record = List.last(state.history)
      assert record.full_ast != nil
      assert record.incremental_ast != nil
    end

    test "stores execution result" do
      {:ok, state} = CLI.execute_string("echo hello\n")

      record = List.last(state.history)
      assert record.execution_result != nil
      assert record.execution_result.status == :success
    end

    test "stores timestamp" do
      {:ok, state} = CLI.execute_string("echo test\n")

      record = List.last(state.history)
      assert %DateTime{} = record.timestamp
    end

    test "stores runtime context" do
      {:ok, state} = CLI.execute_string("X=hello\n")

      record = List.last(state.history)
      assert is_map(record.context)
      assert is_map(record.context.env)
      assert record.context.env["X"] == "hello"
    end
  end

  describe "reset/1" do
    test "clears execution history" do
      {:ok, state1} = CLI.execute_string("X=5\n")
      {:ok, state2} = CLI.execute_string("echo $X\n", state: state1)
      assert length(state2.history) == 2

      {:ok, state3} = CLI.reset(state2)
      assert length(state3.history) == 0
    end

    test "resets runtime environment" do
      {:ok, state1} = CLI.execute_string("X=5\n")
      {:ok, state2} = CLI.execute_string("echo $X\n", state: state1)

      # Variable should exist
      record = List.last(state2.history)
      assert record.stdout == ["5\n"]

      {:ok, state3} = CLI.reset(state2)
      {:ok, state4} = CLI.execute_string("echo $X\n", state: state3)

      # Variable should be empty after reset
      record2 = List.last(state4.history)
      assert record2.stdout == ["\n"]
    end

    test "preserves PIDs and session ID" do
      {:ok, state1} = CLI.execute_string("echo test\n")
      {:ok, state2} = CLI.reset(state1)

      assert state1.parser_pid == state2.parser_pid
      assert state1.runtime_pid == state2.runtime_pid
      assert state1.session_id == state2.session_id
    end
  end
end
