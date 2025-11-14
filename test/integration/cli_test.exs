defmodule RShell.Integration.CLITest do
  use ExUnit.Case, async: true

  import RShell.TestSupport.CLIHelper

  alias RShell.CLI
  alias RShell.CLI.ExecutionRecord

  describe "execute_string/2 - basic commands" do
    test "executes a simple echo command" do
      state =
        assert_cli_output("echo hello\n",
          stdout_contains: "hello",
          exit_code: 0,
          record_count: 1
        )

      record = List.last(state.history)
      assert is_struct(record, ExecutionRecord)
      assert record.fragment == "echo hello\n"
    end

    test "collects parse and execution metrics" do
      state = assert_cli_success("echo test\n")

      record = List.last(state.history)
      assert record.parse_metrics.duration_us > 0
      assert record.exec_metrics.duration_us > 0
      assert is_integer(record.parse_metrics.memory_delta)
      assert is_integer(record.exec_metrics.memory_delta)
    end

    test "stores full AST and incremental AST" do
      state = assert_cli_success("echo test\n")

      record = List.last(state.history)
      assert record.full_ast != nil
      assert record.incremental_ast != nil
    end

    test "stores execution result" do
      state = assert_cli_success("echo hello\n")

      record = List.last(state.history)
      assert record.execution_result != nil
      assert record.execution_result.status == :success
    end

    test "stores timestamp" do
      state = assert_cli_success("echo test\n")

      record = List.last(state.history)
      assert %DateTime{} = record.timestamp
    end

    test "stores runtime context" do
      state = assert_cli_success("X=hello\n")

      record = List.last(state.history)
      assert is_map(record.context)
      assert is_map(record.context.env)
      assert record.context.env["X"] == "hello"
    end
  end

  describe "execute_string/2 - if statements" do
    test "variable assignment with if statement (then branch)" do
      script = """
      env X=5
      if test $X = 5; then
        echo "X equals 5!"
      else
        echo "X does not equal 5"
      fi
      """

      # With execute_lines (auto-detected for multi-line): env + if creates 2 records
      assert_cli_output(script,
        stdout_contains: "X equals 5!",
        exit_code: 0,
        record_count: 2
      )
    end

    test "if-else executes else branch when condition false" do
      script = """
      if test 1 = 2; then
        echo "should not print"
      else
        echo "else branch"
      fi
      """

      state =
        assert_cli_output(script,
          stdout_contains: "else branch",
          exit_code: 0
        )

      # Verify "should not print" does NOT appear
      outputs = Enum.flat_map(state.history, fn r -> r.stdout end)
      refute Enum.any?(outputs, &(&1 =~ "should not print"))
    end
  end

  describe "execute_lines/2 - InputBuffer integration" do
    test "accumulates if statement until complete" do
      script = """
      X=5
      if test $X = 5; then
        echo "X equals 5!"
      else
        echo "X does not equal 5"
      fi
      """

      state =
        assert_cli_output(
          script,
          [
            stdout_contains: "X equals 5!",
            exit_code: 0,
            record_count: 2
          ],
          mode: :execute_lines
        )

      # Verify InputBuffer accumulated the if statement
      first_record = List.first(state.history)
      assert first_record.fragment =~ "X=5"

      second_record = List.last(state.history)
      assert second_record.fragment =~ "if test"
      assert second_record.fragment =~ "fi"
    end

    test "accumulates for loop until done" do
      script = """
      for i in 1 2 3; do
        echo "Loop: $i"
      done
      """

      state = assert_cli_success(script, mode: :execute_lines)

      # Should have just 1 record (for loop accumulated)
      assert length(state.history) == 1

      record = List.first(state.history)
      assert record.fragment =~ "for i in"
      assert record.fragment =~ "done"
    end
  end

  describe "execute_string/2 - state accumulation" do
    test "accumulates state across multiple executions" do
      {:ok, state1} = CLI.execute_string("echo first\n")
      {:ok, state2} = CLI.execute_string("echo second\n", state: state1)

      assert length(state2.history) == 2

      record = List.last(state2.history)
      assert record.stdout == ["second\n"]
      assert record.exit_code == 0
    end
  end

  describe "reset/1" do
    test "clears execution history" do
      {:ok, state1} = CLI.execute_string("env X=5\n")
      {:ok, state2} = CLI.execute_string("echo $X\n", state: state1)
      assert length(state2.history) == 2

      {:ok, state3} = CLI.reset(state2)
      assert length(state3.history) == 0
    end

    test "resets runtime environment" do
      {:ok, state1} = CLI.execute_string("X=5\n")

      # Variable should be set in context
      record = List.last(state1.history)
      assert record.context.env["X"] == 5

      {:ok, state2} = CLI.reset(state1)
      {:ok, state3} = CLI.execute_string("echo test\n", state: state2)

      # Variable should be gone after reset
      record2 = List.last(state3.history)
      refute Map.has_key?(record2.context.env, "X")
    end

    test "preserves PIDs and session ID" do
      {:ok, state1} = CLI.execute_string("echo test\n")
      {:ok, state2} = CLI.reset(state1)

      assert state1.parser_pid == state2.parser_pid
      assert state1.runtime_pid == state2.runtime_pid
      assert state1.session_id == state2.session_id
    end
  end

  describe "variable support" do
    test "variable assignment sets environment variable" do
      {:ok, state} = CLI.execute_string("X=5\n")

      record = List.last(state.history)
      assert record.context.env["X"] == 5
      assert record.exit_code == 0
    end

    test "multiple variable assignments accumulate" do
      script = """
      X=5
      Y=10
      """

      state = assert_cli_success(script)

      assert length(state.history) == 2
      last_context = List.last(state.history).context
      assert last_context.env["X"] == 5
      assert last_context.env["Y"] == 10
    end
  end

  describe "timeout protection" do
    test "both execute_string and execute_lines complete without timeout" do
      script = """
      for i in 1 2 3; do
        echo $i
      done
      """

      # Just verify both complete without timeout (5 second default)
      assert_cli_output(script, [no_timeout: true], mode: :execute_string)
      assert_cli_output(script, [no_timeout: true], mode: :execute_lines)
    end
  end
end
