# Builtin ExecutionState Migration Design

## Goal

Migrate builtins from `(argv, stdin, context)` to `(argv, stdin, state)` where state is `ExecutionState`, giving builtins access to the frame stack.

## Current Signature

```elixir
def shell_echo(argv, stdin, context) do
  {context, stdout, stderr, exit_code}
end
```

## Proposed Signature

```elixir
def shell_echo(argv, stdin, state) do
  # state.context - execution context
  # state.frame_stack - frame stack!
  # state.session_id - session ID
  {state, stdout, stderr, exit_code}
end
```

## Migration Strategy

### Phase 1: Update Builtin Interface (Backward Compatible)

**Change execute/4 to accept ExecutionState:**
```elixir
# Old
def execute(name, argv, stdin, context)

# New (backward compatible wrapper)
def execute(name, argv, stdin, context) when is_map(context) do
  # Create minimal ExecutionState from context
  state = %ExecutionState{
    context: context,
    frame_stack: FrameStack.new(output_mode: :isolate, context: context),
    session_id: Map.get(context, :session_id, "unknown")
  }
  
  case execute_with_state(name, argv, stdin, state) do
    {new_state, stdout, stderr, exit_code} ->
      {new_state.context, stdout, stderr, exit_code}
  end
end

# New primary function
def execute_with_state(name, argv, stdin, state) do
  # Call builtin with state
  apply(__MODULE__, function_name, [argv, stdin, state])
end
```

### Phase 2: Migrate Individual Builtins

**Simple builtins (no context changes):**
```elixir
# Before
def shell_echo(argv, stdin, context) do
  {context, stdout, stderr, 0}
end

# After
def shell_echo(argv, stdin, state) do
  {state, stdout, stderr, 0}
end
```

**Context-modifying builtins:**
```elixir
# Before
def shell_cd(argv, stdin, context) do
  new_context = %{context | cwd: new_dir}
  {new_context, stdout, stderr, 0}
end

# After
def shell_cd(argv, stdin, state) do
  new_context = %{state.context | cwd: new_dir}
  new_state = %{state | context: new_context}
  {new_state, stdout, stderr, 0}
end
```

### Phase 3: New Frame Stack Debugging Builtins

**stackdump - Show frame stack:**
```elixir
@shell_stackdump_opts :argv
def shell_stackdump(_argv, _stdin, state) do
  frames = state.frame_stack.frames
  
  output = frames
  |> Enum.with_index()
  |> Enum.map(fn {frame, idx} ->
    """
    Frame ##{idx}: #{frame.type}
      Output mode: #{frame.output_mode}
      Accumulated: #{length(frame.accumulated.stdout)} stdout, #{length(frame.accumulated.stderr)} stderr
      Scope vars: #{Map.keys(frame.scope) |> Enum.join(", ")}
      Metadata: #{inspect(frame.metadata, pretty: true)}
    """
  end)
  |> Enum.join("\n")
  
  {state, Utils.stream(output), Utils.stream(""), 0}
end
```

**frames - Count frames:**
```elixir
@shell_frames_opts :argv
def shell_frames(_argv, _stdin, state) do
  count = length(state.frame_stack.frames)
  output = "Frame count: #{count}\n"
  {state, Utils.stream(output), Utils.stream(""), 0}
end
```

**scope - Show current scope chain:**
```elixir
@shell_scope_opts :argv
def shell_scope(_argv, _stdin, state) do
  output = state.frame_stack.frames
  |> Enum.map(fn frame ->
    if map_size(frame.scope) > 0 do
      vars = frame.scope
      |> Enum.map(fn {k, v} -> "  #{k} = #{inspect(v, pretty: true)}" end)
      |> Enum.join("\n")
      
      "#{frame.type} scope:\n#{vars}"
    else
      "#{frame.type} scope: (empty)"
    end
  end)
  |> Enum.join("\n\n")
  
  {state, Utils.stream(output <> "\n"), Utils.stream(""), 0}
end
```

## Benefits

1. **Frame Stack Access**: Builtins can inspect/modify the frame stack
2. **Better Debugging**: `stackdump`, `frames`, `scope` builtins
3. **Future Features**: 
   - Builtins could push their own frames for complex operations
   - Access to parent scopes for variable lookup
   - Inspection of call stack depth

## Example Usage

```rshell
# Simple debugging
stackdump                    # Show all frames

# Inside a loop
for (i in [1, 2, 3]) {
  stackdump                 # Shows global frame + loop frame
  echo $i
}

# Nested structures
while (X < 3) {
  for (j in [1, 2]) {
    stackdump             # Shows global + while + for frames!
    echo "$X:$j"
  }
  X = X + 1
}

# Check scope
scope                       # Show all scoped variables
```

## Migration Checklist

- [ ] Add ExecutionState support to Builtins.execute/4 (backward compatible)
- [ ] Migrate core builtins (echo, true, false, pwd)
- [ ] Migrate context-modifying builtins (cd, env)
- [ ] Add stackdump builtin
- [ ] Add frames builtin  
- [ ] Add scope builtin
- [ ] Update Runtime to call execute_with_state
- [ ] Remove backward compatibility wrapper