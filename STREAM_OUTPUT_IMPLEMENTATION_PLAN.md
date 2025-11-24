# Stream-Based Output Implementation Plan

**Design Doc**: [`STREAM_OUTPUT_DESIGN.md`](STREAM_OUTPUT_DESIGN.md:1)  
**Created**: 2025-11-23  
**Status**: Ready for Implementation

---

## Overview

This plan breaks down the stream-based output migration into **5 commits**, each independently testable and non-breaking. Each commit builds on the previous one, allowing for incremental progress with safety.

---

## Commit 1: Add Stream Support to Frame & FrameStack

**Goal**: Update Frame and FrameStack to handle streams internally while maintaining backwards compatibility.

### Files Changed
- `lib/r_shell/runtime/frame.ex`
- `lib/r_shell/runtime/frame_stack.ex`
- `test/unit/runtime/frame_stack_test.exs` (new)

### Changes

#### `lib/r_shell/runtime/frame.ex`
```elixir
# Change accumulated type from lists to streams
@type t :: %__MODULE__{
  type: frame_type(),
  output_mode: output_mode(),
  scope: map(),
  accumulated: %{stdout: Enumerable.t(), stderr: Enumerable.t()},  # Changed from list()
  metadata: map(),
  parent_scope: map() | nil
}

# Initialize with empty streams instead of empty lists
defstruct type: :global,
          output_mode: :isolate,
          scope: %{},
          accumulated: %{stdout: Stream.concat([]), stderr: Stream.concat([])},  # Changed
          metadata: %{},
          parent_scope: nil
```

#### `lib/r_shell/runtime/frame_stack.ex`
```elixir
# Update add_output to accept streams or lists (polymorphic for migration)
def add_output(%__MODULE__{frames: [current | rest]} = stack, stdout, stderr) do
  stdout_stream = ensure_stream(stdout)
  stderr_stream = ensure_stream(stderr)
  
  case current.output_mode do
    :isolate ->
      # Replace output (clear previous)
      updated_frame = %{current | accumulated: %{
        stdout: stdout_stream,
        stderr: stderr_stream
      }}
      %{stack | frames: [updated_frame | rest]}
    
    :accumulate ->
      # Concatenate streams lazily
      new_accumulated = %{
        stdout: Stream.concat([current.accumulated.stdout, stdout_stream]),
        stderr: Stream.concat([current.accumulated.stderr, stderr_stream])
      }
      updated_frame = %{current | accumulated: new_accumulated}
      %{stack | frames: [updated_frame | rest]}
    
    _ ->
      # Other modes TBD
      stack
  end
end

# New helper: ensure we have a stream
defp ensure_stream(s) when is_function(s), do: s
defp ensure_stream(list) when is_list(list), do: Stream.concat(list)
defp ensure_stream(str) when is_binary(str) do
  if str == "", do: Stream.concat([]), else: Stream.concat([str])
end
defp ensure_stream(term), do: Stream.concat([term])

# Update clear_output to use empty streams
def clear_output(%__MODULE__{frames: [current | rest]} = stack) do
  updated_frame = %{current | accumulated: %{
    stdout: Stream.concat([]),
    stderr: Stream.concat([])
  }}
  %{stack | frames: [updated_frame | rest]}
end
```

#### `test/unit/runtime/frame_stack_test.exs` (new file)
```elixir
defmodule RShell.Runtime.FrameStackTest do
  use ExUnit.Case, async: true
  alias RShell.Runtime.FrameStack
  
  describe "stream-based output" do
    test "accepts lists and converts to streams" do
      stack = FrameStack.new()
      stack = FrameStack.add_output(stack, ["hello\n"], [])
      
      output = FrameStack.get_output(stack)
      assert Enum.to_list(output.stdout) == ["hello\n"]
      assert Enum.to_list(output.stderr) == []
    end
    
    test "accepts streams directly" do
      stack = FrameStack.new()
      stream = Stream.concat(["world\n"])
      stack = FrameStack.add_output(stack, stream, Stream.concat([]))
      
      output = FrameStack.get_output(stack)
      assert Enum.to_list(output.stdout) == ["world\n"]
    end
    
    test "accumulate mode concatenates streams lazily" do
      stack = FrameStack.new(output_mode: :accumulate)
      
      stack = FrameStack.add_output(stack, ["a"], [])
      stack = FrameStack.add_output(stack, ["b"], [])
      stack = FrameStack.add_output(stack, ["c"], [])
      
      output = FrameStack.get_output(stack)
      assert Enum.to_list(output.stdout) == ["a", "b", "c"]
    end
    
    test "isolate mode replaces streams" do
      stack = FrameStack.new(output_mode: :isolate)
      
      stack = FrameStack.add_output(stack, ["first"], [])
      stack = FrameStack.add_output(stack, ["second"], [])
      
      output = FrameStack.get_output(stack)
      assert Enum.to_list(output.stdout) == ["second"]
    end
  end
end
```

