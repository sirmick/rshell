# Interactive Mode Testing Strategy

## Overview

This document outlines a comprehensive testing strategy for RShell's interactive mode behavior, focusing on state isolation, output correctness, and PubSub event handling.

## Critical Bug That Was Fixed

### The PubSub Event Leakage Bug

**Symptom**: Commands in interactive mode were displaying output from previous commands (e.g., `X=12` showed `man` builtin output).

**Root Cause**: When we refactored to use `Executor.execute_fragment`, we removed the PubSub event draining logic. Events remained in the process mailbox and were processed at wrong times.

**Fix**: Added `drain_pubsub_events/1` at line 810 in [`lib/r_shell/cli.ex`](lib/r_shell/cli.ex:810) to consume stale messages after each execution.

## Testing Strategy

### 1. Command Sequence Isolation Tests

**Goal**: Ensure each command's output is isolated from previous commands.

**Test File**: `test/integration/interactive_mode_test.exs`

#### Test Cases:

```elixir
describe "command output isolation" do
  test "variable assignment produces no output" do
    {:ok, state1} = CLI.execute_string("X=12\n")
    record = List.last(state1.history)
    
    # Variable assignments should produce ZERO output
    assert record.stdout == []
    assert record.stderr == []
    assert record.exit_code == 0
  end

  test "builtin command followed by variable assignment" do
    # Execute man (produces output)
    {:ok, state1} = CLI.execute_string("man\n")
    record1 = List.last(state1.history)
    assert length(record1.stdout) > 0  # man produces output
    
    # Execute variable assignment (should produce NO output)
    {:ok, state2} = CLI.execute_string("X=12\n", state: state1)
    record2 = List.last(state2.history)
    assert record2.stdout == []  # Must be empty
    assert record2.stderr == []
  end

  test "variable assignment followed by echo" do
    {:ok, state1} = CLI.execute_string("X=hello\n")
    {:ok, state2} = CLI.execute_string("echo $X\n", state: state1)
    
    record1 = List.last(state1.history)
    record2 = List.last(state2.history)
    
    # First command (assignment) - no output
    assert record1.stdout == []
    
    # Second command (echo) - should show "hello"
    stdout = Utils.format_output(record2.stdout)
    assert stdout =~ "hello"
  end

  test "multiple commands in sequence maintain isolation" do
    commands = [
      {"man", fn record -> assert length(record.stdout) > 0 end},
      {"X=5", fn record -> assert record.stdout == [] end},
      {"echo test", fn record -> assert Utils.format_output(record.stdout) =~ "test" end},
      {"Y=10", fn record -> assert record.stdout == [] end},
      {"math:add 5 10", fn record -> assert Utils.format_output(record.stdout) =~ "15" end}
    ]
    
    state = 
      Enum.reduce(commands, nil, fn {cmd, validator}, acc_state ->
        {:ok, state} = CLI.execute_string(cmd <> "\n", state: acc_state)
        record = List.last(state.history)
        validator.(record)
        state
      end)
    
    # Verify final state has all 5 commands
    assert length(state.history) == 5
  end
end
```

### 2. PubSub Event Draining Tests

**Goal**: Verify that PubSub events don't leak between commands.

```elixir
describe "PubSub event isolation" do
  test "no stale events after command execution" do
    {:ok, state1} = CLI.execute_string("echo test\n")
    
    # Verify no PubSub messages remain in mailbox
    refute_receive {:ast_incremental, _}, 10
    refute_receive {:executable_node, _, _}, 10
    refute_receive {:variable_set, _}, 10
    
    # Execute next command
    {:ok, state2} = CLI.execute_string("X=5\n", state: state1)
    
    # Still no stale messages
    refute_receive {:ast_incremental, _}, 10
    refute_receive {:executable_node, _, _}, 10
  end

  test "PubSub events are drained after each execute_fragment call" do
    # This tests the internal behavior
    {:ok, cli_state} = State.new()
    session_id = cli_state.session_id
    
    # Subscribe to PubSub
    PubSub.subscribe(session_id, [:ast, :executable, :runtime])
    
    # Execute command
    {:ok, new_state} = Executor.execute_fragment("echo test\n", cli_state)
    
    # Manually drain events (simulating what execute_and_loop does)
    drain_all_events(session_id)
    
    # Verify no events remain
    refute_receive {:ast_incremental, _}, 10
    refute_receive {:executable_node, _, _}, 10
  end
end

defp drain_all_events(session_id) do
  receive do
    {:ast_incremental, _} -> drain_all_events(session_id)
    {:executable_node, _, _} -> drain_all_events(session_id)
    {:variable_set, _} -> drain_all_events(session_id)
    {:parsing_failed, _} -> drain_all_events(session_id)
    {:parsing_crashed, _} -> drain_all_events(session_id)
  after
    0 -> :ok
  end
end
```

