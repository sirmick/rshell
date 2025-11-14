# RShell Runtime Design

**Last Updated**: 2025-11-14

---

## Overview

The Runtime is a GenServer that executes parsed bash AST nodes while maintaining execution context (environment variables, working directory). It subscribes to the Parser's `:executable` PubSub topic and can execute nodes automatically or on-demand.

**Implementation Status**:
- ✅ Builtin commands (echo, env, export, printenv, cd, pwd, true, false, man, test)
- ✅ Control flow execution (if/elif/else, for, while)
- ✅ Variable expansion in arguments ($VAR with bracket notation)
- ✅ Bracket notation for nested data access ($VAR["key"], $VAR[0])
- ✅ Execution pipeline architecture (via ExecutionPipeline module)
- ✅ JSONPath support for nested access (using warpath library)
- ⏳ Variable assignments (direct assignment: A=value)
- ⏳ Pipelines, redirects, external command execution

---

## Implementation

### State Structure

```elixir
%{
  session_id: String.t(),      # PubSub topic identifier
  context: %{
    env: %{String.t() => any()},       # Environment variables (any Elixir term)
    cwd: String.t(),                    # Current working directory
    exit_code: integer(),               # Last exit code
    command_count: integer(),           # Number of executed commands
    output: [any()],                   # Accumulated output (can be streams)
    errors: [String.t()]               # Accumulated error lines
  },
  auto_execute: boolean()      # Auto-execute on {:executable_node, ...}
}
```

### Event Flow

```
Parser (IncrementalParser)
    ↓
PubSub :executable topic → {:executable_node, node, count}
    ↓
Runtime (if auto_execute: true)
    ↓
execute_node_internal(node, context, session_id)
    ↓
1. Broadcast {:execution_started, ...} to :runtime topic
2. Pattern match on typed struct (Types.Command, Types.IfStatement, etc.)
3. Execute based on node type and mode
4. Update context (env, output, exit_code, command_count)
5. Broadcast {:execution_completed, ...} to :runtime topic
6. Broadcast output to :output topic
7. Broadcast context changes to :context topic
```

### PubSub Topics & Events

**Subscribes to:**
- `session:#{id}:executable` - Receives executable nodes from Parser
  - `{:executable_node, node, count}` - Node ready to execute

**Broadcasts to:**

#### Topic: `:runtime` (Execution Lifecycle)
- `{:execution_started, %{node: node, timestamp: DateTime.t()}}`
  - **When**: Before executing any AST node
  - **Always broadcast**: ✅ Yes
  
- `{:execution_completed, %{node: node, exit_code: int, duration_us: int, timestamp: DateTime.t()}}`
  - **When**: After successful execution
  - **Always broadcast**: ✅ Yes
  
- `{:execution_failed, %{reason: String.t(), message: String.t(), node_type: String.t(), timestamp: DateTime.t()}}`
  - **When**: On execution error (both sync and async)
  - **Always broadcast**: ✅ Yes (fixed in refactoring)
  - **Includes**: Error details, node type, optional stacktrace

#### Topic: `:output` (Command Output)
- `{:stdout, String.t()}`
  - **When**: Builtin command produces stdout
  - **Always broadcast**: ✅ Yes (if non-empty)
  
- `{:stderr, String.t()}`
  - **When**: Builtin command produces stderr
  - **Always broadcast**: ✅ Yes (if non-empty)

#### Topic: `:context` (State Changes)
- `{:cwd_changed, %{old: String.t(), new: String.t()}}`
  - **When**: Working directory changes via `set_cwd/2`
  - **Always broadcast**: ✅ Yes
  
- `{:env_changed, %{operation: atom(), name: String.t(), value: any(), old_value: any(), timestamp: DateTime.t()}}`
  - **When**: Environment variable modified
  - **Status**: ⏳ Planned (not yet implemented)
  - **Operations**: `:set`, `:unset`

---

## API

### Starting the Runtime

```elixir
{:ok, runtime} = Runtime.start_link(
  session_id: "my_session",
  auto_execute: true,       # Auto-execute executable nodes
  env: System.get_env(),    # Optional: custom env
  cwd: "/home/user"         # Optional: custom cwd
)
```

### Manual Execution

```elixir
# Execute a typed AST node
{:ok, result} = Runtime.execute_node(runtime, %Types.Command{...})
```

### Context Queries

```elixir
# Get full context
context = Runtime.get_context(runtime)

# Get specific values
value = Runtime.get_variable(runtime, "PATH")
cwd = Runtime.get_cwd(runtime)
```

### Context Mutations

```elixir
# Change working directory (updates context only, doesn't affect file system)
:ok = Runtime.set_cwd(runtime, "/tmp")
```

---

## Builtin Commands

The Runtime executes builtin commands (implemented in Elixir) directly:

**Implementation**: Native Elixir functions in `RShell.Builtins`

**Current Builtins** (9 implemented):
- `echo` - Output text with flag support (-n, -e, -E) and rich type conversion
- `env` - Unified environment variable management with JSON support
- `export` - Export variables with -n (unset) flag
- `printenv` - Print environment variables with -0 (null separator) flag
- `cd` - Change working directory with -L/-P flags
- `pwd` - Print working directory
- `true` - Return success (exit code 0)
- `false` - Return failure (exit code 1)
- `man` - Display builtin help with -a (list all) flag
- `test` - Evaluate conditional expressions (string, numeric, type checks)