### Testing
```bash
mix test test/unit/runtime/frame_stack_test.exs
```

### Commit Message
```
refactor: Add stream support to Frame and FrameStack

- Change Frame.accumulated type from list() to Enumerable.t()
- Update FrameStack.add_output/3 to accept streams or lists
- Add ensure_stream/1 helper for polymorphic input
- Use Stream.concat/1 for lazy accumulation instead of ++
- Update clear_output/1 to use empty streams
- Add comprehensive unit tests for stream operations

All existing code continues to work (backwards compatible).
Streams are now lazy throughout the frame stack.
```

---

## Commit 2: Add Stream Support to BuiltinResult

**Goal**: Add stream-based API to BuiltinResult without breaking existing code.

### Files Changed
- `lib/r_shell/builtin_result.ex`
- `test/unit/builtin_result_test.exs` (new)

### Changes

#### `lib/r_shell/builtin_result.ex`
```elixir
# Add new stream-based API
@doc """
Get streams directly without materialization.

Returns {context, stdout_stream, stderr_stream} tuple.
Caller is responsible for materialization if needed.

## Examples

    iex> result = BuiltinResult.new(ctx, stream1, stream2, 0)
    iex> {ctx, stdout, stderr} = BuiltinResult.get_streams(result)
    iex> Enum.to_list(stdout)
    ["output\n"]
"""
def get_streams(%__MODULE__{} = result) do
  # Update context with exit code only (no materialization)
  new_context = %{result.context | exit_code: result.exit_code}
  
  # Return streams as-is
  {new_context, result.stdout, result.stderr}
end

# Keep existing materialize_and_update for backwards compatibility
# (no changes to this function)

# Add helper for test usage
@doc """
Materialize streams for testing or compatibility.

## Examples

    iex> result = BuiltinResult.new(ctx, ["hello"], [], 0)
    iex> {ctx, stdout, stderr} = BuiltinResult.materialize(result)
    iex> stdout
    ["hello"]
"""
def materialize(%__MODULE__{} = result) do
  stdout_list = to_list(result.stdout)
  stderr_list = to_list(result.stderr)
  new_context = %{result.context | exit_code: result.exit_code}
  
  {new_context, stdout_list, stderr_list}
end

# Make to_list public for helper usage
@doc false
def to_list(stream) when is_function(stream), do: Enum.to_list(stream)
def to_list(string) when is_binary(string), do: if string == "", do: [], else: [string]
def to_list([]), do: []
def to_list(list) when is_list(list), do: list
def to_list(term), do: [term]

# Keep private materialize_output as alias to to_list for compat
defp materialize_output(output), do: to_list(output)
```

