# Execution Frame Stack Design for RShell Runtime

## Problem Statement

The current runtime has become complex due to mixing concerns:
- Output accumulation (loops need it, interactive commands don't)
- Context threading (variables, cwd, exit codes)
- Scope management (will need for functions, subshells)
- Control flow state (loop iteration counters, function call depth)

The `accumulate` parameter is a band-aid solution. As we add:
- **Functions** - need local scopes
- **Subshells** - need isolated contexts
- **Pipelines** - need output chaining
- **Command substitution** - need captured output

...the complexity will explode.

## Proposed Solution: Execution Frame Stack

### Core Concept

Execute code within **frames** on a stack. Each frame has:
- **Scope**: Variable bindings (with shadowing)
- **Output mode**: How to handle command output (accumulate, isolate, pipe, capture)
- **Type**: What kind of execution context (global, loop, function, subshell)
- **State**: Frame-specific state (loop counters, function args, etc.)

### Frame Types

```elixir
defmodule RShell.Runtime.Frame do
  @type frame_type :: :global | :loop | :function | :subshell | :command_substitution
  
  @type output_mode :: 
    :isolate      # Each command clears previous output (interactive/top-level)
    | :accumulate # Collect all outputs (loops, blocks)
    | :pipe       # Chain to next command (pipelines)
    | :capture    # Capture for substitution ($(cmd))
  
  defstruct [
    :type,           # frame_type
    :output_mode,    # output_mode
    :scope,          # %{var_name => value} - local variables
    :accumulated,    # %{stdout: [], stderr: []} - accumulated output
    :metadata,       # Frame-specific data (loop counter, function name, etc.)
    :parent_scope    # Reference to parent for variable lookup
  ]
end
```

### Stack Operations

```elixir
defmodule RShell.Runtime.FrameStack do
  defstruct [
    :frames,         # [Frame.t()] - stack of frames
    :global_context  # %{env, cwd, exit_code, command_count}
  ]
  
  # Push a new frame
  def push_frame(stack, type, output_mode, metadata \\ %{})
  
  # Pop the current frame, return accumulated output
  def pop_frame(stack) :: {stack, accumulated_output}
  
  # Get variable (searches up the scope chain)
  def get_variable(stack, name)
  
  # Set variable (in current frame's scope)
  def set_variable(stack, name, value)
  
  # Add output to current frame
  def add_output(stack, stdout, stderr)
  
  # Get current output mode
  def output_mode(stack)
end
```

## Execution Flow

### Global/Interactive Commands
```elixir
# Start with global frame (output_mode: :isolate)
stack = FrameStack.new(output_mode: :isolate)

# Execute: echo "hello"
stack = execute_command("echo", ["hello"], stack)
# Frame accumulates: stdout=["hello\n"]
# Assignment clears it: stdout=[]

# Execute: X = 5
stack = execute_assignment("X", 5, stack)
# Frame output: stdout=[] (cleared)
```

### While Loop
```elixir
# Execute: while (X < 3) { echo $X; X = X + 1 }

# Push loop frame (output_mode: :accumulate)
stack = FrameStack.push_frame(stack, :loop, :accumulate, %{iteration: 0})

# Iteration 1: X=0
stack = execute_command("echo", [0], stack)  # stdout=["0\n"]
stack = execute_assignment("X", 1, stack)     # stdout still ["0\n"] - no clear in accumulate mode!

# Iteration 2: X=1
stack = execute_command("echo", [1], stack)  # stdout=["0\n", "1\n"]
stack = execute_assignment("X", 2, stack)     # stdout still ["0\n", "1\n"]

# Iteration 3: X=2
stack = execute_command("echo", [2], stack)  # stdout=["0\n", "1\n", "2\n"]
stack = execute_assignment("X", 3, stack)     # stdout still ["0\n", "1\n", "2\n"]

# Pop frame - return accumulated output
{stack, output} = FrameStack.pop_frame(stack)
# output = %{stdout: ["0\n", "1\n", "2\n"], stderr: []}
```

### Functions (Future)
```elixir
# Define: function greet(name) { echo "Hello, $name" }
# Call: greet("World")

# Push function frame (output_mode: :accumulate, creates new scope)
stack = FrameStack.push_frame(stack, :function, :accumulate, %{
  name: "greet",
  args: ["World"]
})

# Set local variable in function scope
stack = FrameStack.set_variable(stack, "name", "World")

# Execute body
stack = execute_command("echo", ["Hello, World"], stack)

# Pop frame - function variables disappear
{stack, output} = FrameStack.pop_frame(stack)
# Variable "name" no longer exists in parent scope
```

## Key Benefits

### 1. Clean Separation of Concerns
- **Output handling**: Controlled by frame's `output_mode`
- **Scoping**: Each frame has its own scope with parent lookup
- **State management**: Frame metadata holds loop counters, function args, etc.

### 2. No More Boolean Flags
- Remove `accumulate` parameter threading through all functions
- Frame type determines behavior automatically

### 3. Future-Proof
- **Subshells**: `{ cmd; }` - Push frame, execute, pop (isolated changes)
- **Command substitution**: `$(cmd)` - Push :capture frame, execute, pop and return output
- **Pipelines**: Push :pipe frames, chain output
- **Functions**: Local scopes with shadowing

### 4. Clearer Control Flow
```elixir
# Before
execute_while_loop(cond, body, context, session_id, accumulated_output \\ %{})

# After  
def execute_while_loop(condition, body, stack, session_id) do
  stack = FrameStack.push_frame(stack, :loop, :accumulate)
  
  stack = while_iteration(condition, body, stack, session_id)
  
  {stack, output} = FrameStack.pop_frame(stack)
  # Apply output to parent frame based on parent's mode
  FrameStack.add_output(stack, output.stdout, output.stderr)
end
```

## Implementation Strategy with Commit Points

### Phase 1: Create Frame Stack Foundation
**Goal**: Build and test the frame stack infrastructure without changing runtime execution

#### Commit 1.1: Create Frame module
**Files**: `lib/r_shell/runtime/frame.ex`
```elixir
defmodule RShell.Runtime.Frame do
  @moduledoc """
  Represents an execution frame with scope, output mode, and metadata.
  """
  
  @type frame_type :: :global | :loop | :function | :subshell | :command_substitution
  @type output_mode :: :isolate | :accumulate | :pipe | :capture
  
  defstruct [
    type: :global,
    output_mode: :isolate,
    scope: %{},
    accumulated: %{stdout: [], stderr: []},
    metadata: %{},
    parent_scope: nil
  ]
  
  @spec new(frame_type(), output_mode(), map()) :: t()
  def new(type, output_mode, metadata \\ %{}) do
    %__MODULE__{
      type: type,
      output_mode: output_mode,
      metadata: metadata,
      scope: %{},
      accumulated: %{stdout: [], stderr: []}
    }
  end
end
```

**Tests**: `test/unit/runtime/frame_test.exs`
```elixir
defmodule RShell.Runtime.FrameTest do
  use ExUnit.Case, async: true
  alias RShell.Runtime.Frame
  
  test "creates frame with defaults" do
    frame = Frame.new(:global, :isolate)
    assert frame.type == :global
    assert frame.output_mode == :isolate
    assert frame.scope == %{}
  end
  
  test "creates frame with metadata" do
    frame = Frame.new(:loop, :accumulate, %{iteration: 0})
    assert frame.metadata.iteration == 0
  end
end
```

**Commit Message**: 
```
feat(runtime): add Frame struct for execution contexts

- Define frame types: global, loop, function, subshell, command_substitution
- Define output modes: isolate, accumulate, pipe, capture
- Frame holds scope, accumulated output, and metadata
- Add unit tests for frame creation
```

#### Commit 1.2: Create FrameStack module with basic operations
**Files**: `lib/r_shell/runtime/frame_stack.ex`
```elixir
defmodule RShell.Runtime.FrameStack do
  @moduledoc """
  Manages a stack of execution frames with variable scoping and output handling.
  """
  
  alias RShell.Runtime.Frame
  
  defstruct [
    frames: [],           # Stack of Frame.t()
    global_context: %{}   # Shared global state (env, cwd, exit_code, command_count)
  ]
  
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    output_mode = Keyword.get(opts, :output_mode, :isolate)
    context = Keyword.get(opts, :context, %{
      env: %{},
      cwd: "/",
      exit_code: 0,
      command_count: 0
    })
    
    # Start with a global frame
    global_frame = Frame.new(:global, output_mode)
    
    %__MODULE__{
      frames: [global_frame],
      global_context: context
    }
  end
  
  @spec push_frame(t(), Frame.frame_type(), Frame.output_mode(), map()) :: t()
  def push_frame(%__MODULE__{frames: frames} = stack, type, output_mode, metadata \\ %{}) do
    new_frame = Frame.new(type, output_mode, metadata)
    %{stack | frames: [new_frame | frames]}
  end
  
  @spec pop_frame(t()) :: {t(), map()}
  def pop_frame(%__MODULE__{frames: [current | rest]} = stack) do
    # Return stack without current frame and the accumulated output
    {%{stack | frames: rest}, current.accumulated}
  end
  
  @spec current_frame(t()) :: Frame.t()
  def current_frame(%__MODULE__{frames: [current | _]}), do: current
  
  @spec output_mode(t()) :: Frame.output_mode()
  def output_mode(stack) do
    current_frame(stack).output_mode
  end
end
```

**Tests**: `test/unit/runtime/frame_stack_test.exs`
```elixir
defmodule RShell.Runtime.FrameStackTest do
  use ExUnit.Case, async: true
  alias RShell.Runtime.FrameStack
  
  test "initializes with global frame" do
    stack = FrameStack.new()
    assert length(stack.frames) == 1
    frame = FrameStack.current_frame(stack)
    assert frame.type == :global
    assert frame.output_mode == :isolate
  end
  
  test "pushes and pops frames" do
    stack = FrameStack.new()
    stack = FrameStack.push_frame(stack, :loop, :accumulate)
    
    assert length(stack.frames) == 2
    assert FrameStack.current_frame(stack).type == :loop
    
    {stack, _output} = FrameStack.pop_frame(stack)
    assert length(stack.frames) == 1
    assert FrameStack.current_frame(stack).type == :global
  end
  
  test "returns accumulated output on pop" do
    stack = FrameStack.new()
    stack = FrameStack.push_frame(stack, :loop, :accumulate)
    
    # Simulate adding output (will be implemented in commit 1.3)
    # For now, just test the structure
    {_stack, output} = FrameStack.pop_frame(stack)
    assert output == %{stdout: [], stderr: []}
  end
end
```

**Commit Message**:
```
feat(runtime): add FrameStack with push/pop operations

- Initialize with global frame
- Push new frames onto stack
- Pop frames and return accumulated output
- Track global context (env, cwd, exit_code, command_count)
- Add unit tests for stack operations
```

#### Commit 1.3: Add variable operations with scope chain
**Files**: Update `lib/r_shell/runtime/frame_stack.ex`
```elixir
# Add to FrameStack module:

@spec get_variable(t(), String.t()) :: term()
def get_variable(%__MODULE__{frames: frames, global_context: context}, name) do
  # Search frames from top to bottom (current -> parent -> ... -> global)
  Enum.find_value(frames, fn frame ->
    Map.get(frame.scope, name)
  end) || Map.get(context.env || %{}, name)
end

@spec set_variable(t(), String.t(), term()) :: t()
def set_variable(%__MODULE__{frames: [current | rest]} = stack, name, value) do
  # Set in current frame's scope
  new_scope = Map.put(current.scope, name, value)
  updated_frame = %{current | scope: new_scope}
  %{stack | frames: [updated_frame | rest]}
end

@spec update_global_env(t(), String.t(), term()) :: t()
def update_global_env(%__MODULE__{global_context: context} = stack, name, value) do
  new_env = Map.put(context.env || %{}, name, value)
  %{stack | global_context: %{context | env: new_env}}
end
```

**Tests**: Update `test/unit/runtime/frame_stack_test.exs`
```elixir
test "sets and gets variables in current frame" do
  stack = FrameStack.new()
  stack = FrameStack.set_variable(stack, "X", 42)
  
  assert FrameStack.get_variable(stack, "X") == 42
end

test "variable shadowing works across frames" do
  stack = FrameStack.new()
  stack = FrameStack.update_global_env(stack, "X", 10)
  
  # Push new frame and shadow X
  stack = FrameStack.push_frame(stack, :loop, :accumulate)
  stack = FrameStack.set_variable(stack, "X", 20)
  
  # Current frame sees shadowed value
  assert FrameStack.get_variable(stack, "X") == 20
  
  # Pop frame - back to global value
  {stack, _output} = FrameStack.pop_frame(stack)
  assert FrameStack.get_variable(stack, "X") == 10
end

test "looks up variables in parent frames" do
  stack = FrameStack.new()
  stack = FrameStack.update_global_env(stack, "GLOBAL", "value")
  
  stack = FrameStack.push_frame(stack, :loop, :accumulate)
  stack = FrameStack.set_variable(stack, "LOCAL", "local_value")
  
  # Can see both local and global
  assert FrameStack.get_variable(stack, "LOCAL") == "local_value"
  assert FrameStack.get_variable(stack, "GLOBAL") == "value"
end
```

**Commit Message**:
```
feat(runtime): add variable scoping to FrameStack

- Implement get_variable with scope chain lookup
- Implement set_variable in current frame
- Support variable shadowing across frames
- Add update_global_env for global variables
- Add comprehensive tests for scoping behavior
```

#### Commit 1.4: Add output accumulation operations
**Files**: Update `lib/r_shell/runtime/frame_stack.ex`
```elixir
# Add to FrameStack module:

@spec add_output(t(), list(), list()) :: t()
def add_output(%__MODULE__{frames: [current | rest]} = stack, stdout, stderr) do
  case current.output_mode do
    :isolate ->
      # Replace output (clear previous)
      updated_frame = %{current | accumulated: %{stdout: stdout, stderr: stderr}}
      %{stack | frames: [updated_frame | rest]}
    
    :accumulate ->
      # Append to existing output
      new_accumulated = %{
        stdout: current.accumulated.stdout ++ stdout,
        stderr: current.accumulated.stderr ++ stderr
      }
      updated_frame = %{current | accumulated: new_accumulated}
      %{stack | frames: [updated_frame | rest]}
    
    _ ->
      # Other modes TBD (pipe, capture)
      stack
  end
end

@spec clear_output(t()) :: t()
def clear_output(%__MODULE__{frames: [current | rest]} = stack) do
  updated_frame = %{current | accumulated: %{stdout: [], stderr: []}}
  %{stack | frames: [updated_frame | rest]}
end

@spec get_output(t()) :: map()
def get_output(%__MODULE__{frames: [current | _]}) do
  current.accumulated
end
```

**Tests**: Update `test/unit/runtime/frame_stack_test.exs`
```elixir
test "isolate mode replaces output" do
  stack = FrameStack.new(output_mode: :isolate)
  
  stack = FrameStack.add_output(stack, ["first\n"], [])
  assert FrameStack.get_output(stack) == %{stdout: ["first\n"], stderr: []}
  
  stack = FrameStack.add_output(stack, ["second\n"], [])
  assert FrameStack.get_output(stack) == %{stdout: ["second\n"], stderr: []}
end

test "accumulate mode appends output" do
  stack = FrameStack.new()
  stack = FrameStack.push_frame(stack, :loop, :accumulate)
  
  stack = FrameStack.add_output(stack, ["first\n"], [])
  stack = FrameStack.add_output(stack, ["second\n"], [])
  
  output = FrameStack.get_output(stack)
  assert output == %{stdout: ["first\n", "second\n"], stderr: []}
end

test "clear_output empties accumulated output" do
  stack = FrameStack.new()
  stack = FrameStack.add_output(stack, ["test\n"], [])
  stack = FrameStack.clear_output(stack)
  
  assert FrameStack.get_output(stack) == %{stdout: [], stderr: []}
end
```

**Commit Message**:
```
feat(runtime): add output accumulation to FrameStack

- Implement add_output with mode-specific behavior
  - :isolate mode replaces previous output
  - :accumulate mode appends to existing output
- Add clear_output and get_output helpers
- Add tests for both output modes
```

**Phase 1 Complete**: All FrameStack infrastructure tested and working independently.

---

### Phase 2: Parallel Implementation (Adapter Pattern)
**Goal**: Add FrameStack support to Runtime WITHOUT breaking existing code

#### Commit 2.1: Add FrameStack adapter to Runtime state
**Files**: Update `lib/r_shell/runtime.ex`
```elixir
# In init/1 callback, add:
alias RShell.Runtime.FrameStack

context = %{
  env: env,
  env_meta: %{},
  cwd: cwd,
  exit_code: 0,
  command_count: 0,
  last_output: %{stdout: [], stderr: []}
}

# NEW: Initialize frame stack alongside existing context
frame_stack = FrameStack.new(
  output_mode: :isolate,
  context: context
)

{:ok, %{
  session_id: session_id,
  context: context,              # Keep existing
  frame_stack: frame_stack,      # Add new
  initial_env: env,
  initial_cwd: cwd,
  use_frames: false              # Feature flag!
}}
```

**Tests**: Update existing runtime tests to verify no breakage
```elixir
test "runtime initializes with frame stack" do
  {:ok, state} = Runtime.init(session_id: "test", env: %{}, cwd: "/")
  
  # Old context still works
  assert state.context.cwd == "/"
  
  # New frame stack exists
  assert state.frame_stack != nil
  assert length(state.frame_stack.frames) == 1
end
```

**Commit Message**:
```
feat(runtime): add FrameStack to Runtime state (parallel mode)

- Initialize FrameStack alongside existing context
- Add use_frames feature flag (default: false)
- Keep existing context-based code working
- Verify no regression in existing tests
```

#### Commit 2.2: Add frame-based variable operations
**Files**: Update `lib/r_shell/runtime.ex`
```elixir
# Add new functions (don't change existing ones):

defp get_variable_from_frames(state, name) do
  FrameStack.get_variable(state.frame_stack, name)
end

defp set_variable_in_frames(state, name, value) do
  new_stack = FrameStack.update_global_env(state.frame_stack, name, value)
  %{state | frame_stack: new_stack}
end

# Update execute_rshell_assignment to support both modes:
defp execute_rshell_assignment(%Types.Assignment{name: name_node, value: value_node}, context, session_id) do
  var_name = case name_node do
    %Types.Identifier{source_info: %{text: text}} -> text
    %{source_info: %{text: text}} -> text
    _ -> ""
  end
  
  native_value = ExprEvaluator.evaluate(value_node, context)
  
  # Update environment with native value
  new_env = Map.put(context.env, var_name, native_value)
  
  # Broadcast variable_set event
  PubSub.broadcast(session_id, :context, {:variable_set, %{
    name: var_name,
    value: native_value
  }})
  
  # Assignments produce NO output
  %{context | env: new_env, last_output: %{stdout: [], stderr: []}}
end
```

**Commit Message**:
```
feat(runtime): add frame-based variable operations (parallel mode)

- Add get_variable_from_frames helper
- Add set_variable_in_frames helper
- Keep existing context-based assignment working
- Prepare for future frame-based execution
```

#### Commit 2.3: Create frame-based execute_command_list
**Files**: Update `lib/r_shell/runtime.ex`
```elixir
# Add new version alongside existing execute_command_list:

defp execute_command_list_with_frames(nodes, frame_stack, session_id) when is_list(nodes) do
  output_mode = FrameStack.output_mode(frame_stack)
  
  Enum.reduce(nodes, frame_stack, fn node, acc_stack ->\
    start_time = System.monotonic_time(:microsecond)
    
    try do
      # Execute node with frame stack
      new_stack = simple_execute_with_frames(node, acc_stack, session_id)
      duration = System.monotonic_time(:microsecond) - start_time
      
      # Get output from current frame
      output = FrameStack.get_output(new_stack)
      
      # Broadcast execution result
      broadcast_execution_success_with_output(
        node,
        FrameStack.current_frame(new_stack),
        acc_stack,
        duration,
        output.stdout,
        output.stderr,
        session_id
      )
      
      # Clear output if in isolate mode
      if output_mode == :isolate do
        FrameStack.clear_output(new_stack)
      else
        new_stack
      end
    rescue
      e ->
        # Error handling (similar to existing)
        acc_stack
    end
  end)
end

# Keep existing execute_command_list for compatibility
```

**Tests**: Add parallel tests (don't change existing ones)
```elixir
# test/unit/runtime/frame_execution_test.exs
defmodule RShell.Runtime.FrameExecutionTest do
  use ExUnit.Case, async: true
  
  # Tests for frame-based execution
  # Without breaking existing tests
end
```

**Commit Message**:
```
feat(runtime): add frame-based execute_command_list (parallel mode)

- Create execute_command_list_with_frames alongside existing
- Respect output_mode from current frame
- Clear output after each command in isolate mode
- Keep accumulating output in accumulate mode
- Add parallel test suite for frame execution
```

**Phase 2 Complete**: FrameStack fully integrated in parallel mode, all existing tests pass.

---

### Phase 3: Migrate Control Flow (Feature Flag Enabled)
**Goal**: Switch while/for/if to use frames, enable with feature flag

#### Commit 3.1: Migrate while loop to frames
**Files**: Update `lib/r_shell/runtime.ex`
```elixir
# Replace execute_while_loop:
defp execute_while_loop(condition_node, body_node, context, session_id, accumulated_output \\ %{stdout: [], stderr: []}) do
  # NEW: Check feature flag
  state = %{context: context, frame_stack: /* get from somewhere */, use_frames: true}
  
  if state.use_frames do
    execute_while_loop_with_frames(condition_node, body_node, state, session_id)
  else
    # Keep old implementation for now
    execute_while_loop_legacy(condition_node, body_node, context, session_id, accumulated_output)
  end
end

defp execute_while_loop_with_frames(condition_node, body_node, state, session_id) do
  # Push loop frame
  frame_stack = FrameStack.push_frame(state.frame_stack, :loop, :accumulate, %{type: :while})
  
  # Recursive loop with frames
  final_stack = while_iteration_with_frames(condition_node, body_node, frame_stack, session_id)
  
  # Pop frame and get accumulated output
  {popped_stack, output} = FrameStack.pop_frame(final_stack)
  
  # Add output to parent frame
  new_stack = FrameStack.add_output(popped_stack, output.stdout, output.stderr)
  
  # Update context from frame stack
  %{state.context | 
    env: new_stack.global_context.env,
    last_output: output
  }
end
```

**Tests**: Add feature flag tests
```elixir
@tag :use_frames
test "while loop with frames accumulates output correctly" do
  script = """
  X = 0
  while (X < 3) {
    echo $X
    X = X + 1
  }
  """
  
  state = assert_cli_success(script, use_frames: true)
  outputs = Enum.flat_map(state.history, & &1.stdout)
  assert Enum.any?(outputs, &(&1 =~ "0"))
  assert Enum.any?(outputs, &(&1 =~ "1"))
  assert Enum.any?(outputs, &(&1 =~ "2"))
end
```

**Commit Message**:
```
feat(runtime): migrate while loop to use frames (feature flag)

- Add execute_while_loop_with_frames
- Keep legacy implementation for compatibility
- Use feature flag to switch implementations
- Add @tag :use_frames tests
- Verify output accumulation works correctly
```

#### Commit 3.2: Migrate for loop to frames
**Files**: Similar pattern to 3.1

**Commit Message**:
```
feat(runtime): migrate for loop to use frames (feature flag)

- Add execute_for_statement_with_frames
- Support variable scoping in loop iterations
- Accumulate output across all iterations
- Add @tag :use_frames tests
```

#### Commit 3.3: Migrate if statement to frames
**Files**: Similar pattern to 3.1

**Commit Message**:
```
feat(runtime): migrate if statement to use frames (feature flag)

- Add execute_if_statement_with_frames
- Support elif/else branches with frames
- Add @tag :use_frames tests
```

**Phase 3 Complete**: All control flow working with frames behind feature flag.

---

### Phase 4: Hard Cutover
**Goal**: Remove feature flag, delete old code, make frames the default

#### Commit 4.1: Enable frames by default
**Files**: Update `lib/r_shell/runtime.ex`
```elixir
# In init/1:
{:ok, %{
  session_id: session_id,
  context: context,
  frame_stack: frame_stack,
  initial_env: env,
  initial_cwd: cwd,
  use_frames: true  # Changed from false!
}}
```

**Run all tests, verify pass rate stays at 98.9%+**

**Commit Message**:
```
feat(runtime): enable frame stack by default

- Change use_frames default to true
- Run full test suite (expect 374/378 passing)
- Keep legacy code for one more commit (safety)
```

#### Commit 4.2: Remove legacy code and feature flag
**Files**: Update `lib/r_shell/runtime.ex`
```elixir
# Remove:
# - execute_while_loop_legacy
# - execute_for_statement_legacy  
# - execute_if_statement_legacy
# - execute_command_list (old version)
# - use_frames flag from state

# Rename:
# - execute_while_loop_with_frames -> execute_while_loop
# - execute_for_statement_with_frames -> execute_for_statement
# - execute_if_statement_with_frames -> execute_if_statement
```

**Commit Message**:
```
refactor(runtime): remove legacy execution code

- Delete execute_*_legacy functions
- Remove use_frames feature flag
- Rename execute_*_with_frames to standard names
- FrameStack is now the only execution model
- All tests passing (374/378 = 98.9%)
```

#### Commit 4.3: Update documentation
**Files**: 
- Update `EXECUTION_FRAME_DESIGN.md` (mark as IMPLEMENTED)
- Update `RUNTIME_DESIGN.md` with frame stack details
- Update code comments

**Commit Message**:
```
docs(runtime): update documentation for frame stack

- Mark EXECUTION_FRAME_DESIGN.md as implemented
- Add frame stack details to RUNTIME_DESIGN.md
- Update inline code comments
- Remove references to accumulate parameter
```

**Phase 4 Complete**: FrameStack is the one true execution model.

---

## Output Mode Behavior

### `:isolate` (Interactive/Global)
- Each command **clears** accumulated output before executing
- Assignments clear output
- Used for: Top-level commands, interactive mode

### `:accumulate` (Loops/Blocks)
- Commands **append** to accumulated output
- Assignments **do not clear** output
- Used for: while, for, if blocks

### `:pipe` (Future - Pipelines)
- Output from one command becomes input to next
- Used for: `cmd1 | cmd2 | cmd3`

### `:capture` (Future - Substitution)
- Collect all output, return as string
- Used for: `X = $(ls)`, `echo $(date)`

## Testing Strategy

### Phase 1 Tests (Unit - FrameStack only)
- Frame creation and properties
- Stack push/pop operations
- Variable scoping and shadowing
- Output accumulation in both modes

### Phase 2 Tests (Integration - Parallel mode)
- Runtime initializes with frame stack
- Variables work in both old and new mode
- No regression in existing tests

### Phase 3 Tests (Integration - Feature flagged)
- Control flow with `@tag :use_frames`
- Output accumulation in loops
- Variable scoping in nested structures

### Phase 4 Tests (All existing tests)
- Run full suite without feature flag
- Verify 374/378 tests passing (98.9%)
- No new failures introduced

## Expression Evaluation vs Execution Stack

**Important**: Expression evaluation and execution frames are **different stacks** with different purposes!

### Expression Stack (Already Exists)
The `ExprEvaluator` module uses a **value stack** for computing expressions:

```elixir
# Expression: 2 + (3 + (5 / 2) + 3 ) * 2
# This is tree-walking evaluation with implicit stack:

evaluate(BinaryOp{op: :+, left: 2, right: ...}) do
  left_val = evaluate(2)                    # => 2
  right_val = evaluate(                     # Recursive call
    BinaryOp{op: :*, left: ..., right: 2}
  )
  left_val + right_val
end

# The call stack IS the value stack
# Nested expressions create nested evaluate() calls
# When a call returns, its value is used by the parent
```

### Execution Stack (This Design)
The execution frame stack manages:
- **Variable scopes**: Where to find `ex` when evaluating
- **Output handling**: What to do with `echo` results
- **Control flow state**: Loop counters, function args

### How They Work Together

```elixir
# Example: Evaluating an expression in a while loop

# Execution Stack:
# [Global Frame, Loop Frame]

# In loop body: X = 2 + (Y * 3)

1. Assignment calls ExprEvaluator.evaluate(BinaryOp{...})
2. ExprEvaluator needs value of Y
3. ExprEvaluator calls FrameStack.get_variable(stack, "Y")
4. FrameStack searches: Loop Frame scope -> Global Frame scope
5. Returns Y's value to ExprEvaluator
6. ExprEvaluator computes: 2 + (5 * 3) = 17
7. Assignment calls FrameStack.set_variable(stack, "X", 17)
8. FrameStack stores X in current frame (Loop Frame)
```

## Commit Point Summary

### Phase 1: Foundation (4 commits, ~4 hours)
1. ✅ Create Frame module
2. ✅ Create FrameStack with push/pop
3. ✅ Add variable scoping
4. ✅ Add output accumulation

### Phase 2: Integration (3 commits, ~4 hours)
1. ✅ Add FrameStack to Runtime state
2. ✅ Add frame-based variable operations
3. ✅ Create frame-based execute_command_list

### Phase 3: Migration (3 commits, ~6 hours)
1. ✅ Migrate while loop to frames
2. ✅ Migrate for loop to frames
3. ✅ Migrate if statement to frames

### Phase 4: Cutover (3 commits, ~4 hours)
1. ✅ Enable frames by default
2. ✅ Remove legacy code
3. ✅ Update documentation

**Total: 13 commits, ~18 hours estimated**

Each commit point is:
- **Atomic**: Single, well-defined change
- **Tested**: Unit or integration tests included
- **Safe**: No breaking changes until Phase 4
- **Reversible**: Can roll back to any commit

---

## ACTUAL IMPLEMENTATION NOTES (2025-11-23)

### Reality Check: Threading State is Hard

The original design assumed we could thread `{context, frame_stack}` through all execution functions. This is impractical because:

1. **80+ function calls** would need signature changes
2. **Pattern matching everywhere** on `{context, frame_stack}` tuples
3. **Breaking change** to all existing execution code

### Pragmatic Alternative: Keep Frame Stack in GenServer State

**Better approach**: Keep frame stack in Runtime GenServer state alongside context:
- `state.context` - Current execution context (env, cwd, exit_code, last_output)
- `state.frame_stack` - Frame stack for scope/output management (PARALLEL)

**Execution model**:
```elixir
# Current (context only):
new_context = execute_while_loop(condition, body, context, session_id)

# After frame migration:
# Still returns context, but ALSO updates frame_stack in GenServer state
new_context = execute_while_loop(condition, body, context, session_id)
# Internally: get frame_stack from process state, use it, update it
```

### Revised Implementation (Pragmatic Hard Cutover)

**Phase 1-2: DONE** (6 commits)
- ✅ Frame and FrameStack modules (30 tests)
- ✅ Integration into Runtime state
- ✅ While loop refactoring

**Phase 3: Simplify Output Accumulation** (Current)
- Goal: Remove `accumulate` parameter without full frame migration
- Keep context-based execution
- Frame stack stays dormant but ready

**Future: When needed for functions/subshells**
- Use frame stack for LOCAL SCOPES only
- Keep context for global state
- Hybrid model: best of both worlds