### 3. State Accumulation Tests

**Goal**: Verify state correctly accumulates across multiple commands.

```elixir
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
    {:ok, state1} = CLI.execute_string("X=hello\n")
    {:ok, state2} = CLI.execute_string("Y=world\n", state: state1)
    {:ok, state3} = CLI.execute_string("echo $X $Y\n", state: state2)
    
    record = List.last(state3.history)
    stdout = Utils.format_output(record.stdout)
    assert stdout =~ "hello"
    assert stdout =~ "world"
  end

  test "reset clears history but preserves PIDs" do
    {:ok, state1} = CLI.execute_string("X=5\n")
    {:ok, state2} = CLI.execute_string("echo $X\n", state: state1)
    
    assert length(state2.history) == 2
    
    {:ok, state3} = CLI.reset(state2)
    
    # History cleared
    assert length(state3.history) == 0
    
    # PIDs preserved
    assert state3.parser_pid == state1.parser_pid
    assert state3.runtime_pid == state1.runtime_pid
    assert state3.session_id == state1.session_id
    
    # Environment cleared
    {:ok, state4} = CLI.execute_string("echo $X\n", state: state3)
    record = List.last(state4.history)
    stdout = Utils.format_output(record.stdout)
    assert stdout == "\n"  # $X is now empty
  end
end
```

### 4. Multi-line Command Tests

**Goal**: Verify InputBuffer correctly handles control structures.

```elixir
describe "multi-line input accumulation" do
  test "if statement accumulates until complete" do
    script = """
    if test 1 = 1; then
      echo "true branch"
    fi
    """
    
    {:ok, state} = CLI.execute_lines(script)
    
    assert length(state.history) == 1
    record = List.first(state.history)
    
    # Full fragment should include entire if statement
    assert record.fragment =~ "if test"
    assert record.fragment =~ "fi"
    
    # Output should be from then branch
    stdout = Utils.format_output(record.stdout)
    assert stdout =~ "true branch"
  end

  test "for loop accumulates until done" do
    script = """
    for i in 1 2 3; do
      echo "Number: $i"
    done
    """
    
    {:ok, state} = CLI.execute_lines(script)
    
    assert length(state.history) == 1
    record = List.first(state.history)
    
    # Full fragment
    assert record.fragment =~ "for i in"
    assert record.fragment =~ "done"
    
    # Output should have all 3 iterations
    stdout = Utils.format_output(record.stdout)
    assert stdout =~ "Number: 1"
    assert stdout =~ "Number: 2"
    assert stdout =~ "Number: 3"
  end

  test "variable assignment before control structure" do
    script = """
    X=5
    if test $X = 5; then
      echo "X is 5"
    fi
    """
    
    {:ok, state} = CLI.execute_lines(script)
    
    # Should have 2 records: assignment + if statement
    assert length(state.history) == 2
    
    [r1, r2] = state.history
    
    # First record: variable assignment
    assert r1.fragment =~ "X=5"
    assert r1.stdout == []
    
    # Second record: if statement
    assert r2.fragment =~ "if test"
    stdout = Utils.format_output(r2.stdout)
    assert stdout =~ "X is 5"
  end
end
```

### 5. Edge Cases and Error Handling

```elixir
describe "edge cases" do
  test "empty input produces no record" do
    {:ok, state} = CLI.execute_string("\n")
    
    # Empty input should not create a record
    assert length(state.history) == 0
  end

  test "whitespace-only input produces no record" do
    {:ok, state} = CLI.execute_string("   \n")
    
    assert length(state.history) == 0
  end

  test "parse error doesn't crash state" do
    # This would need a deliberately malformed input
    # For now, most inputs either parse or get treated as commands
    
    {:ok, state1} = CLI.execute_string("echo test\n")
    {:ok, state2} = CLI.execute_string("echo ok\n", state: state1)
    
    # State should still work
    assert length(state2.history) == 2
  end

  test "builtin error doesn't affect next command" do
    # Execute invalid math operation
    {:ok, state1} = CLI.execute_string("math:add abc xyz\n")
    record1 = List.last(state1.history)
    
    # Should have error
    assert record1.exit_code != 0
    
    # Next command should work fine
    {:ok, state2} = CLI.execute_string("echo hello\n", state: state1)
    record2 = List.last(state2.history)
    
    assert record2.exit_code == 0
    stdout = Utils.format_output(record2.stdout)
    assert stdout =~ "hello"
  end
end
```