#### `test/unit/builtin_result_test.exs` (new file)
```elixir
defmodule RShell.BuiltinResultTest do
  use ExUnit.Case, async: true
  alias RShell.BuiltinResult
  
  describe "get_streams/1" do
    test "returns streams without materialization" do
      ctx = %{env: %{}, cwd: "/", exit_code: 0, command_count: 0}
      stream = Stream.concat(["hello\n", "world\n"])
      
      result = BuiltinResult.new(ctx, stream, Stream.concat([]), 0)
      {new_ctx, stdout, stderr} = BuiltinResult.get_streams(result)
      
      # Streams are not materialized
      assert is_function(stdout)
      assert is_function(stderr)
      
      # Can materialize when needed
      assert Enum.to_list(stdout) == ["hello\n", "world\n"]
      assert Enum.to_list(stderr) == []
      
      # Context updated with exit code
      assert new_ctx.exit_code == 0
    end
    
    test "handles lists and converts to streams" do
      ctx = %{env: %{}, cwd: "/", exit_code: 0, command_count: 0}
      
      result = BuiltinResult.new(ctx, ["line1\n"], ["error\n"], 1)
      {new_ctx, stdout, stderr} = BuiltinResult.get_streams(result)
      
      assert Enum.to_list(stdout) == ["line1\n"]
      assert Enum.to_list(stderr) == ["error\n"]
      assert new_ctx.exit_code == 1
    end
  end
  
  describe "materialize/1" do
    test "converts streams to lists" do
      ctx = %{env: %{}, cwd: "/", exit_code: 0, command_count: 0}
      stream = Stream.map(1..3, &"line#{&1}\n")
      
      result = BuiltinResult.new(ctx, stream, Stream.concat([]), 0)
      {_ctx, stdout, stderr} = BuiltinResult.materialize(result)
      
      # Lists returned
      assert stdout == ["line1\n", "line2\n", "line3\n"]
      assert stderr == []
    end
  end
  
  describe "backwards compatibility" do
    test "materialize_and_update still works" do
      ctx = %{env: %{}, cwd: "/", exit_code: 0, command_count: 0}
      
      result = BuiltinResult.new(ctx, ["output\n"], [], 0)
      {new_ctx, stdout, stderr} = BuiltinResult.materialize_and_update(result)
      
      # Still returns lists
      assert stdout == ["output\n"]
      assert stderr == []
      assert new_ctx.exit_code == 0
    end
  end
end
```

### Testing
```bash
mix test test/unit/builtin_result_test.exs
mix test  # Ensure no regressions
```

### Commit Message
```
refactor: Add stream API to BuiltinResult

- Add get_streams/1 to return streams without materialization
- Add materialize/1 helper for explicit materialization
- Make to_list/1 public for helper usage
- Keep materialize_and_update/1 for backwards compatibility
- Add comprehensive unit tests

No breaking changes - existing code continues to work.
New stream API available for consumers that want lazy evaluation.
```

---

## Commit 3: Update Runtime to Use Streams

**Goal**: Migrate Runtime.execute_builtin to use stream-based API.

### Files Changed
- `lib/r_shell/runtime.ex`

### Changes

#### `lib/r_shell/runtime.ex`
```elixir
# Update execute_builtin/4 (around line 400)
defp execute_builtin(name, args, stdin, state) do
  alias RShell.BuiltinResult
  
  case Builtins.execute(name, args, stdin, state) do
    {new_context, stdout, stderr, exit_code} when is_map(new_context) and not is_struct(new_context) ->
      # Backward compat: context returned
      result = BuiltinResult.new(new_context, stdout, stderr, exit_code)
      
      # NEW: Use get_streams instead of materialize_and_update
      {updated_context, stdout_stream, stderr_stream} = BuiltinResult.get_streams(result)
      
      # Add streams to FrameStack (FrameStack now handles streams)
      updated_stack = FrameStack.add_output(state.frame_stack, stdout_stream, stderr_stream)
      
      # Return updated state
      %{state | context: updated_context, frame_stack: updated_stack}
    
    {%ExecutionState{} = new_state, stdout, stderr, exit_code} ->
      # New: ExecutionState returned
      result = BuiltinResult.new(new_state.context, stdout, stderr, exit_code)
      
      # NEW: Use get_streams
      {updated_context, stdout_stream, stderr_stream} = BuiltinResult.get_streams(result)
      
      # Add streams to FrameStack from new_state
      updated_stack = FrameStack.add_output(new_state.frame_stack, stdout_stream, stderr_stream)
      
      # Return updated state with both context and frame_stack
      %{new_state | context: updated_context, frame_stack: updated_stack}
    
    {:error, :not_a_builtin} ->
      Logger.warning("Builtin '#{name}' not found despite passing is_builtin? check")
      raise "External command execution not yet implemented"
  end
end

# Update broadcast functions to materialize streams for PubSub (lines 589-617)
defp broadcast_execution_success_with_output(
       node,
       new_context,
       _old_context,
       duration_us,
       stdout_stream,  # Changed from stdout
       stderr_stream,  # Changed from stderr
       session_id
     ) do
  # Materialize for PubSub compatibility (for now)
  stdout = BuiltinResult.to_list(stdout_stream)
  stderr = BuiltinResult.to_list(stderr_stream)
  
  result = %{
    status: :success,
    node: node,
    node_type: get_node_type(node),
    node_text: get_node_text(node),
    node_line: get_node_line(node),
    exit_code: new_context.exit_code,
    stdout: stdout,
    stderr: stderr,
    context: %{
      env: new_context.env,
      cwd: new_context.cwd,
      exit_code: new_context.exit_code
    },
    duration_us: duration_us,
    timestamp: DateTime.utc_now()
  }
  
  PubSub.broadcast(session_id, :runtime, {:execution_result, result})
end

# Update execute_command_list to get streams from FrameStack (around line 705)
defp execute_command_list(nodes, state, accumulate) when is_list(nodes) do
  if accumulate do
    Enum.reduce(nodes, state, fn node, acc_state ->
      start_time = System.monotonic_time(:microsecond)
      
      try do
        new_state = simple_execute_with_state(node, acc_state)
        duration = System.monotonic_time(:microsecond) - start_time
        
        # Get output streams from FrameStack
        frame_output = FrameStack.get_output(new_state.frame_stack)
        
        # Broadcast with streams (broadcast function will materialize)
        broadcast_execution_success_with_output(
          node,
          new_state.context,
          acc_state.context,
          duration,
          frame_output.stdout,  # Stream
          frame_output.stderr,  # Stream
          new_state.session_id
        )
        
        new_state
      rescue
        e ->
          _duration = System.monotonic_time(:microsecond) - start_time
          
          # Get any output that was produced before error (streams from FrameStack)
          frame_output = FrameStack.get_output(acc_state.frame_stack)
          
          broadcast_execution_failure_with_output(
            e,
            node,
            frame_output.stdout,
            frame_output.stderr,
            acc_state.context.exit_code,
            acc_state.session_id
          )
          
          acc_state
      end
    end)
  else
    # ... similar changes for non-accumulate path
  end
end
```

