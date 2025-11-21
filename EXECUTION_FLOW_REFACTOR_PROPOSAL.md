# Execution Flow Refactor Proposal

## Current Problems

Based on investigation of the exit code propagation bug, we've identified several architectural issues:

### 1. **Too Many Layers with Context Copying**
Current flow:
```
Runtime.execute_node (GenServer call)
  → execute_node_internal
    → ExecutionPipeline.execute
      → Runtime.do_execute_node (exported)
        → execute_command
          → execute_builtin
            → Builtins.execute
```

**Issues:**
- 5+ layers of function calls
- Context copied/transformed at each layer
- Exit codes can be lost during transformations
- Hard to trace where values change

### 2. **Confusing Context Semantics**

Builtins return: `{new_context, stdout, stderr, exit_code}`

But `new_context` is often the SAME unchanged input context, while `exit_code` is separate.

Example from `shell_false`:
```elixir
def shell_false(_argv, _stdin, context) do
  {context, Utils.stream(""), Utils.stream(""), 1}
  #  ^^^^^^^ UNCHANGED (exit_code: 0)              ^^^^ SEPARATE VALUE (1)
end
```

This creates confusion: which exit_code is authoritative?

### 3. **Wrapper Node Handling is Scattered**

CmdLine unwrapping happens in `do_execute_node`, but:
- Command count increment logic is tangled with unwrapping
- Not clear which nodes increment counts vs pass-through
- Hard to add new wrapper types

### 4. **Exit Code Update Problem**

When we try:
```elixir
%{new_context | exit_code: exit_code}
```

It should work, but doesn't in practice. Suggests:
- Map update syntax issue?
- Stale context being used?
- GenServer state not persisting correctly?

## Proposed Elegant Solution

### Design Principles
1. **Single Source of Truth**: Exit codes only in context, never separate
2. **Explicit Context Flow**: Clear where context changes vs passes through
3. **Minimal Layers**: Reduce indirection
4. **Type Safety**: Use structs instead of maps for context

### Proposed Architecture

#### 1. Context as a Struct
```elixir
defmodule RShell.ExecutionContext do
  @moduledoc "Immutable execution context"
  
  defstruct [
    :env,           # Environment variables
    :env_meta,      # Variable metadata
    :cwd,           # Current directory
    :exit_code,     # ALWAYS authoritative
    :command_count, # Commands executed
    :last_output    # {stdout, stderr} lists
  ]
  
  @type t :: %__MODULE__{
    env: map(),
    env_meta: map(),
    cwd: String.t(),
    exit_code: integer(),
    command_count: integer(),
    last_output: %{stdout: list(), stderr: list()}
  }
  
  def new(opts \\ []) do
    %__MODULE__{
      env: Keyword.get(opts, :env, System.get_env()),
      env_meta: %{},
      cwd: Keyword.get(opts, :cwd, System.get_env("PWD") || "/"),
      exit_code: 0,
      command_count: 0,
      last_output: %{stdout: [], stderr: []}
    }
  end
  
  def set_exit_code(context, code), do: %{context | exit_code: code}
  def increment_command(context), do: %{context | command_count: context.command_count + 1}
  def set_output(context, stdout, stderr), do: %{context | last_output: %{stdout: stdout, stderr: stderr}}
end
```

#### 2. Builtin Contract Change
```elixir
# OLD: Returns separate exit_code
{new_context, stdout, stderr, exit_code}

# NEW: Exit code ALWAYS in context
{%ExecutionContext{exit_code: 1}, stdout, stderr}
```

Update all builtins:
```elixir
def shell_false(_argv, _stdin, context) do
  context = ExecutionContext.set_exit_code(context, 1)
  {context, Utils.stream(""), Utils.stream("")}
end
```

#### 3. Simplified Execution Flow
```elixir
defmodule RShell.Runtime do
  def do_execute_node(node, context, session_id) do
    case node do
      # Transparent wrappers - pass through unchanged
      %Types.CmdLine{children: [inner | _]} ->
        do_execute_node(inner, context, session_id)
      
      # Actual commands - increment count and execute
      %Types.Command{} = cmd ->
        context
        |> ExecutionContext.increment_command()
        |> execute_command(cmd, session_id)
      
      %Types.Assignment{} = assign ->
        # Assignments don't increment command count
        execute_assignment(assign, context, session_id)
      
      # Control flow
      %Types.IfStatement{} = stmt ->
        context
        |> ExecutionContext.increment_command()
        |> execute_if(stmt, session_id)
    end
  end
  
  defp execute_command(context, cmd, session_id) do
    # Extract command parts
    {:ok, name, args} = extract_command_parts(cmd, context)
    
    if Builtins.is_builtin?(name) do
      # Builtins return modified context directly
      {new_context, stdout, stderr} = Builtins.execute(name, args, "", context)
      
      # Materialize streams and update output
      ExecutionContext.set_output(
        new_context,
        materialize(stdout),
        materialize(stderr)
      )
    else
      execute_external(context, name, args, session_id)
    end
  end
end
```

#### 4. Remove ExecutionPipeline Layer
Move broadcasting directly into Runtime:
```elixir
defp execute_node_internal(node, context, session_id) do
  start_time = System.monotonic_time(:microsecond)
  
  try do
    new_context = do_execute_node(node, context, session_id)
    duration = System.monotonic_time(:microsecond) - start_time
    
    # Broadcast success
    broadcast_result(node, new_context, duration, session_id)
    
    {{:ok, new_context}, new_context}
  rescue
    e ->
      broadcast_error(node, e, session_id)
      {{:error, Exception.message(e)}, context}
  end
end
```

### Migration Path

1. **Phase 1**: Add ExecutionContext struct alongside existing map
2. **Phase 2**: Update all builtins to return context with exit_code inside
3. **Phase 3**: Remove separate exit_code parameter from builtin protocol
4. **Phase 4**: Inline ExecutionPipeline into Runtime
5. **Phase 5**: Replace all context maps with ExecutionContext struct

### Benefits

✅ **Single source of truth**: Exit code always in context
✅ **Fewer layers**: Remove ExecutionPipeline indirection  
✅ **Type safety**: Struct with @spec instead of map
✅ **Clear semantics**: Builtin returns modified context, not mixed tuple
✅ **Easier debugging**: Context transformations are explicit
✅ **Testability**: Can test context transformations in isolation

### Testing Strategy

Each phase is independently testable:
- Phase 1: Tests pass with both map and struct
- Phase 2: Test builtins return correct exit codes in context
- Phase 3: Test protocol change with integration tests
- Phase 4: Test same behavior with inlined pipeline
- Phase 5: Final cleanup and verification

## Implementation Notes

### Key Insight from Investigation

The exit code bug revealed that **mixing separate exit_code values with context objects causes confusion**. The builtin returns the *unchanged* input context plus a *separate* exit code value. When we try to merge them, something gets lost.

**Solution**: Make context the single source of truth. If a builtin wants to set exit code 1, it modifies the context BEFORE returning it.

### Why This is More Elegant

1. **Immutable data flow**: Each function takes context, returns new context
2. **Pure functions**: Easy to test and reason about
3. **No hidden state**: Everything flows through explicit parameters
4. **Type safety**: Struct ensures required fields always present
5. **Self-documenting**: Function signatures tell the whole story

## Next Steps

1. Create ExecutionContext module
2. Update one builtin (false) to use new pattern
3. Verify exit code propagates correctly
4. If successful, migrate remaining builtins
5. Remove ExecutionPipeline layer
6. Convert all context maps to structs

---

*This refactor addresses the fundamental question: "how can we make the execution flow more elegant?"*