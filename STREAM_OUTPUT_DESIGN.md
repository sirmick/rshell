# Stream-Based Output Design

**Status**: Design Phase  
**Created**: 2025-11-23  
**Owner**: Runtime Team

---

## Overview

Replace the current eager materialization approach for stdout/stderr with a lazy stream-based architecture. This design eliminates unnecessary memory overhead, provides flexible consumption patterns, and decouples output production from consumption.

---

## Current Problems

### 1. Eager Materialization
```elixir
# In BuiltinResult.materialize_and_update/1 (line 67)
def materialize_and_update(%__MODULE__{} = result) do
  stdout_list = materialize_output(result.stdout)  # 🔴 Eager conversion
  stderr_list = materialize_output(result.stderr)  # 🔴 Eager conversion
  # ...
end
```

**Issues:**
- Converts entire streams to lists immediately
- Happens before output is needed
- Memory inefficient for large outputs (logs, file contents)
- No way to defer materialization

### 2. List-Based Storage
```elixir
# In Frame (line 47)
defstruct accumulated: %{stdout: [], stderr: []}  # 🔴 Lists, not streams

# In FrameStack.add_output/3 (line 214)
def add_output(stack, stdout, stderr) do
  # Expects lists, appends to lists
  new_accumulated = %{
    stdout: current.accumulated.stdout ++ stdout,  # 🔴 List concatenation
    stderr: current.accumulated.stderr ++ stderr
  }
end
```

**Issues:**
- Output stored as materialized lists
- List concatenation is O(n) for each append
- Cannot support streaming/filtering without full materialization

### 3. Inflexible Consumption
```elixir
# CLI must materialize everything to display anything
output = FrameStack.get_output(stack)
IO.write(Enum.join(output.stdout, ""))  # 🔴 All or nothing
```

**Issues:**
- No way to get "last N lines" without loading all
- No streaming output during long-running commands
- Tests must load all output even for simple assertions

---

## Design Goals

1. **Lazy Evaluation**: Output materialized only when consumed
2. **Memory Efficient**: Don't load unnecessary data into memory
3. **Flexible Consumption**: Support various consumption patterns (all, first N, last N, stream)
4. **Composable**: Streams can be filtered, transformed, merged
5. **Decoupled**: Runtime doesn't know how output will be consumed
6. **Backwards Compatible**: Easy migration path for existing code

---

## Architecture

### Core Principle

**Keep stdout/stderr as streams throughout execution. Materialize only at consumption boundaries.**

### Data Flow

```
Builtin Execution
    ↓
Stream.resource() or Stream.unfold()
    ↓
BuiltinResult (stores streams)
    ↓
Frame.accumulated (stores streams)
    ↓
FrameStack.get_output() (returns streams)
    ↓
Consumer materializes (CLI, tests, PubSub)
```

---

## Implementation Details

### 1. BuiltinResult - Remove Materialization

**Current (Eager):**
```elixir
def materialize_and_update(%__MODULE__{} = result) do
  stdout_list = materialize_output(result.stdout)  # 🔴 Eager
  stderr_list = materialize_output(result.stderr)
  
  new_context = %{result.context | exit_code: result.exit_code}
  {new_context, stdout_list, stderr_list}
end
```

**New (Lazy):**
```elixir
def get_streams(%__MODULE__{} = result) do
  # Return streams directly, update context
  new_context = %{result.context | exit_code: result.exit_code}
  {new_context, result.stdout, result.stderr}
end

# Helper for consumers that need lists (tests, compatibility)
def materialize(%__MODULE__{} = result) do
  stdout_list = to_list(result.stdout)
  stderr_list = to_list(result.stderr)
  {result.context, stdout_list, stderr_list}
end

# Private helper
defp to_list(stream) when is_function(stream), do: Enum.to_list(stream)
defp to_list(string) when is_binary(string), do: if string == "", do: [], else: [string]
defp to_list([]), do: []
defp to_list(list) when is_list(list), do: list
defp to_list(term), do: [term]
```

### 2. Frame - Store Streams

**Current:**
```elixir
defstruct accumulated: %{stdout: [], stderr: []}  # 🔴 Lists
```

**New:**
```elixir
defstruct accumulated: %{stdout: Stream.concat([]), stderr: Stream.concat([])}  # ✅ Streams

@type t :: %__MODULE__{
  type: frame_type(),
  output_mode: output_mode(),
  scope: map(),
  accumulated: %{stdout: Enumerable.t(), stderr: Enumerable.t()},  # ✅ Changed
  metadata: map(),
  parent_scope: map() | nil
}
```

### 3. FrameStack - Stream Operations

**Current:**
```elixir
def add_output(stack, stdout, stderr) do
  case current.output_mode do
    :accumulate ->
      new_accumulated = %{
        stdout: current.accumulated.stdout ++ stdout,  # 🔴 List concat
        stderr: current.accumulated.stderr ++ stderr
      }
  end
end
```