### Testing
```bash
mix test test/integration/control_flow_test.exs
mix test test/integration/cli_test.exs
mix test  # Full suite
```

### Commit Message
```
refactor: Use stream API in Runtime.execute_builtin

- Switch from materialize_and_update/1 to get_streams/1
- Pass streams to FrameStack.add_output/3
- Update broadcast functions to materialize streams for PubSub
- Update execute_command_list to work with streams from FrameStack

All tests pass. Runtime now uses streams internally.
PubSub still receives materialized output (backwards compatible).
```

---

## Commit 4: Add Test Helpers for Stream Output

**Goal**: Provide convenient helpers for tests to work with streams.

### Files Changed
- `lib/r_shell/test_helpers.ex` (new)
- `test/support/cli_helper.ex` (update)
- `test/test_helper.exs` (update to compile test_helpers)

### Changes

#### `lib/r_shell/test_helpers.ex` (new file)
```elixir
defmodule RShell.TestHelpers do
  @moduledoc """
  Helper functions for working with stream-based output in tests.
  
  These helpers make it easy to materialize and assert on output streams
  without needing to manually call Enum.to_list/1 everywhere.
  """
  
  alias RShell.Runtime.{FrameStack, Frame}
  alias RShell.BuiltinResult
  
  @doc """
  Materialize output from a FrameStack, Frame, or BuiltinResult.
  
  Returns a map with materialized stdout and stderr lists.
  
  ## Examples
  
      iex> output = TestHelpers.materialize_output(stack)
      iex> output.stdout
      ["line1\\n", "line2\\n"]
      
      iex> output = TestHelpers.materialize_output(result)
      iex> output.stderr
      []
  """
  def materialize_output(%FrameStack{} = stack) do
    output = FrameStack.get_output(stack)
    %{
      stdout: Enum.to_list(output.stdout),
      stderr: Enum.to_list(output.stderr)
    }
  end
  
  def materialize_output(%Frame{} = frame) do
    %{
      stdout: Enum.to_list(frame.accumulated.stdout),
      stderr: Enum.to_list(frame.accumulated.stderr)
    }
  end
  
  def materialize_output(%BuiltinResult{} = result) do
    {_ctx, stdout, stderr} = BuiltinResult.materialize(result)
    %{stdout: stdout, stderr: stderr}
  end
  
  @doc """
  Get stdout as a single joined string.
  
  ## Examples
  
      iex> TestHelpers.stdout_string(stack)
      "line1\\nline2\\n"
  """
  def stdout_string(output_source) do
    materialize_output(output_source).stdout |> Enum.join("")
  end
  
  @doc """
  Get stderr as a single joined string.
  """
  def stderr_string(output_source) do
    materialize_output(output_source).stderr |> Enum.join("")
  end
  
  @doc """
  Get just the stdout list (convenience wrapper).
  """
  def stdout_list(output_source) do
    materialize_output(output_source).stdout
  end
  
  @doc """
  Get just the stderr list (convenience wrapper).
  """
  def stderr_list(output_source) do
    materialize_output(output_source).stderr
  end
  
  @doc """
  Assert that stdout matches expected output.
  
  ## Examples
  
      assert_stdout(stack, ["hello\\n", "world\\n"])
      assert_stdout(result, "hello\\nworld\\n")
  """
  def assert_stdout(output_source, expected) when is_list(expected) do
    ExUnit.Assertions.assert stdout_list(output_source) == expected
  end
  
  def assert_stdout(output_source, expected) when is_binary(expected) do
    ExUnit.Assertions.assert stdout_string(output_source) == expected
  end
  
  @doc """
  Assert that stderr matches expected output.
  """
  def assert_stderr(output_source, expected) when is_list(expected) do
    ExUnit.Assertions.assert stderr_list(output_source) == expected
  end
  
  def assert_stderr(output_source, expected) when is_binary(expected) do
    ExUnit.Assertions.assert stderr_string(output_source) == expected
  end
end
```