**Behavior**:
- Execute immediately within the Runtime process
- Have access to full context (env, cwd, etc.)
- Can modify context (env, cd, etc.)
- Return results synchronously
- Support rich data types (maps, lists) via RShell.EnvJSON

### External Commands

**Status**: Not yet implemented

**Future Implementation**: Will execute via Erlang ports
- Spawn child processes
- Handle stdin/stdout/stderr streams
- Pass exported environment variables to children

---

## Node Type Support

The runtime pattern matches on typed AST structs:

### Fully Implemented

**`Types.Command`** - Simple commands
- Executes builtin commands directly
- Tracks command count
- Broadcasts execution events

**`Types.IfStatement`** - If/elif/else chains ✅
- Executes condition commands
- Branches based on exit code
- Supports nested structures

**`Types.ForStatement`** - For loops ✅
- Iterates over values (explicit or from variable expansion)
- Supports native type iteration (lists, maps)
- Loop variable persists after completion

**`Types.WhileStatement`** - While loops ✅
- Executes condition, checks exit code
- Loops until condition fails
- Supports nested structures

**`Types.VariableAssignment`** - Direct assignments ⏳
- `VAR=value` syntax
- Will support JSON parsing for rich types
- Currently not implemented

**`Types.DeclarationCommand`** - Export/declare statements ⏳
- `export VAR=value`, `readonly VAR=value`
- Currently not implemented
- Will support variable attributes (readonly, exported)

### Detection Only (Placeholder)

These node types are recognized but not yet executed:

- `Types.Pipeline` - Command pipelines (`cmd1 | cmd2`)
- `Types.List` - Command lists (`cmd1 && cmd2`, `cmd1 || cmd2`)
- `Types.CaseStatement` - Case/switch statements
- `Types.FunctionDefinition` - Function definitions

---

## Design Rationale

### Pattern Matching on Typed Structs

**Typed approach:**
```elixir
case node do
  %Types.Command{} -> execute_command(node, context)
  %Types.IfStatement{} -> execute_if(node, context)
end
```

**Benefits:**
- Compile-time type checking
- IDE autocomplete and navigation
- Safer refactoring
- Faster pattern matching

### Separate Parser and Runtime GenServers

| Benefit | Description |
|---------|-------------|
| Separation of Concerns | Parser parses, Runtime executes |
| Independent Testing | Test components in isolation |
| Flexibility | Parse-only or execute-only modes |
| Fault Tolerance | Crashes don't cascade |
| Concurrency | Parse next input during execution |

### PubSub Communication

- **Loose Coupling**: No direct references needed
- **Observable**: Any component can subscribe
- **Extensible**: Easy to add CLI, LSP, debugger
- **Session Isolation**: Multiple sessions independent

---

## Testing

### Unit Tests (`test/runtime_test.exs`)

Tests runtime GenServer in isolation:
- Context initialization and state
- Variable get/set operations
- CWD get/set operations
- Event broadcasting correctness
- Auto-execute vs manual execution
- Builtin command execution

### Integration Tests (`test/parser_runtime_integration_test.exs`)

Tests parser → runtime integration:
- End-to-end parse and execute flow
- Auto-execution triggered by parser events
- Context persistence across multiple commands
- Incomplete structures (no execution until complete)
- Parser reset behavior (runtime context persists)

---

## Performance

### Current Characteristics
- **Memory**: ~155 KB per runtime instance (estimated)
- **Overhead**: GenServer calls ~6μs, PubSub ~2μs (negligible)
- **Native Type Support**: Environment variables can hold any Elixir term

---

## Summary

The Runtime provides:
- ✅ GenServer architecture with PubSub events
- ✅ Context management (env, cwd, output, exit codes)
- ✅ Observable execution lifecycle
- ✅ Pattern matching on strongly-typed AST
- ✅ Auto-execute and manual modes
- ✅ Multiple builtin commands (echo, env, export, cd, pwd, etc.)
- ✅ Variable expansion in arguments ($VAR with context)
- ✅ Control flow execution (if/elif/else, for, while)
- ✅ Native type support in environment variables
- ✅ JSON parsing for rich data structures

**Current Limitations**:
- No external command execution yet
- No variable assignment via AST (VariableAssignment, DeclarationCommand)
- No pipeline execution between commands
- No redirects (>, <, >>, 2>&1, etc.)
- No function definitions or local scope

**Recent Improvements** (2025-11-14):
- ✅ Refactored to use warpath library for JSONPath queries
- ✅ Created ExecutionPipeline module for clean execution flow
- ✅ Removed process dictionary, now fully functional
- ✅ Unified error broadcasting (sync and async paths)
- ✅ Added `last_output` field to context structure
- ✅ Reduced code by ~70 lines while improving maintainability

**Next Steps**:
- Implement VariableAssignment node handling (direct assignment: A=value)
- Implement DeclarationCommand node handling (export, readonly)
- Add variable attribute tracking (readonly, exported, local)
- Implement `env_changed` event broadcasting
- Implement pipeline execution
- Add redirect support
- Implement external command execution via ports
- Add function definitions and local scope