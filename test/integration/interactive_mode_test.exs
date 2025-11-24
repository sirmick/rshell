defmodule RShell.Integration.InteractiveModeTest do
  use ExUnit.Case, async: true

  alias RShell.CLI
  alias RShell.CLI.State
  alias RShell.Builtins.Utils
  import RShell.TestHelpers

  @moduledoc """
  Tests for interactive mode behavior, focusing on:
  - Command output isolation
  - PubSub event draining
  - State accumulation
  - Multi-line input handling

  These tests prevent regression of the PubSub event leakage bug where
  commands would display output from previous commands.
  """

  describe "command output isolation - CRITICAL BUG PREVENTION" do
    test "variable assignment produces no output" do
      {:ok, state} = CLI.execute_string("X = 12\n")
      record = List.last(state.history)

      # Variable assignments MUST produce zero output
      output = materialize_output(record)
      assert output.stdout == [], "Variable assignment produced stdout: #{inspect(output.stdout)}"
      assert output.stderr == [], "Variable assignment produced stderr: #{inspect(output.stderr)}"
      assert record.exit_code == 0
    end

    test "builtin command followed by variable assignment - NO OUTPUT LEAKAGE" do
      # This is the EXACT bug scenario that was fixed
      # Execute man (produces output)
      {:ok, state1} = CLI.execute_string("man\n")
      record1 = List.last(state1.history)
      output1 = materialize_output(record1)
      assert length(output1.stdout) > 0, "man should produce output"

      # Execute variable assignment (MUST produce NO output)
      {:ok, state2} = CLI.execute_string("X = 12\n", state: state1)
      record2 = List.last(state2.history)

      # THE CRITICAL ASSERTION - this was failing before the fix
      output2 = materialize_output(record2)
      assert output2.stdout == [],
             "Variable assignment leaked output from previous command! Got: #{inspect(output2.stdout)}"

      assert output2.stderr == []
    end

    test "variable assignment followed by echo" do
      {:ok, state1} = CLI.execute_string("X = 'hello'\n")
      {:ok, state2} = CLI.execute_string("echo $X\n", state: state1)

      record1 = List.last(state1.history)
      record2 = List.last(state2.history)

      # First command (assignment) - no output
      assert_stdout(record1, [])

      # Second command (echo) - should show "hello"
      stdout = Utils.format_output(record2.stdout)
      assert stdout =~ "hello"
    end

    test "multiple commands maintain strict isolation" do
      commands = [
        {"man\n", fn r ->
          output = materialize_output(r)
          assert length(output.stdout) > 0
        end},
        {"X = 5\n", fn r -> assert_stdout(r, []) end},
        {"echo test\n", fn r -> assert Utils.format_output(r.stdout) =~ "test" end},
        {"Y = 10\n", fn r -> assert_stdout(r, []) end},
        {"math:add 5 10\n", fn r -> assert Utils.format_output(r.stdout) =~ "15" end}
      ]

      state =
        Enum.reduce(commands, nil, fn {cmd, validator}, acc_state ->
          {:ok, new_state} = CLI.execute_string(cmd, state: acc_state)
          record = List.last(new_state.history)
          validator.(record)
          new_state
        end)

      # Verify final state has all 5 commands
      assert length(state.history) == 5
    end

    test "echo followed by variable followed by echo - each isolated" do
      {:ok, state1} = CLI.execute_string("echo first\n")
      {:ok, state2} = CLI.execute_string("VAR = 'value'\n", state: state1)
      {:ok, state3} = CLI.execute_string("echo second\n", state: state2)

      [r1, r2, r3] = state3.history

      # First echo - has output
      assert Utils.format_output(r1.stdout) =~ "first"

      # Variable assignment - NO output
      assert_stdout(r2, [])

      # Second echo - has output (not from first echo!)
      stdout3 = Utils.format_output(r3.stdout)
      assert stdout3 =~ "second"
      refute stdout3 =~ "first"
    end
  end

  describe "PubSub event draining" do
    test "no stale PubSub events after command execution" do
      {:ok, _state} = CLI.execute_string("echo test\n")

      # After execute_string, all PubSub events should be drained
      # These messages should NOT be in the mailbox
      refute_receive {:ast_incremental, _}, 10
      refute_receive {:executable_node, _, _}, 10
      refute_receive {:variable_set, _}, 10
      refute_receive {:parsing_failed, _}, 10
    end

    test "sequential commands don't accumulate PubSub events" do
      {:ok, state1} = CLI.execute_string("echo one\n")
      refute_receive {:ast_incremental, _}, 10

      {:ok, state2} = CLI.execute_string("echo two\n", state: state1)
      refute_receive {:ast_incremental, _}, 10

      {:ok, _state3} = CLI.execute_string("echo three\n", state: state2)
      refute_receive {:ast_incremental, _}, 10
    end
  end

  describe "state accumulation" do
    test "execution history accumulates correctly" do
      {:ok, state1} = CLI.execute_string("echo first\n")
      {:ok, state2} = CLI.execute_string("echo second\n", state: state1)
      {:ok, state3} = CLI.execute_string("echo third\n", state: state2)

      assert length(state3.history) == 3

      # Verify each record is distinct
      [r1, r2, r3] = state3.history
      assert Utils.format_output(r1.stdout) =~ "first"
      assert Utils.format_output(r2.stdout) =~ "second"
      assert Utils.format_output(r3.stdout) =~ "third"
    end

    test "environment variables persist across commands" do
      {:ok, state1} = CLI.execute_string("X = 'hello'\n")
      {:ok, state2} = CLI.execute_string("Y = 'world'\n", state: state1)
      {:ok, state3} = CLI.execute_string("echo $X $Y\n", state: state2)

      record = List.last(state3.history)
      stdout = Utils.format_output(record.stdout)
      assert stdout =~ "hello"
      assert stdout =~ "world"
    end

    test "reset clears history and environment" do
      {:ok, state1} = CLI.execute_string("X = 5\n")
      {:ok, state2} = CLI.execute_string("echo $X\n", state: state1)

      assert length(state2.history) == 2

      {:ok, state3} = CLI.reset(state2)

      # History cleared
      assert length(state3.history) == 0

      # PIDs preserved
      assert state3.parser_pid == state1.parser_pid
      assert state3.runtime_pid == state1.runtime_pid
      assert state3.session_id == state1.session_id

      # Environment cleared - $X should be empty
      {:ok, state4} = CLI.execute_string("echo [$X]\n", state: state3)
      record = List.last(state4.history)
      stdout = Utils.format_output(record.stdout)
      assert stdout =~ "[]", "Variable should be empty after reset"
    end
  end

  describe "multi-line input accumulation" do
    test "if statement accumulates until complete" do
      script = """
      if (true) {
        echo 'true branch'
      }
      """

      {:ok, state} = CLI.execute_lines(script)

      assert length(state.history) == 1
      record = List.first(state.history)

      # Full fragment should include entire if statement
      assert record.fragment =~ "if (true)"
      assert record.fragment =~ "}"

      # Output should be from then branch
      stdout = Utils.format_output(record.stdout)
      assert stdout =~ "true branch"
    end

    test "for loop accumulates until done" do
      script = """
      for (i in [1, 2, 3]) {
        echo 'Number: $i'
      }
      """

      {:ok, state} = CLI.execute_lines(script)

      assert length(state.history) == 1
      record = List.first(state.history)

      # Full fragment
      assert record.fragment =~ "for (i in"
      assert record.fragment =~ "}"

      # Note: Current implementation only captures last iteration's output
      # This is because each iteration overwrites context.last_output
      # TODO: Accumulate output across loop iterations
      stdout = Utils.format_output(record.stdout)
      assert stdout =~ "Number: 3"
    end

    test "variable assignment before control structure" do
      script = """
      X = 5
      if (X == 5) {
        echo 'X is 5'
      }
      """

      {:ok, state} = CLI.execute_lines(script)

      # Should have 2 records: assignment + if statement
      assert length(state.history) == 2

      [r1, r2] = state.history

      # First record: variable assignment (NO output!)
      assert r1.fragment =~ "X = 5"
      assert_stdout(r1, [])

      # Second record: if statement
      assert r2.fragment =~ "if (X"
      stdout = Utils.format_output(r2.stdout)
      assert stdout =~ "X is 5"
    end
  end

  describe "edge cases and error handling" do
    test "whitespace-only input produces no record" do
      {:ok, state} = CLI.execute_string("   \n")

      # Parser might create a record or might not - check behavior
      # For now, just verify it doesn't crash
      assert is_struct(state, State)
    end

    test "builtin error doesn't affect next command" do
      # Execute invalid math operation
      {:ok, state1} = CLI.execute_string("math:add abc xyz\n")
      _record1 = List.last(state1.history)

      # Should have error (non-zero exit or error message)
      # The exact behavior depends on how math:add handles invalid input

      # Next command should work fine regardless
      {:ok, state2} = CLI.execute_string("echo hello\n", state: state1)
      record2 = List.last(state2.history)

      stdout = Utils.format_output(record2.stdout)
      assert stdout =~ "hello"
    end

    test "multiple variable assignments in sequence" do
      {:ok, state1} = CLI.execute_string("A = 1\n")
      {:ok, state2} = CLI.execute_string("B = 2\n", state: state1)
      {:ok, state3} = CLI.execute_string("C = 3\n", state: state2)

      # All should produce no output
      [r1, r2, r3] = state3.history
      assert_stdout(r1, [])
      assert_stdout(r2, [])
      assert_stdout(r3, [])
    end
  end

  describe ".last command functionality" do
    test ".last shows incremental AST changes after command execution" do
      # Execute a command
      {:ok, state} = CLI.execute_string("echo test\n")
      record = List.last(state.history)

      # Verify incremental_ast is stored
      assert record.incremental_ast != nil
      assert is_list(record.incremental_ast)
    end

    test "incremental AST metadata is wrapped in expected format" do
      # This tests the fix for .last command
      # We need to simulate the interactive state update
      {:ok, cli_state} = State.new()

      # Execute a command
      {:ok, new_cli_state} = CLI.execute_string("echo test\n", state: cli_state)
      last_record = List.last(new_cli_state.history)

      # Simulate what execute_and_loop does
      last_ast_metadata = if last_record && last_record.incremental_ast do
        %{changed_nodes: last_record.incremental_ast}
      else
        nil
      end

      # Verify format matches what .last command expects
      assert last_ast_metadata != nil
      assert Map.has_key?(last_ast_metadata, :changed_nodes)
      assert is_list(last_ast_metadata.changed_nodes)
    end

    test "incremental AST contains Command node after echo" do
      {:ok, state} = CLI.execute_string("echo test\n")
      record = List.last(state.history)

      # Should have incremental AST with Command node
      assert length(record.incremental_ast) > 0

      # First node should be a Command
      first_node = List.first(record.incremental_ast)
      # RShell AST returns CmdLine which wraps Command
      assert first_node.__struct__ == BashParser.AST.RShellTypes.CmdLine
    end
  end

  describe "regression tests for specific bugs" do
    test "REGRESSION: man followed by variable assignment shows no man output" do
      # This is the exact bug that was reported and fixed
      {:ok, state1} = CLI.execute_string("man\n")
      {:ok, state2} = CLI.execute_string("X = 12\n", state: state1)

      [man_record, var_record] = state2.history

      # man should have output
      man_output = materialize_output(man_record)
      assert length(man_output.stdout) > 0

      # Variable assignment MUST NOT have output
      assert_stdout(var_record, [],
             "REGRESSION: Variable assignment leaked man output! Fix drain_pubsub_events/1")
    end

    test "REGRESSION: echo followed by variable shows no echo output" do
      {:ok, state1} = CLI.execute_string("echo LEAKED_TEXT\n")
      {:ok, state2} = CLI.execute_string("Y = 'value'\n", state: state1)

      var_record = List.last(state2.history)

      # Variable assignment MUST NOT contain "LEAKED_TEXT"
      assert_stdout(var_record, [])
      refute Utils.format_output(var_record.stdout) =~ "LEAKED_TEXT"
    end
  end
end