#### Update `test/support/cli_helper.ex`
```elixir
# Add import for test helpers
import RShell.TestHelpers

# Update execute_code to use test helpers
def execute_code(code, opts \\ []) do
  # ... existing code ...
  
  # Replace manual materialization with helper
  # OLD:
  # output = FrameStack.get_output(state.frame_stack)
  # stdout = Enum.to_list(output.stdout)
  
  # NEW:
  output = RShell.TestHelpers.materialize_output(state.frame_stack)
  stdout = output.stdout
  
  # ... rest of code ...
end
```

#### Update `test/test_helper.exs`
```elixir
# Ensure TestHelpers is compiled and available
Code.require_file("../lib/r_shell/test_helpers.ex", __DIR__)

ExUnit.start()
```

### Testing
```bash
mix test  # All tests should pass with new helpers
```

### Commit Message
```
feat: Add TestHelpers for stream-based output

- Create RShell.TestHelpers with materialize_output/1
- Add stdout_string/1, stderr_string/1 convenience functions
- Add stdout_list/1, stderr_list/1 for list assertions
- Add assert_stdout/2, assert_stderr/2 for cleaner test code
- Update CLIHelper to use new test helpers
- Add TestHelpers to test_helper.exs for availability

Tests can now easily work with streams using helpers.
No need to manually call Enum.to_list everywhere.
```

---

## Commit 5: Add CLI Output Renderer

**Goal**: Create CLI rendering layer that materializes streams on demand.

### Files Changed
- `lib/r_shell/cli/output_renderer.ex` (new)
- `lib/r_shell/cli.ex` (update to use renderer)

### Changes

#### `lib/r_shell/cli/output_renderer.ex` (new file)
```elixir
defmodule RShell.CLI.OutputRenderer do
  @moduledoc """
  Renders stream-based output to terminal.
  
  Provides flexible materialization strategies:
  - Stream directly to IO (memory efficient)
  - Take first/last N lines
  - Capture as string for display
  """
  
  @doc """
  Render output streams to terminal.
  
  ## Options
  
  - `:max_lines` - Maximum lines to display (default: :all)
  - `:last_only` - If true with max_lines, show last N instead of first N
  
  ## Examples
  
      # Stream all output to terminal
      OutputRenderer.render(output)
      
      # Show last 100 lines only
      OutputRenderer.render(output, max_lines: 100, last_only: true)
      
      # Show first 50 lines
      OutputRenderer.render(output, max_lines: 50)
  """
  def render(output, opts \\ []) do
    max_lines = Keyword.get(opts, :max_lines, :all)
    last_only = Keyword.get(opts, :last_only, false)
    
    case {max_lines, last_only} do
      {:all, _} ->
        # Stream directly to IO (most memory efficient)
        output.stdout |> Stream.each(&IO.write/1) |> Stream.run()
        output.stderr |> Stream.each(&IO.write(:stderr, &1)) |> Stream.run()
      
      {n, true} when is_integer(n) ->
        # Take last N lines (requires materialization)
        stdout_lines = output.stdout |> Enum.to_list() |> Enum.take(-n)
        stderr_lines = output.stderr |> Enum.to_list() |> Enum.take(-n)
        
        Enum.each(stdout_lines, &IO.write/1)
        Enum.each(stderr_lines, &IO.write(:stderr, &1))
      
      {n, false} when is_integer(n) ->
        # Take first N lines (can stream)
        output.stdout |> Stream.take(n) |> Stream.each(&IO.write/1) |> Stream.run()
        output.stderr |> Stream.take(n) |> Stream.each(&IO.write(:stderr, &1)) |> Stream.run()
    end
  end
  
  @doc """
  Capture output as strings (for display in UI).
  
  ## Options
  
  - `:max_lines` - Maximum lines to capture per stream (default: 1000)
  
  ## Examples
  
      iex> OutputRenderer.to_strings(output)
      %{stdout: "line1\\nline2\\n", stderr: ""}
      
      iex> OutputRenderer.to_strings(output, max_lines: 10)
      %{stdout: "...", stderr: "..."}
  """
  def to_strings(output, opts \\ []) do
    max_lines = Keyword.get(opts, :max_lines, 1000)
    
    stdout = output.stdout
      |> Stream.take(max_lines)
      |> Enum.join("")
    
    stderr = output.stderr
      |> Stream.take(max_lines)
      |> Enum.join("")
    
    %{stdout: stdout, stderr: stderr}
  end
  
  @doc """
  Stream output line-by-line with a callback.
  
  Useful for progress indicators or filtering during execution.
  
  ## Examples
  
      OutputRenderer.stream_lines(output, fn line ->
        IO.write(colorize(line))
      end)
  """
  def stream_lines(output, callback) when is_function(callback, 1) do
    output.stdout |> Stream.each(callback) |> Stream.run()
    output.stderr |> Stream.each(callback) |> Stream.run()
  end
end
```

