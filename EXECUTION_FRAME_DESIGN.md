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

## Implementation Strategy

### Phase 1: Create Frame Stack Module
- Implement `RShell.Runtime.Frame`
- Implement `RShell.Runtime.FrameStack`
- Unit tests for frame operations

### Phase 2: Migrate Command Execution
- Update `execute_command` to use stack
- Update `execute_assignment` to respect output_mode
- Update builtins to receive/return stack

### Phase 3: Migrate Control Flow
- Update `execute_while_loop` to use frames
- Update `execute_for_loop` to use frames
- Update `execute_if_statement` to use frames

### Phase 4: Update Tests
- Ensure all existing tests still pass
- Add new tests for frame-specific behavior

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

## Migration Path

1. Keep existing runtime working
2. Build frame stack in parallel
3. Add feature flag to switch implementations
4. Migrate tests incrementally
5. Remove old implementation once stable

## Questions to Consider

1. **Global context**: Should `cwd`, `exit_code`, `command_count` be in frames or stay global?
   - **Answer**: Global state like cwd should be in the stack itself, not frames
   - Frames handle scoping and output, stack handles global execution state

2. **Variable shadowing**: How do we handle local variables in functions?
   - **Answer**: Each frame has a `parent_scope` reference for lookups
   - Set always sets in current frame, get searches up the chain

3. **Broadcasting**: When do we broadcast execution results?
   - **Answer**: Still broadcast at the command level (like now)
   - Frames are internal implementation detail

4. **Error handling**: How do frames interact with exceptions?
   - **Answer**: Errors should pop frames during unwinding
   - Could use `try/catch` with cleanup in `after` to ensure frames are popped

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

For complex lookups like `ex[2].d[4]['yo']`:
```elixir
# AST: MemberAccess{
#   base: IndexAccess{
#     base: MemberAccess{
#       base: IndexAccess{base: Identifier("ex"), index: 2},
#       member: "d"
#     },
#     index: 4
#   },
#   member: "yo"
# }

# Evaluation (post-order traversal):
1. evaluate(Identifier("ex")) => lookup variable "ex" in EXECUTION stack
2. evaluate(IndexAccess{ex, 2}) => ex[2]
3. evaluate(MemberAccess{ex[2], "d"}) => ex[2].d
4. evaluate(IndexAccess{ex[2].d, 4}) => ex[2].d[4]
5. evaluate(MemberAccess{ex[2].d[4], "yo"}) => ex[2].d[4]["yo"]
```

**Key Point**: Variable lookups (`Identifier("ex")`) query the **execution stack** to get values, but the expression evaluation itself uses the **call stack** (recursive evaluate calls).

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

### Stack Comparison

| Aspect | Expression Stack | Execution Stack |
|--------|-----------------|-----------------|
| **Purpose** | Compute values | Manage execution context |
| **Implemented as** | Call stack (recursion) | Explicit frame list |
| **Lifetime** | During single expression | Across multiple statements |
| **Contains** | Intermediate values | Variables, output, state |
| **Example** | `(2 + 3) * 4` | Loop iteration, function scope |

### Why Separate Stacks?

1. **Different lifecycles**:
   - Expression stack lives for microseconds (one calculation)
   - Execution frames live for statements/blocks

2. **Different data**:
   - Expression stack: Numbers, strings, intermediate results
   - Execution frames: Variable bindings, output buffers, metadata

3. **Clean separation**:
   - ExprEvaluator: Pure expression evaluation (no side effects)
   - FrameStack: Execution context and side effects (output, variables)

### Example: Full Picture

```elixir
# Code: while (i < 10) { sum = sum + (i * 2); i = i + 1 }

# Execution Stack State:
# [GlobalFrame{i: 0, sum: 0}, LoopFrame{output_mode: :accumulate}]

# Iteration 1:
# 1. Evaluate condition: i < 10
#    - ExprEvaluator.evaluate(BinaryOp{:lt, i, 10})
#    - Needs 'i' -> queries FrameStack.get_variable("i") -> 0
#    - Returns: true
#
# 2. Execute: sum = sum + (i * 2)
#    - ExprEvaluator.evaluate(BinaryOp{:+, sum, BinaryOp{:*, i, 2}})
#    - Needs 'sum' -> FrameStack.get_variable("sum") -> 0
#    - Needs 'i' -> FrameStack.get_variable("i") -> 0
#    - Computes: 0 + (0 * 2) = 0
#    - FrameStack.set_variable("sum", 0)
#
# 3. Execute: i = i + 1
#    - ExprEvaluator.evaluate(BinaryOp{:+, i, 1})
#    - Needs 'i' -> FrameStack.get_variable("i") -> 0
#    - Computes: 0 + 1 = 1
#    - FrameStack.set_variable("i", 1)
```

### Summary

- **Expression evaluation** = Tree-walking with call stack for intermediate values
- **Execution frames** = Explicit stack for variable scopes and execution context
- They interact: ExprEvaluator queries FrameStack for variable values
- They're independent: You can have deep expression nesting in a single frame