**New:**
```elixir
def add_output(stack, stdout_stream, stderr_stream) do
  case current.output_mode do
    :isolate ->
      # Replace with new streams
      updated_frame = %{current | accumulated: %{
        stdout: ensure_stream(stdout_stream),
        stderr: ensure_stream(stderr_stream)
      }}
      %{stack | frames: [updated_frame | rest]}
    
    :accumulate ->
      # Concatenate streams lazily
      new_accumulated = %{
        stdout: Stream.concat([current.accumulated.stdout, ensure_stream(stdout_stream)]),
        stderr: Stream.concat([current.accumulated.stderr, ensure_stream(stderr_stream)])
      }
      updated_frame = %{current | accumulated: new_accumulated}
      %{stack | frames: [updated_frame | rest]}
  end
end

# Ensure we have a stream
defp ensure_stream(s) when is_function(s), do: s
defp ensure_stream(list) when is_list(list), do: Stream.concat(list)
defp ensure_stream(str) when is_binary(str), do: Stream.concat(if str == "", do: [], else: [str])
defp ensure_stream(term), do: Stream.concat([term])
```

### 4. Runtime - Pass Streams Through

**Current:**
```elixir
def execute_builtin(name, args, stdin, state) do
  case Builtins.execute(name, args, stdin, state) do
    {new_context, stdout, stderr, exit_code} ->
      result = BuiltinResult.new(new_context, stdout, stderr, exit_code)
      {updated_context, stdout_list, stderr_list} = BuiltinResult.materialize_and_update(result)  # 🔴
      
      updated_stack = FrameStack.add_output(state.frame_stack, stdout_list, stderr_list)
      %{state | context: updated_context, frame_stack: updated_stack}
  end
end
```

**New:**
```elixir
def execute_builtin(name, args, stdin, state) do
  case Builtins.execute(name, args, stdin, state) do
    {new_context, stdout, stderr, exit_code} ->
      result = BuiltinResult.new(new_context, stdout, stderr, exit_code)
      {updated_context, stdout_stream, stderr_stream} = BuiltinResult.get_streams(result)  # ✅
      
      updated_stack = FrameStack.add_output(state.frame_stack, stdout_stream, stderr_stream)
      %{state | context: updated_context, frame_stack: updated_stack}
  end
end
```

### 5. Consumer Helpers

**For Tests:**
```elixir
defmodule RShell.TestHelpers do
  @doc "Materialize output for test assertions"
  def materialize_output(frame_or_stack) do
    output = case frame_or_stack do
      %FrameStack{} -> FrameStack.get_output(frame_or_stack)
      %Frame{} -> frame_or_stack.accumulated
    end
    
    %{
      stdout: Enum.to_list(output.stdout),
      stderr: Enum.to_list(output.stderr)
    }
  end
  
  @doc "Get stdout as single string for assertions"
  def stdout_string(frame_or_stack) do
    materialize_output(frame_or_stack).stdout |> Enum.join("")
  end
end
```

**For CLI:**
```elixir
defmodule RShell.CLI.OutputRenderer do
  @doc "Render output streams to terminal"
  def render(output, opts \\\\ []) do
    max_lines = Keyword.get(opts, :max_lines, :all)
    
    case max_lines do
      :all ->
        # Stream directly to IO
        output.stdout |> Stream.each(&IO.write/1) |> Stream.run()
        output.stderr |> Stream.each(&IO.write(:stderr, &1)) |> Stream.run()
      
      n when is_integer(n) ->
        # Take last N lines
        stdout_lines = output.stdout |> Enum.to_list() |> Enum.take(-n)
        stderr_lines = output.stderr |> Enum.to_list() |> Enum.take(-n)
        
        Enum.each(stdout_lines, &IO.write/1)
        Enum.each(stderr_lines, &IO.write(:stderr, &1))
    end
  end
  
  @doc "Capture output as string (for display in UI)"
  def to_string(output, opts \\\\ []) do
    max_lines = Keyword.get(opts, :max_lines, 1000)
    
    stdout = output.stdout
      |> Stream.take(max_lines)
      |> Enum.join("")
    
    %{stdout: stdout, stderr: Enum.join(output.stderr, "")}
  end
end
```

**For PubSub:**
```elixir
# Option 1: Keep streams in events (lazy)
defp broadcast_execution_success_with_output(node, context, duration, stdout_stream, stderr_stream, session_id) do
  result = %{
    status: :success,
    # ... other fields ...
    stdout: stdout_stream,  # ✅ Stream
    stderr: stderr_stream,  # ✅ Stream
  }
  
  PubSub.broadcast(session_id, :runtime, {:execution_result, result})
end

# Option 2: Materialize for backwards compatibility (eager)
defp broadcast_execution_success_with_output(node, context, duration, stdout_stream, stderr_stream, session_id) do
  result = %{
    status: :success,
    # ... other fields ...
    stdout: Enum.to_list(stdout_stream),  # 🔴 Materialize for compat
    stderr: Enum.to_list(stderr_stream),
  }
  
  PubSub.broadcast(session_id, :runtime, {:execution_result, result})
end
```