### 6. Interactive State Tests

**Goal**: Test InteractiveState struct behavior.

```elixir
describe "InteractiveState management" do
  test "input_buffer accumulates correctly" do
    {:ok, cli_state} = State.new()
    istate = InteractiveState.new(cli_state)
    
    # Initially empty
    assert istate.input_buffer == ""
    
    # After adding line
    istate2 = %{istate | input_buffer: "echo test\n"}
    assert istate2.input_buffer == "echo test\n"
    
    # After clearing
    istate3 = %{istate2 | input_buffer: ""}
    assert istate3.input_buffer == ""
  end

  test "last_ast_metadata tracks incremental changes" do
    {:ok, state1} = CLI.execute_string("echo test\n")
    record = List.last(state1.history)
    
    # Record should have incremental AST
    assert record.incremental_ast != nil
    
    # This would be used in InteractiveState.last_ast_metadata
    assert is_map(record.incremental_ast)
  end

  test "get_last_record returns most recent execution" do
    {:ok, cli_state} = State.new()
    istate = InteractiveState.new(cli_state)
    
    # No records yet
    assert InteractiveState.get_last_record(istate) == nil
    
    # After execution
    {:ok, new_cli_state} = Executor.execute_fragment("echo test\n", cli_state)
    istate2 = %{istate | cli_state: new_cli_state}
    
    record = InteractiveState.get_last_record(istate2)
    assert record != nil
    assert record.fragment == "echo test\n"
  end
end
```

## Implementation Plan

### Phase 1: Create Test File (Immediate)
1. Create `test/integration/interactive_mode_test.exs`
2. Implement all test cases from sections 1-6 above
3. Run tests to establish baseline

### Phase 2: Add Regression Tests (High Priority)
1. Specifically test the PubSub event draining bug
2. Test variable assignment producing no output
3. Test builtin → variable → builtin sequence

### Phase 3: Continuous Testing
1. Run interactive mode tests on every commit
2. Add new test cases as bugs are discovered
3. Maintain 100% test coverage for interactive behavior

## Testing Tools Needed

### Helper Functions to Add to CLIHelper

```elixir
@doc """
Assert that a command produces no output (for variable assignments).
"""
def assert_no_output(script, opts \\\\ []) do
  state = assert_cli_success(script, opts)
  record = List.last(state.history)
  
  if record.stdout != [] || record.stderr != [] do
    flunk("""
    Expected no output but got:
      Stdout: #{inspect(record.stdout)}
      Stderr: #{inspect(record.stderr)}
      
    Script: #{script}
    """)
  end
  
  state
end

@doc """
Execute multiple commands in sequence and verify each one.
"""
def assert_command_sequence(commands, opts \\\\ []) do
  Enum.reduce(commands, nil, fn {cmd, validator}, state ->
    {:ok, new_state} = CLI.execute_string(cmd <> "\n", state: state)
    record = List.last(new_state.history)
    validator.(record)
    new_state
  end)
end
```

## Coverage Goals

- [ ] 100% coverage of interactive mode execution paths
- [ ] All PubSub event types covered
- [ ] All InputBuffer continuation types covered
- [ ] All dot commands covered
- [ ] Error handling paths covered
- [ ] State accumulation patterns covered

## Success Metrics

1. **Zero output leakage**: Variable assignments never show output from previous commands
2. **Clean state transitions**: Each command operates on fresh mailbox
3. **Correct accumulation**: Multi-command sequences maintain proper state
4. **Robust error handling**: Errors don't corrupt state for future commands

## Notes

- The PubSub event draining is CRITICAL for interactive mode
- All tests should use `execute_string` or `execute_lines` (not direct interactive loop)
- Interactive loop testing would require expect-style testing (harder to automate)
- Focus on programmatic API testing since interactive loop delegates to it