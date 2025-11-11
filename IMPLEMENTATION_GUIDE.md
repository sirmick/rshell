# RShell Runtime Implementation Guide

**Step-by-step instructions for implementing the Parser + Runtime architecture.**

See [ARCHITECTURE_DESIGN.md](ARCHITECTURE_DESIGN.md) for the complete design rationale.

---

## Overview

We're building an event-driven bash runtime with:
- **Parser GenServer**: Incremental parsing with PubSub events
- **Runtime GenServer**: Execution engine with context management
- **Phoenix.PubSub**: Event bus connecting components

**No Session/History GenServers** - Keep it simple. Add later if needed.

---

## Prerequisites

- Elixir 1.14+
- Rust toolchain (for NIF compilation)
- Existing RShell project with Phase 1 complete (incremental parser working)

---

## Phase 2: PubSub Infrastructure (2-3 hours)

**Goal**: Set up Phoenix.PubSub for event-driven communication.

### Step 2.1: Add Phoenix.PubSub Dependency

**File**: `mix.exs`

```elixir
defp deps do
  [
    {:rustler, "~> 0.30.0"},
    {:rustler_precompiled, "~> 0.7.0"},
    {:jason, "~> 1.4"},
    {:phoenix_pubsub, "~> 2.1"}  # ADD THIS LINE
  ]
end
```

**Run**:
```bash
mix deps.get
mix deps.compile
```

### Step 2.2: Create PubSub Module

**File**: `lib/r_shell/pubsub.ex`