---

## Migration Strategy

### Phase 1: Internal Stream Support (No Breaking Changes)
1. Update `Frame.accumulated` to store streams
2. Update `FrameStack.add_output/3` to accept streams
3. Update `Runtime.execute_builtin/4` to pass streams
4. Keep `BuiltinResult.materialize_and_update/1` for compatibility
5. Add `BuiltinResult.get_streams/1` as new API

**Result**: Runtime uses streams internally, but existing tests still work.

### Phase 2: Consumer Migration
1. Add `RShell.TestHelpers` with `materialize_output/1`
2. Update tests to use new helpers
3. Update CLI to use stream-based rendering
4. Update PubSub broadcasts (decide lazy vs eager)

**Result**: All consumers use streams properly.

### Phase 3: Cleanup
1. Remove `BuiltinResult.materialize_and_update/1`
2. Mark old patterns as deprecated
3. Update documentation

---

## Benefits

### Memory Efficiency
```elixir
# Before: Load all 1GB of logs into memory
output = FrameStack.get_output(stack)
last_100 = output.stdout |> Enum.to_list() |> Enum.take(-100)

# After: Only materialize last 100 lines
output = FrameStack.get_output(stack)
last_100 = output.stdout |> Stream.take(-100) |> Enum.to_list()
```

### Composability
```elixir
# Filter output without materialization
errors_only = output.stderr
  |> Stream.filter(&String.contains?(&1, "ERROR"))
  |> Enum.to_list()

# Chain transformations
formatted = output.stdout
  |> Stream.map(&String.trim/1)
  |> Stream.reject(&(&1 == ""))
  |> Stream.with_index()
  |> Enum.to_list()
```

### Flexibility
```elixir
# Different consumption patterns
output.stdout |> Stream.take(10) |> Enum.to_list()     # First 10
output.stdout |> Stream.drop(10) |> Enum.to_list()     # Skip 10
output.stdout |> Enum.count()                          # Count only
output.stdout |> Stream.each(&IO.write/1) |> Stream.run()  # Stream to IO
```

---

## Open Questions

1. **PubSub Events**: Should broadcasts include streams or materialized output?
   - **Recommendation**: Start with materialized for compatibility, migrate to streams later

2. **Builtin Requirements**: Can all builtins return streams, or do some need materialization?
   - **Recommendation**: Most can stream, but `math.calc` and similar might materialize internally

3. **Error Handling**: If stream evaluation fails mid-consumption, how to handle?
   - **Recommendation**: Let consumer handle errors, provide `safe_to_list/1` helper

4. **Performance**: Does stream overhead outweigh benefits for small outputs?
   - **Recommendation**: Measure, but expect negligible impact for typical workloads

---

## Testing Strategy

### Unit Tests
```elixir
# Test stream concatenation
test "accumulate mode concatenates streams" do
  stack = FrameStack.new(output_mode: :accumulate)
  
  stack = FrameStack.add_output(stack, Stream.concat(["a"]), Stream.concat([]))
  stack = FrameStack.add_output(stack, Stream.concat(["b"]), Stream.concat([]))
  
  output = FrameStack.get_output(stack)
  assert Enum.to_list(output.stdout) == ["a", "b"]
end

# Test isolate mode replaces streams
test "isolate mode replaces streams" do
  stack = FrameStack.new(output_mode: :isolate)
  
  stack = FrameStack.add_output(stack, Stream.concat(["first"]), Stream.concat([]))
  stack = FrameStack.add_output(stack, Stream.concat(["second"]), Stream.concat([]))
  
  output = FrameStack.get_output(stack)
  assert Enum.to_list(output.stdout) == ["second"]
end
```

### Integration Tests
```elixir
test "for loop accumulates output as stream" do
  code = """
  for I in [1, 2, 3] {
    echo "Line $I"
  }
  """
  
  {:ok, state} = execute_code(code)
  output = TestHelpers.materialize_output(state.frame_stack)
  
  assert output.stdout == ["Line 1\n", "Line 2\n", "Line 3\n"]
end
```

---

## Success Criteria

- [ ] All existing tests pass without modification
- [ ] Memory usage reduced for large output workloads
- [ ] CLI can render "last N lines" without loading all output
- [ ] Streams are properly lazy (verified with instrumentation)
- [ ] Performance is equal or better than current implementation
- [ ] Documentation updated with stream-based patterns

---

## References

- **Current Implementation**: [`lib/r_shell/runtime.ex:400`](lib/r_shell/runtime.ex:400)
- **Frame Storage**: [`lib/r_shell/runtime/frame.ex:47`](lib/r_shell/runtime/frame.ex:47)
- **FrameStack Operations**: [`lib/r_shell/runtime/frame_stack.ex:214`](lib/r_shell/runtime/frame_stack.ex:214)
- **BuiltinResult**: [`lib/r_shell/builtin_result.ex:67`](lib/r_shell/builtin_result.ex:67)