#### Update `lib/r_shell/cli.ex`
```elixir
# Add alias
alias RShell.CLI.OutputRenderer

# Update output display (wherever output is currently rendered)
def display_output(state) do
  output = FrameStack.get_output(state.runtime_state.frame_stack)
  
  # NEW: Use renderer instead of manual materialization
  OutputRenderer.render(output)
  
  state
end

# Or for interactive mode with history limit:
def display_output_limited(state, max_lines \\ 100) do
  output = FrameStack.get_output(state.runtime_state.frame_stack)
  
  # Show last 100 lines only (memory efficient)
  OutputRenderer.render(output, max_lines: max_lines, last_only: true)
  
  state
end
```

### Testing
```bash
# Manual testing in interactive mode
mix cli

# Run test suite
mix test
```

### Commit Message
```
feat: Add CLI OutputRenderer for stream materialization

- Create RShell.CLI.OutputRenderer module
- Add render/2 with flexible materialization options
- Support :all (stream), first N, or last N lines
- Add to_strings/2 for UI capture (with max_lines limit)
- Add stream_lines/2 for callback-based processing
- Update CLI to use OutputRenderer instead of manual materialization

CLI now materializes output on demand with configurable limits.
Memory efficient for large outputs (e.g., logs, file contents).
```

---

## Summary

### Commits Overview

1. **Commit 1**: Frame & FrameStack stream support (internal only)
2. **Commit 2**: BuiltinResult stream API (dual API for migration)
3. **Commit 3**: Runtime uses streams (streams flow through system)
4. **Commit 4**: TestHelpers (easy testing with streams)
5. **Commit 5**: CLI OutputRenderer (consumer-side materialization)

### Testing Strategy

After each commit:
```bash
mix test                              # Full suite
mix test test/integration/           # Integration tests
mix test test/unit/builtins/         # Builtin tests
```

After all commits:
```bash
# Interactive testing
mix cli
> for I in [1, 2, 3, 4, 5] { echo "Line $I" }

# Memory profiling (before/after)
mix profile.memory --eval "RShell.CLI.execute_code(large_script)"
```

### Success Criteria

- [ ] All 5 commits applied cleanly
- [ ] Full test suite passes after each commit
- [ ] No breaking changes to public APIs
- [ ] Memory usage reduced for large outputs
- [ ] CLI can display "last N lines" efficiently
- [ ] Tests work with new helpers
- [ ] Documentation updated

---

## Next Steps

1. Review this plan
2. Implement commits 1-5 in sequence
3. Test after each commit
4. Update [`STREAM_OUTPUT_DESIGN.md`](STREAM_OUTPUT_DESIGN.md:1) with "Implemented" status
5. Update [`DOCUMENTATION_INDEX.md`](DOCUMENTATION_INDEX.md:1) to reference stream design