```elixir
defmodule RShell.PubSub do
  @moduledoc """
  PubSub topic definitions and subscription helpers.
  
  ## Topics (per session)
  
  - `session:#{id}:ast` - AST updates from parser
  - `session:#{id}:executable` - Executable nodes ready
  - `session:#{id}:runtime` - Runtime execution events
  - `session:#{id}:output` - stdout/stderr
  - `session:#{id}:context` - Context changes (vars, cwd)
  """
  
  @pubsub_name :rshell_pubsub
  
  def pubsub_name, do: @pubsub_name
  
  # Topic generators
  def ast_topic(session_id), do: "session:#{session_id}:ast"
  def executable_topic(session_id), do: "session:#{session_id}:executable"
  def runtime_topic(session_id), do: "session:#{session_id}:runtime"
  def output_topic(session_id), do: "session:#{session_id}:output"
  def context_topic(session_id), do: "session:#{session_id}:context"
  
  @doc """
  Subscribe to specific topics for a session.
  
  ## Examples
  
      RShell.PubSub.subscribe("my_session", [:ast, :output])
      RShell.PubSub.subscribe("my_session", :all)
  """
  def subscribe(session_id, :all) do
    subscribe(session_id, [:ast, :executable, :runtime, :output, :context])
  end
  
  def subscribe(session_id, topic_atoms) when is_list(topic_atoms) do
    Enum.each(topic_atoms, fn atom ->
      topic = topic_for(session_id, atom)
      Phoenix.PubSub.subscribe(@pubsub_name, topic)
    end)
  end
  
  @doc """
  Unsubscribe from topics.
  """
  def unsubscribe(session_id, topic_atoms) when is_list(topic_atoms) do
    Enum.each(topic_atoms, fn atom ->
      topic = topic_for(session_id, atom)
      Phoenix.PubSub.unsubscribe(@pubsub_name, topic)
    end)
  end
  
  @doc """
  Broadcast a message to a topic.
  
  ## Examples
  
      RShell.PubSub.broadcast("my_session", :ast, {:ast_updated, ast})
  """
  def broadcast(session_id, topic_atom, message) do
    topic = topic_for(session_id, topic_atom)
    Phoenix.PubSub.broadcast(@pubsub_name, topic, message)
  end
  
  # Private helpers
  defp topic_for(session_id, :ast), do: ast_topic(session_id)
  defp topic_for(session_id, :executable), do: executable_topic(session_id)
  defp topic_for(session_id, :runtime), do: runtime_topic(session_id)
  defp topic_for(session_id, :output), do: output_topic(session_id)
  defp topic_for(session_id, :context), do: context_topic(session_id)
end
```

### Step 2.3: Create Application Module

**File**: `lib/r_shell/application.ex`

```elixir
defmodule RShell.Application do
  @moduledoc false
  
  use Application
  
  @impl true
  def start(_type, _args) do
    children = [
      # PubSub for event-driven communication
      {Phoenix.PubSub, name: RShell.PubSub.pubsub_name()}
    ]
    
    opts = [strategy: :one_for_one, name: RShell.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```

### Step 2.4: Update mix.exs Application

**File**: `mix.exs`

```elixir
def application do
  [
    extra_applications: [:logger],
    mod: {RShell.Application, []}  # ADD THIS LINE
  ]
end
```

### Step 2.5: Test PubSub

**File**: `test/pubsub_test.exs`

```elixir
defmodule RShell.PubSubTest do
  use ExUnit.Case, async: false
  
  alias RShell.PubSub
  
  setup do
    session_id = "test_#{:rand.uniform(1000000)}"
    {:ok, session_id: session_id}
  end
  
  test "subscribe and receive messages", %{session_id: session_id} do
    PubSub.subscribe(session_id, [:ast])
    
    message = {:ast_updated, %{test: "data"}}
    PubSub.broadcast(session_id, :ast, message)
    
    assert_receive ^message, 1000
  end
  
  test "subscribe to multiple topics", %{session_id: session_id} do
    PubSub.subscribe(session_id, [:ast, :output])
    
    PubSub.broadcast(session_id, :ast, {:ast, 1})
    PubSub.broadcast(session_id, :output, {:output, 2})
    
    assert_receive {:ast, 1}, 1000
    assert_receive {:output, 2}, 1000
  end
  
  test "unsubscribe from topics", %{session_id: session_id} do
    PubSub.subscribe(session_id, [:ast])
    PubSub.unsubscribe(session_id, [:ast])
    
    PubSub.broadcast(session_id, :ast, {:ast, 1})
    
    refute_receive {:ast, 1}, 100
  end
  
  test "subscribe to all topics", %{session_id: session_id} do
    PubSub.subscribe(session_id, :all)
    
    PubSub.broadcast(session_id, :ast, {:ast, 1})
    PubSub.broadcast(session_id, :runtime, {:runtime, 2})
    PubSub.broadcast(session_id, :output, {:output, 3})
    
    assert_receive {:ast, 1}, 1000
    assert_receive {:runtime, 2}, 1000
    assert_receive {:output, 3}, 1000
  end
  
  test "session isolation", %{session_id: session_id} do
    other_session = "other_#{:rand.uniform(1000000)}"
    
    PubSub.subscribe(session_id, [:ast])
    PubSub.subscribe(other_session, [:ast])
    
    # Broadcast to our session
    PubSub.broadcast(session_id, :ast, {:our_message, 1})
    
    # Should only receive our message
    assert_receive {:our_message, 1}, 1000
    
    # Other session's messages don't interfere
    PubSub.broadcast(other_session, :ast, {:other_message, 2})
    refute_receive {:other_message, 2}, 100
  end
end
```

**Run**:
```bash
mix test test/pubsub_test.exs
```

**Expected**: 5 tests passing

---

## Phase 3: Parser Enhancement (2-3 hours)

**Goal**: Make parser broadcast AST and executable node events.

### Step 3.1: Enhance Parser State

**File**: `lib/r_shell/incremental_parser.ex`

Add `session_id` to state and update `init`:

```elixir
# At top of module
alias RShell.PubSub

# Update init callback
@impl true
def init(opts) when is_list(opts) do
  buffer_size = Keyword.get(opts, :buffer_size, @default_buffer_size)
  session_id = Keyword.get(opts, :session_id, generate_session_id())
  
  case BashParser.new_parser_with_size(buffer_size) do
    {:ok, resource} ->
      Logger.debug("IncrementalParser started: session_id=#{session_id}")
      {:ok, %{
        resource: resource,
        buffer_size: buffer_size,
        session_id: session_id  # NEW
      }}
    
    error ->
      Logger.error("Failed to create parser resource: #{inspect(error)}")
      {:stop, :parser_init_failed}
  end
end

# Add helper
defp generate_session_id do
  "parser_#{System.unique_integer([:positive, :monotonic])}"
end
```

### Step 3.2: Add Executable Node Detection

```elixir
# Add to incremental_parser.ex

defp detect_executable_nodes(ast) do
  children = ast["children"] || []
  
  Enum.filter(children, fn child ->
    type = child["type"]
    has_errors = child["has_errors"] || false
    
    # Complete, error-free statements
    type in [
      "command",
      "pipeline",
      "list",
      "if_statement",
      "for_statement",
      "while_statement",
      "case_statement",
      "function_definition",
      "variable_assignment"
    ] and not has_errors
  end)
end
```

### Step 3.3: Broadcast Events

Update `handle_call({:append_fragment, ...})`:

```elixir
@impl true
def handle_call({:append_fragment, fragment}, _from, state) do
  case BashParser.parse_incremental(state.resource, fragment) do
    {:ok, ast} = result ->
      # Broadcast AST update
      PubSub.broadcast(state.session_id, :ast, {:ast_updated, %{
        ast: ast,
        changed_ranges: ast["changed_ranges"] || [],
        has_errors: ast["has_errors"] || false,
        timestamp: DateTime.utc_now()
      }})
      
      # Check for executable nodes
      executable_nodes = detect_executable_nodes(ast)
      
      if length(executable_nodes) > 0 do
        PubSub.broadcast(state.session_id, :executable, {:executable_nodes, %{
          nodes: executable_nodes,
          complete: true
        }})
      end
      
      {:reply, result, state}
    
    {:error, _reason} = error ->
      {:reply, error, state}
  end
end
```

### Step 3.4: Add get_session_id API

```elixir
@doc """
Get the session ID for this parser.
"""
@spec get_session_id(GenServer.server()) :: String.t()
def get_session_id(server) do
  GenServer.call(server, :get_session_id)
end

@impl true
def handle_call(:get_session_id, _from, state) do
  {:reply, state.session_id, state}
end
```

### Step 3.5: Test Parser PubSub Events

**File**: `test/incremental_parser_pubsub_test.exs`

```elixir
defmodule IncrementalParserPubSubTest do
  use ExUnit.Case, async: false
  
  alias RShell.{IncrementalParser, PubSub}
  
  setup do
    session_id = "test_#{:rand.uniform(1000000)}"
    {:ok, parser} = IncrementalParser.start_link(session_id: session_id)
    
    # Subscribe to events
    PubSub.subscribe(session_id, [:ast, :executable])
    
    {:ok, parser: parser, session_id: session_id}
  end
  
  test "broadcasts ast_updated event", %{parser: parser} do
    IncrementalParser.append_fragment(parser, "echo 'hello'\\n")
    
    assert_receive {:ast_updated, %{
      ast: ast,
      has_errors: false
    }}, 1000
    
    assert ast["type"] == "program"
  end
  
  test "broadcasts executable_nodes for complete command", %{parser: parser} do
    IncrementalParser.append_fragment(parser, "echo 'test'\\n")
    
    assert_receive {:executable_nodes, %{
      nodes: nodes,
      complete: true
    }}, 1000
    
    assert length(nodes) == 1
    assert hd(nodes)["type"] == "command"
  end
  
  test "no executable event for incomplete input", %{parser: parser} do
    IncrementalParser.append_fragment(parser, "if [ -f file ]; then\\n")
    
    # Should get AST update
    assert_receive {:ast_updated, _}, 1000
    
    # But not executable (incomplete)
    refute_receive {:executable_nodes, _}, 100
  end
  
  test "executable event after completing structure", %{parser: parser} do
    IncrementalParser.append_fragment(parser, "if [ -f file ]; then\\n")
    IncrementalParser.append_fragment(parser, "  echo 'found'\\n")
    IncrementalParser.append_fragment(parser, "fi\\n")
    
    # Last fragment should trigger executable
    assert_receive {:executable_nodes, %{nodes: nodes}}, 1000
    assert length(nodes) >= 1
  end
  
  test "get_session_id returns session", %{parser: parser, session_id: session_id} do
    assert IncrementalParser.get_session_id(parser) == session_id
  end
end
```

**Run**:
```bash
mix test test/incremental_parser_pubsub_test.exs
```

**Expected**: 5 tests passing

---

## Phase 4: Runtime GenServer (4-6 hours)

**Goal**: Create execution engine that subscribes to parser events.

### Step 4.1: Enhance Context

**File**: `lib/bash_parser/executor/context.ex`

Add to struct:

```elixir
defstruct [
  # Existing fields
  :mode, :env, :functions, :exit_code, :output, :errors, :strict, :scopes,
  
  # NEW runtime fields
  :cwd,              # Current working directory
  :aliases,          # Command aliases
  :last_command,     # Last executed command
  :command_count,    # Number of commands run
  :session_vars      # Session metadata ($?, $LINENO, etc.)
]

# Update new/1
def new(opts \\ []) do
  mode = Keyword.get(opts, :mode, :simulate)
  env = Keyword.get(opts, :env, %{})
  strict = Keyword.get(opts, :strict, false)
  cwd = Keyword.get(opts, :cwd, System.get_env("PWD") || "/")
  
  %__MODULE__{
    mode: mode,
    env: env,
    functions: %{},
    exit_code: 0,
    output: [],
    errors: [],
    strict: strict,
    scopes: [],
    cwd: cwd,
    aliases: %{},
    last_command: "",
    command_count: 0,
    session_vars: %{
      last_exit: 0,
      line_number: 0
    }
  }
end

# Add new functions

@doc "Change current working directory"
@spec set_cwd(t(), String.t()) :: t()
def set_cwd(%__MODULE__{} = context, path) do
  %{context | cwd: path}
end

@doc "Set alias"
@spec set_alias(t(), String.t(), String.t()) :: t()
def set_alias(%__MODULE__{} = context, name, value) do
  %{context | aliases: Map.put(context.aliases, name, value)}
end

@doc "Get alias"
@spec get_alias(t(), String.t()) :: String.t() | nil
def get_alias(%__MODULE__{} = context, name) do
  Map.get(context.aliases, name)
end

@doc "Increment command counter"
@spec inc_command_count(t()) :: t()
def inc_command_count(%__MODULE__{} = context) do
  %{context | command_count: context.command_count + 1}
end
```

### Step 4.2: Create Runtime GenServer

**File**: `lib/r_shell/runtime.ex`

```elixir
defmodule RShell.Runtime do
  @moduledoc """
  Runtime execution engine for bash scripts.
  
  Subscribes to parser's executable_nodes events and executes them
  while maintaining execution context (variables, cwd, functions).
  """
  
  use GenServer
  require Logger
  
  alias BashParser.Executor
  alias BashParser.Executor.Context
  alias RShell.PubSub
  
  # Client API
  
  @doc """
  Start the runtime GenServer.
  
  Options:
    - `:session_id` - Session identifier (required)
    - `:mode` - Execution mode (:simulate | :capture | :real)
    - `:auto_execute` - Execute nodes as they arrive (default: true)
    - `:env` - Initial environment variables
    - `:cwd` - Initial working directory
  """
  def start_link(opts) do
    session_id = Keyword.fetch!(opts, :session_id)
    GenServer.start_link(__MODULE__, opts)
  end
  
  @doc "Execute a single AST node"
  def execute_node(server, node) do
    GenServer.call(server, {:execute_node, node})
  end
  
  @doc "Get current execution context"
  def get_context(server) do
    GenServer.call(server, :get_context)
  end
  
  @doc "Get variable value"
  def get_variable(server, name) do
    GenServer.call(server, {:get_variable, name})
  end
  
  @doc "Get current working directory"
  def get_cwd(server) do
    GenServer.call(server, :get_cwd)
  end
  
  @doc "Set current working directory"
  def set_cwd(server, path) do
    GenServer.call(server, {:set_cwd, path})
  end
  
  @doc "Set execution mode"
  def set_mode(server, mode) when mode in [:simulate, :capture, :real] do
    GenServer.call(server, {:set_mode, mode})
  end
  
  # Server Callbacks
  
  @impl true
  def init(opts) do
    session_id = Keyword.fetch!(opts, :session_id)
    mode = Keyword.get(opts, :mode, :simulate)
    auto_execute = Keyword.get(opts, :auto_execute, true)
    env = Keyword.get(opts, :env, %{})
    cwd = Keyword.get(opts, :cwd, System.get_env("PWD") || "/")
    
    # Subscribe to executable nodes from parser
    PubSub.subscribe(session_id, [:executable])
    
    context = Context.new(mode: mode, env: env, cwd: cwd)
    
    Logger.debug("Runtime started: session_id=#{session_id}, mode=#{mode}")
    
    {:ok, %{
      session_id: session_id,
      context: context,
      auto_execute: auto_execute
    }}
  end
  
  @impl true
  def handle_call({:execute_node, node}, _from, state) do
    {result, new_context} = execute_node_internal(node, state.context, state.session_id)
    {:reply, result, %{state | context: new_context}}
  end
  
  @impl true
  def handle_call(:get_context, _from, state) do
    {:reply, state.context, state}
  end
  
  @impl true
  def handle_call({:get_variable, name}, _from, state) do
    value = Context.get_variable(state.context, name)
    {:reply, value, state}
  end
  
  @impl true
  def handle_call(:get_cwd, _from, state) do
    {:reply, state.context.cwd, state}
  end
  
  @impl true
  def handle_call({:set_cwd, path}, _from, state) do
    old_cwd = state.context.cwd
    new_context = Context.set_cwd(state.context, path)
    
    # Broadcast context change
    PubSub.broadcast(state.session_id, :context, {:cwd_changed, %{
      old: old_cwd,
      new: path
    }})
    
    {:reply, :ok, %{state | context: new_context}}
  end
  
  @impl true
  def handle_call({:set_mode, mode}, _from, state) do
    new_context = %{state.context | mode: mode}
    {:reply, :ok, %{state | context: new_context}}
  end
  
  # Handle executable nodes from parser
  @impl true
  def handle_info({:executable_nodes, %{nodes: nodes}}, state) do
    if state.auto_execute do
      new_context = Enum.reduce(nodes, state.context, fn node, ctx ->
        {_result, new_ctx} = execute_node_internal(node, ctx, state.session_id)
        new_ctx
      end)
      
      {:noreply, %{state | context: new_context}}
    else
      {:noreply, state}
    end
  end
  
  # Private Helpers
  
  defp execute_node_internal(node, context, session_id) do
    # Broadcast execution start
    PubSub.broadcast(session_id, :runtime, {:execution_started, %{
      node: node,
      timestamp: DateTime.utc_now()
    }})
    
    start_time = System.monotonic_time(:microsecond)
    
    # Execute using existing Executor
    new_context = Executor.execute_node(node, context)
    new_context = Context.inc_command_count(new_context)
    
    duration = System.monotonic_time(:microsecond) - start_time
    
    # Broadcast execution complete
    PubSub.broadcast(session_id, :runtime, {:execution_completed, %{
      node: node,
      exit_code: new_context.exit_code,
      duration_us: duration,
      timestamp: DateTime.utc_now()
    }})
    
    # Broadcast output if any
    if length(new_context.output) > length(context.output) do
      new_output = new_context.output -- context.output
      Enum.each(Enum.reverse(new_output), fn output ->
        PubSub.broadcast(session_id, :output, {:stdout, output})
      end)
    end
    
    # Broadcast errors if any
    if length(new_context.errors) > length(context.errors) do
      new_errors = new_context.errors -- context.errors
      Enum.each(Enum.reverse(new_errors), fn error ->
        PubSub.broadcast(session_id, :output, {:stderr, error})
      end)
    end
    
    {{:ok, new_context}, new_context}
  end
end
```

### Step 4.3: Test Runtime

**File**: `test/runtime_test.exs`

```elixir
defmodule RShell.RuntimeTest do
  use ExUnit.Case, async: false
  
  alias RShell.{Runtime, PubSub}
  
  setup do
    session_id = "test_#{:rand.uniform(1000000)}"
    {:ok, runtime} = Runtime.start_link(
      session_id: session_id,
      mode: :simulate,
      auto_execute: false  # Manual execution for tests
    )
    
    PubSub.subscribe(session_id, :all)
    
    {:ok, runtime: runtime, session_id: session_id}
  end
  
  test "executes node and broadcasts events", %{runtime: runtime} do
    node = %{
      "type" => "command",
      "text" => "echo hello",
      "children" => []
    }
    
    Runtime.execute_node(runtime, node)
    
    assert_receive {:execution_started, _}, 1000
    assert_receive {:execution_completed, %{exit_code: 0}}, 1000
  end
  
  test "tracks context", %{runtime: runtime} do
    context = Runtime.get_context(runtime)
    
    assert context.cwd != nil
    assert context.command_count == 0
  end
  
  test "get/set cwd", %{runtime: runtime} do
    Runtime.set_cwd(runtime, "/tmp")
    
    assert_receive {:cwd_changed, %{old: _, new: "/tmp"}}, 1000
    assert Runtime.get_cwd(runtime) == "/tmp"
  end
end
```

### Step 4.4: Integration Test

**File**: `test/parser_runtime_integration_test.exs`

```elixir
defmodule ParserRuntimeIntegrationTest do
  use ExUnit.Case, async: false
  
  alias RShell.{IncrementalParser, Runtime, PubSub}
  
  setup do
    session_id = "test_#{:rand.uniform(1000000)}"
    
    {:ok, parser} = IncrementalParser.start_link(session_id: session_id)
    {:ok, runtime} = Runtime.start_link(
      session_id: session_id,
      mode: :simulate,
      auto_execute: true  # Auto-execute for integration
    )
    
    PubSub.subscribe(session_id, :all)
    
    {:ok, parser: parser, runtime: runtime, session_id: session_id}
  end
  
  test "end-to-end: parse and execute", %{parser: parser, runtime: runtime} do
    # Submit command
    IncrementalParser.append_fragment(parser, "echo hello\\n")
    
    # Should see events in order
    assert_receive {:ast_updated, _}, 1000
    assert_receive {:executable_nodes, _}, 1000
    assert_receive {:execution_started, _}, 1000
    assert_receive {:execution_completed, _}, 1000
  end
  
  test "context is updated", %{parser: parser, runtime: runtime} do
    # Set variable
    IncrementalParser.append_fragment(parser, "FOO=bar\\n")
    
    # Wait for execution
    assert_receive {:execution_completed, _}, 1000
    
    # Check context
    context = Runtime.get_context(runtime)
    assert Map.has_key?(context.env, "FOO")
  end
end
```

**Run**:
```bash
mix test test/runtime_test.exs
mix test test/parser_runtime_integration_test.exs
```

**Expected**: 6+ tests passing

---

## Phase 5: CLI Integration (2-3 hours)

**Goal**: Update CLI to use Parser + Runtime.

### Step 5.1: Update CLI

**File**: `lib/r_shell/cli.ex`

Update to use Parser + Runtime:

```elixir
def main(_args) do
  IO.puts("\\n🐚 RShell - Interactive Bash Parser & Runtime")
  IO.puts("=" |> String.duplicate(50))
  IO.puts("Type bash code. Commands: .help .reset .quit\\n")
  
  session_id = "cli_#{System.unique_integer([:positive])}"
  
  # Start components
  {:ok, parser} = IncrementalParser.start_link(session_id: session_id)
  {:ok, runtime} = Runtime.start_link(
    session_id: session_id,
    mode: :real,  # Actually execute commands
    auto_execute: true
  )
  
  # Subscribe to output
  PubSub.subscribe(session_id, [:output, :context])
  
  IO.puts("✅ Session: #{session_id}\\n")
  
  loop(parser, runtime, session_id)
end

defp loop(parser, runtime, session_id) do
  case IO.gets("rshell> ") do
    :eof ->
      IO.puts("\\n👋 Goodbye!")
      :ok
    
    line ->
      line = String.trim(line)
      handle_input(parser, runtime, session_id, line)
  end
end

defp handle_input(_parser, _runtime, _session_id, ".quit"), do: IO.puts("\\n👋 Goodbye!")

defp handle_input(parser, runtime, session_id, ".reset") do
  IncrementalParser.reset(parser)
  IO.puts("🔄 Parser reset\\n")
  loop(parser, runtime, session_id)
end

defp handle_input(parser, runtime, session_id, line) do
  # Submit to parser
  IncrementalParser.append_fragment(parser, line <> "\\n")
  
  # Collect output (with timeout)
  collect_output(1000)
  
  loop(parser, runtime, session_id)
end

defp collect_output(timeout) do
  receive do
    {:stdout, output} ->
      IO.write(output)
      collect_output(timeout)
    
    {:stderr, error} ->
      IO.write(:stderr, error)
      collect_output(timeout)
    
    {:variable_set, %{name: name, value: value}} ->
      # Could display variable changes if desired
      collect_output(timeout)
    
    {:cwd_changed, %{new: cwd}} ->
      IO.puts("cd → #{cwd}")
      collect_output(timeout)
  after
    timeout -> :ok
  end
end
```

---

## Testing & Validation

### Run All Tests

```bash
# Run all tests
mix test

# Run specific phases
mix test test/pubsub_test.exs
mix test test/incremental_parser_pubsub_test.exs
mix test test/runtime_test.exs
mix test test/parser_runtime_integration_test.exs
```

### Manual Testing

```bash
# Start CLI
mix run -e "RShell.CLI.main([])"

# Try commands
rshell> echo hello
rshell> export FOO=bar
rshell> echo $FOO
rshell> .reset
rshell> .quit
```

---

## Troubleshooting

### PubSub messages not received

- Check Application is started: `Application.ensure_all_started(:rshell)`
- Verify subscription: `Process.info(self(), :messages)`
- Check topic name matches

### Parser not broadcasting

- Verify `session_id` is set in parser state
- Check executable node detection logic
- Add debug logs: `Logger.debug("Broadcasting: #{inspect(message)}")`

### Runtime not executing

- Verify auto_execute is true
- Check runtime is subscribed to :executable topic
- Verify nodes are detected as executable

---

## Summary

After completing all phases:

✅ **Phase 2**: PubSub infrastructure working (5 tests)
✅ **Phase 3**: Parser broadcasting events (5 tests)  
✅ **Phase 4**: Runtime executing nodes (6+ tests)
✅ **Phase 5**: CLI using new architecture

**Total**: ~15 hours, 16+ new tests

**Next**: Review ARCHITECTURE_DESIGN.md for future enhancements (Session, History, Bytecode, etc.)