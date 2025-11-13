# RShell Architecture & Design

**Comprehensive design document for RShell's incremental parsing and runtime execution system.**

---

## Table of Contents

1. [Overview](#overview)
2. [Current State](#current-state)
3. [Architecture](#architecture)
4. [Components](#components)
5. [Event Flow](#event-flow)
6. [Performance Characteristics](#performance-characteristics)
7. [Design Decisions](#design-decisions)
8. [Future Enhancements](#future-enhancements)

---

## Overview

RShell is a bash parser and runtime built with tree-sitter (Rust) and Elixir. The system supports:

- **Batch Parsing with Input Buffer**: CLI-level buffering ensures parser only receives complete input
- **Event-Driven Architecture**: Components communicate via Phoenix.PubSub
- **Runtime Execution**: Execute parsed AST with multiple modes (simulate, capture, real)
- **Strongly-Typed AST**: Pattern matching on 59 typed structs throughout
- **Continuation Detection**: Lightweight InputBuffer detects incomplete structures before parsing

### Key Design Principles

1. **Separation of Concerns**: Parser parses, Runtime executes
2. **Event-Driven**: Loose coupling via PubSub
3. **Observable**: Every state change emits events
4. **Type Safety**: Strongly-typed AST with compile-time checking

---

## Current State

### Architecture Components

**Three-layer architecture:**

1. **InputBuffer Module** (NEW)
   - Lightweight lexical analysis at CLI level
   - Detects continuation needs without AST analysis
   - Checks for: line continuations (`\`), unclosed quotes, heredocs, control structures
   - Only sends complete fragments to parser
   - Prevents ERROR nodes for incomplete input

2. **IncrementalParser GenServer**
   - Manages Rust NIF parser resource
   - Receives complete bash fragments from CLI
   - Broadcasts typed AST events via PubSub
   - Detects executable nodes
   - Parser only sees complete, parseable input

3. **Runtime GenServer**
   - Subscribes to Parser's executable node events
   - Executes AST nodes (simulate/capture/real modes)
   - Manages execution context (env vars, cwd, command count)
   - Broadcasts execution events and output via PubSub
   - Auto-execute or manual execution modes

4. **Phoenix.PubSub**
   - Event bus connecting Parser ↔ Runtime
   - Session-based topic isolation
   - 5 topics: `:ast`, `:executable`, `:runtime`, `:output`, `:context`

### Core Features

✅ **Batch Parsing with Input Buffering**
- InputBuffer detects continuation needs at CLI level
- Parser only receives complete, parseable input
- Tree-sitter bash parser via Rust NIF
- No ERROR nodes for incomplete structures
- 21 passing NIF tests + 51 InputBuffer tests

✅ **Strongly-Typed AST**
- 59 typed struct definitions auto-generated from grammar
- Pattern matching throughout (no string-based type checking)
- Type-safe field access with compile-time checking

✅ **Error Classification**
- Distinguishes syntax errors (ERROR nodes) from incomplete structures
- Provides context-aware user feedback
- 14 passing error classification tests

✅ **Event-Driven Architecture**
- Parser and Runtime communicate only via PubSub
- Loose coupling enables independent testing
- 26 PubSub tests + 24 Parser event tests

✅ **Runtime Execution**
- Multiple execution modes (simulate, capture, real)
- Context management (env vars, cwd, command count)
- Event broadcasting for all state changes
- 10 runtime tests + 7 integration tests

✅ **Interactive CLI**
- Event-driven feedback
- Real-time AST display
- Error detection and reporting

**Total**: 184 tests passing, 0 compiler warnings

---

## Testing

The test suite provides comprehensive coverage across all layers of the system:

### Low-Level NIF Tests

**`test/bash_parser_nif_test.exs`** (165 lines)
- Tests raw Rust NIF output structure before typed conversion
- Verifies NIF uses `"type"` as field name (populated from tree-sitter's `node.kind()` method)
- Tests named fields extraction (`condition`, `left`, `right`, `name`, `argument`)
- Tests unnamed children arrays
- Validates nested structure preservation
- **Scope**: Rust NIF layer only, map-based output before typed conversion

**`test/incremental_parser_nif_test.exs`** (444 lines, 21 tests)
- Tests incremental parsing NIF functions directly
- Parser resource creation and management
- Fragment accumulation across multiple calls
- Buffer size limits and overflow handling
- Incomplete input handling (multi-line commands)
- Character-by-character parsing
- Tree reuse efficiency verification
- Reset functionality
- Error detection (`has_errors`)
- **Scope**: Low-level incremental parsing without GenServer

### Typed AST Tests

**`test/typed_ast_test.exs`** (104 lines)
- Tests typed struct conversion from raw NIF maps
- Verifies all 59 typed structs are properly generated
- Tests `__struct__` field presence and correctness
- Validates `SourceInfo` struct embedding
- Tests nested structure typing
- **Scope**: Type system and conversion layer

**`test/ast_walker_test.exs`** (207 lines)
- Tests AST traversal utilities
- Pre-order and breadth-first traversal
- Node collection by type or predicate
- Reduce operations for accumulation
- Statistics generation (node counts by type)
- Transform operations
- **Scope**: AST navigation and manipulation utilities

### Parser GenServer Tests

**`test/incremental_parser_pubsub_test.exs`** (369 lines, 24 tests)
- Tests IncrementalParser GenServer with PubSub broadcasting
- AST update event broadcasting
- Executable node detection and broadcasting
- Duplicate detection (tracks last executable row)
- Command count tracking across fragments
- Reset behavior and state clearing
- Complex command structures (if/for/while/case)
- Incomplete command handling
- **Scope**: Parser GenServer + PubSub integration

### Error Classification Tests

**`test/error_classifier_test.exs`** (335 lines, 14 tests)
- Tests error vs incomplete structure distinction
- `has_error_nodes?/1` - Detects ERROR nodes recursively
- `extract_error_info/1` - Extracts location and text from errors
- `identify_incomplete_structure/1` - Recognizes incomplete if/for/while/until/case
- `classify_parse_state/2` - Distinguishes 3 states:
  - `:complete` - Valid and ready to execute
  - `:syntax_error` - Has ERROR nodes (e.g., `if then fi`)
  - `:incomplete` - Waiting for closing keywords (e.g., `if true; then` needs `fi`)
- **Scope**: Error detection and user feedback

### PubSub Infrastructure Tests

**`test/pubsub_test.exs`** (425 lines, 26 tests)
- Tests Phoenix.PubSub wrapper functions
- Topic generation (`:ast`, `:executable`, `:runtime`, `:output`, `:context`)
- Subscribe/unsubscribe to single or multiple topics
- Subscribe with `:all` shorthand
- Broadcast to subscribed processes
- `broadcast_from` (excludes sender)
- Session isolation (no message leakage)
- Message format validation for all event types
- **Scope**: PubSub event bus infrastructure

### Integration Tests

**`test/stream_parser_test.exs`** (if present)
- Tests streaming parser integration
- **Scope**: End-to-end streaming scenarios

**`test/ast_structure_test.exs`** (if present)
- Tests complex nested AST structures
- **Scope**: Structural correctness validation

### Test Organization

```
test/
├── Low-level NIF
│   ├── bash_parser_nif_test.exs       # Raw NIF output
│   └── incremental_parser_nif_test.exs # Incremental NIF
├── Type System
│   ├── typed_ast_test.exs             # Typed conversion
│   └── ast_walker_test.exs            # AST traversal
├── GenServer Layer
│   └── incremental_parser_pubsub_test.exs # Parser + PubSub
├── Error Handling
│   └── error_classifier_test.exs      # Error classification
├── Infrastructure
│   └── pubsub_test.exs                # PubSub wrapper
└── Helpers
    └── test_helper.exs                # Shared test utilities
```

### Test Coverage by Layer

| Layer | Test Files | Test Count | Coverage |
|-------|-----------|------------|----------|
| Rust NIF | `bash_parser_nif_test.exs`, `incremental_parser_nif_test.exs` | 21+ | Low-level parsing |
| Type System | `typed_ast_test.exs`, `ast_walker_test.exs` | 10+ | Typed structs |
| Parser GenServer | `incremental_parser_pubsub_test.exs` | 24 | Event broadcasting |
| Error Detection | `error_classifier_test.exs` | 14 | Error vs incomplete |
| PubSub | `pubsub_test.exs` | 26 | Event bus |
| **Total** | **6 main files** | **95+** | **All layers** |

---

## Architecture

### High-Level View

```
┌─────────────────────────────────────────────────────────┐
│              Application Layer (CLI, REPL)              │
│                                                          │
│  ┌────────────────────────────────────────────────────┐ │
│  │          InputBuffer (Continuation Detector)        │ │
│  │  - Line continuation detection (backslash-newline)  │ │
│  │  - Quote tracking (single, double, escaped)         │ │
│  │  - Heredoc detection (<<MARKER syntax)              │ │
│  │  - Control structure tracking (for/if/while/case)   │ │
│  │  - Only sends COMPLETE fragments to parser          │ │
│  └────────────────────────────────────────────────────┘ │
└────────────────────┬────────────────────────────────────┘
                     │
                     ├─ Start Parser & Runtime
                     ├─ Send COMPLETE Fragments Only
                     ├─ Subscribe to Events
                     └─ Query State
                     │
                     ↓
┌─────────────────────────────────────────────────────────┐
│            Phoenix.PubSub (Event Bus)                   │
│                                                          │
│  Topics (per session):                                  │
│    session:#{id}:ast        - AST updates               │
│    session:#{id}:executable - Executable nodes          │
│    session:#{id}:runtime    - Execution events          │
│    session:#{id}:output     - stdout/stderr             │
│    session:#{id}:context    - Variable/cwd changes      │
└─────────────────────────────────────────────────────────┘
                     │
           ┌─────────┴─────────┐
           ↓                   ↓
  ┌─────────────────┐  ┌─────────────────┐
  │ IncrementalParser│  │    Runtime      │
  │   GenServer      │  │   GenServer     │
  │                  │  │                 │
  │ - parser_resource│  │ - context       │
  │ - session_id     │  │ - session_id    │
  │ - (no incomplete │  │ - env vars      │
  │    input state)  │  │ - cwd           │
  │                  │  │ - command_count │
  │ Receives:        │  │ - mode          │
  │  Complete        │  │                 │
  │  fragments only  │  │ Subscribes:     │
  │                  │  │  :executable    │
  │ Broadcasts:      │  │                 │
  │  :ast            │  │ Broadcasts:     │
  │  :executable     │  │  :runtime       │
  │                  │  │  :output        │
  │                  │  │  :context       │
  └─────────────────┘  └─────────────────┘
```

### Component Interaction

```
User Input → InputBuffer → Complete Fragment → Parser → PubSub → Runtime → Output
     ↓            ↓              ↓                ↓         ↓         ↓        ↓
   Lines    Continuation    Only when         Typed    Events   Execution  stdout/
             Check          ready!            AST +             Context    stderr
             (no AST!)                        Detect            Changes
                                              Executable
                                              Nodes
```

**Key Innovation**: InputBuffer prevents parser from seeing incomplete input, eliminating ERROR nodes for incomplete structures.

---

## Components

### 1. RShell.InputBuffer (NEW)

**Module**: `lib/r_shell/input_buffer.ex`

**Purpose**: Lightweight lexical analysis to detect when input is ready for parsing, WITHOUT using AST analysis.

**API**:
```elixir
# Check if input is complete
InputBuffer.ready_to_parse?("echo hello\n")  # => true
InputBuffer.ready_to_parse?("for i in 1 2 3")  # => false

# Determine continuation type
InputBuffer.continuation_type("echo hello\\")  # => :line_continuation
InputBuffer.continuation_type("echo 'hello")   # => :quote_continuation
InputBuffer.continuation_type("cat <<EOF")     # => :heredoc_continuation
InputBuffer.continuation_type("for i in 1")    # => :structure_continuation
InputBuffer.continuation_type("echo done")     # => :complete
```

**Detection Logic**:

1. **Line Continuation**: Checks if last line ends with `\`
   ```elixir
   # Continuation if last non-empty line ends with backslash
   "echo yo \\\n" -> :line_continuation
   "echo yo \\\ndude \\\n" -> :line_continuation
   "echo yo \\\ndude \\\n\n" -> :complete (empty line breaks continuation)
   ```

2. **Quote Tracking**: State machine tracks quote context
   ```elixir
   # Counts unescaped quotes
   "echo 'hello" -> :quote_continuation
   "echo \"hello" -> :quote_continuation
   "echo 'hello'" -> :complete
   ```

3. **Heredoc Detection**: Regex-based marker matching
   ```elixir
   # Looks for <<MARKER without matching end line
   "cat <<EOF\n" -> :heredoc_continuation
   "cat <<EOF\nline\nEOF\n" -> :complete
   ```

4. **Control Structure Tracking**: Stack-based keyword matching
   ```elixir
   # Stack tracks nested structures
   "for i in 1 2 3" -> [:for] -> :structure_continuation
   "for i; do echo; done" -> [] -> :complete
   "if true; then" -> [:if] -> :structure_continuation
   "if true; then echo; fi" -> [] -> :complete
   ```

**Benefits**:
- ✅ No AST analysis required (much faster)
- ✅ Parser only sees complete input
- ✅ No ERROR nodes for incomplete structures
- ✅ Clear separation: InputBuffer for continuation, Parser for AST
- ✅ Matches bash architecture (separate lexer/parser)

---

### 2. RShell.PubSub

**Module**: `lib/r_shell/pubsub.ex`

**Topics**:
```elixir
"session:#{id}:ast"        # Parser broadcasts AST updates
"session:#{id}:executable" # Parser broadcasts executable nodes
"session:#{id}:runtime"    # Runtime broadcasts execution events
"session:#{id}:output"     # Runtime broadcasts stdout/stderr
"session:#{id}:context"    # Runtime broadcasts context changes
```

**API**:
```elixir
# Subscribe
PubSub.subscribe(session_id, [:ast, :output])
PubSub.subscribe(session_id, :all)

# Broadcast
PubSub.broadcast(session_id, :ast, {:ast_updated, ast})
```

---

### 3. RShell.IncrementalParser

**Module**: `lib/r_shell/incremental_parser.ex`

**State**:
```elixir
%State{
  resource: ResourceArc,           # Rust parser resource
  buffer_size: integer(),          # Max buffer size
  session_id: String.t(),          # PubSub session ID
  broadcast: boolean(),            # Enable/disable events
  last_executable_row: integer(),  # Track last broadcast row (prevent duplicates)
  command_count: integer()         # Incremental command counter
}
```

**Key Features**:
- **Incremental AST updates**: Uses tree-sitter's native change tracking
- **Duplicate prevention**: Tracks `last_executable_row` to avoid re-broadcasting
- **Command counting**: Sequential numbering for executable nodes
- **Error guarantees**: Always broadcasts ONE event per fragment (success or error)

**API**:
```elixir
{:ok, pid} = IncrementalParser.start_link(session_id: "abc")
{:ok, ast} = IncrementalParser.append_fragment(pid, "echo hello\n")
:ok = IncrementalParser.reset(pid)
{:ok, ast} = IncrementalParser.get_current_ast(pid)
```

**Broadcasts**:
```elixir
# Incremental AST update with change tracking
PubSub.broadcast(session_id, :ast, {:ast_incremental, %{
  full_ast: typed_ast,           # Complete accumulated AST
  changed_nodes: [typed_node],   # Only nodes that changed/were added
  changed_ranges: [%{            # Byte ranges that changed
    start_byte: integer,
    end_byte: integer,
    start_point: %{row, col},
    end_point: %{row, col}
  }]
}})

# Parse errors
PubSub.broadcast(session_id, :ast, {:parsing_failed, error})
PubSub.broadcast(session_id, :ast, {:parsing_crashed, error})

# Executable nodes (typed structs with command count)
PubSub.broadcast(session_id, :executable, {:executable_node, node, count})
```

---

### 4. RShell.Runtime

**Module**: `lib/r_shell/runtime.ex`

**State**:
```elixir
%State{
  session_id: String.t(),
  context: map(),
  auto_execute: boolean()
}
```

**Context**:
```elixir
%{
  mode: :simulate | :capture | :real,
  env: %{String.t() => String.t()},
  cwd: String.t(),
  exit_code: integer(),
  command_count: integer(),
  output: [String.t()],
  errors: [String.t()]
}
```

**API**:
```elixir
# Start runtime
{:ok, pid} = Runtime.start_link(
  session_id: "abc",
  mode: :simulate,
  auto_execute: true
)

# Manual execution
{:ok, result} = Runtime.execute_node(pid, node)

# Context queries
context = Runtime.get_context(pid)
value = Runtime.get_variable(pid, "FOO")
cwd = Runtime.get_cwd(pid)

# Context mutations
:ok = Runtime.set_cwd(pid, "/tmp")
:ok = Runtime.set_mode(pid, :simulate)
```

**Events Published**:
```elixir
# Execution lifecycle
PubSub.broadcast(session_id, :runtime, {:execution_started, %{node: node}})
PubSub.broadcast(session_id, :runtime, {:execution_completed, %{exit_code: 0}})

# Output
PubSub.broadcast(session_id, :output, {:stdout, "hello\n"})
PubSub.broadcast(session_id, :output, {:stderr, "error\n"})

# Context changes
PubSub.broadcast(session_id, :context, {:variable_set, %{name: "FOO", value: "bar"}})
PubSub.broadcast(session_id, :context, {:cwd_changed, %{old: "/", new: "/tmp"}})
```

---

### 5. BashParser.AST.Types

**Module**: `lib/bash_parser/ast/types.ex`

59 strongly-typed struct definitions for all AST node types:

```elixir
%Types.Program{source_info: %SourceInfo{}, children: [...]}
%Types.Command{source_info: %SourceInfo{}, name: ..., argument: [...]}
%Types.IfStatement{source_info: %SourceInfo{}, condition: [...], children: [...]}
# ... 56 more types
```

**Usage**:
```elixir
# Pattern matching on typed structs
case node do
  %Types.Command{} -> execute_command(node, context)
  %Types.IfStatement{} -> execute_if_statement(node, context)
  %Types.Pipeline{} -> execute_pipeline(node, context)
end
```

---

### 6. RShell.ErrorClassifier

**Module**: `lib/r_shell/error_classifier.ex`

Distinguishes between:
- **Syntax errors** - Has ERROR nodes (e.g., `if then fi`)
- **Incomplete structures** - Waiting for closing keywords (e.g., `if true; then` needs `fi`)
- **Complete & valid** - Ready to execute

```elixir
ErrorClassifier.classify_parse_state(ast, resource)
# Returns: {:ok, :complete} | {:error, :syntax_error, info} | {:error, :incomplete_structure, info}
```

---

## Event Flow

### Example: User types "export FOO=bar\n"

```
1. User Input → CLI.submit_fragment("export FOO=bar\n")
2. Parser Receives → IncrementalParser.append_fragment(pid, fragment)
3. Rust NIF parses → Returns typed AST with change tracking
4. Parser Broadcasts → PubSub.broadcast(:ast, {:ast_incremental, %{
     full_ast: typed_ast,
     changed_nodes: [new_command_node],
     changed_ranges: [{start_byte: 0, end_byte: 15, ...}]
   }})
5. Parser Detects Complete → PubSub.broadcast(:executable, {:executable_node, node, 1})
6. Runtime Receives → handle_info({:executable_node, node, count})
7. Runtime Executes → Uses pattern matching on typed struct
8. Runtime Broadcasts → PubSub.broadcast(:context, {:variable_set, %{name: "FOO", value: "bar"}})
9. Runtime Broadcasts → PubSub.broadcast(:runtime, {:execution_completed, %{exit_code: 0}})
10. CLI Maintains State → Parser not reset, accumulates for .ast command
11. CLI Receives → Displays feedback to user
```

---

## Performance Characteristics

### Memory Footprint

Per active session:
```
Parser GenServer:
  - GenServer overhead:      5 KB
  - Parser resource (Rust): 400 KB
  - Accumulated input:       50 KB
  Subtotal:                 455 KB

Runtime GenServer:
  - GenServer overhead:      5 KB
  - Context (env):         100 KB
  - Output buffers:         50 KB
  Subtotal:                155 KB

Total per session:         610 KB
```

### CPU Overhead

Per operation:
```
Tree-sitter parse:      1,000 μs  (94%)
AST conversion:            50 μs   (5%)
Executable detection:      10 μs   (1%)
GenServer calls:            6 μs   (0.6%)
PubSub broadcast:           2 μs   (0.2%)
────────────────────────────────────
Total:                  1,068 μs

GenServer overhead: 0.6% (negligible)
```

### Throughput

- **Parse rate**: ~1,000 operations/sec (limited by tree-sitter)
- **Execution rate**: Depends on commands (1-1000ms each)
- **Typical REPL**: 1-10 commands/sec (human-limited)

**Bottlenecks**: Parsing (tree-sitter) and command execution, NOT GenServers.

---

## Design Decisions

### Why Two Separate GenServers?

**Parser + Runtime** vs. single combined GenServer

| Factor | Two GenServers | One GenServer |
|--------|----------------|---------------|
| Memory | +55 KB (~9%) | Baseline |
| CPU | +3 μs (0.3%) | Baseline |
| Concurrency | ✅ Parse while executing | ❌ Serialized |
| Flexibility | ✅ Parse-only or execute-only | ❌ Always combined |
| Fault Tolerance | ✅ Independent failure | ❌ Single point of failure |
| Testing | ✅ Test in isolation | ❌ Always coupled |

**Verdict**: Overhead is negligible, benefits are substantial. Two GenServers is the right choice.

### Why Strongly-Typed AST?

**Pattern matching on structs** vs. string-based type checking

| Factor | Typed Structs | String Types |
|--------|---------------|--------------|
| Type Safety | ✅ Compile-time errors | ❌ Runtime errors |
| Performance | ✅ Faster pattern matching | ❌ String comparison |
| IDE Support | ✅ Autocomplete, docs | ❌ No help |
| Maintainability | ✅ Clear structure | ❌ Fragile strings |

**Verdict**: Strongly-typed AST provides safety, performance, and maintainability.

### Why No Session GenServer?

**Direct management** (Parser + Runtime) vs. Session orchestrator

**Decision**: Start without Session. Add later if coordination burden becomes clear.

Simple is better until complexity is justified.

---

## Summary

This architecture provides:

✅ **Clean separation**: Parser parses, Runtime executes  
✅ **Event-driven**: Loose coupling via PubSub  
✅ **Observable**: Every state change emits events  
✅ **Type-safe**: Strongly-typed AST throughout  
✅ **Testable**: Components tested independently  
✅ **Performant**: Overhead is negligible (<1%)  
✅ **Extensible**: Easy to add new components  

**Current Status**: All planned phases complete. 368 tests passing.

**Recent Updates (2025-11-13)**:
- ✅ Implemented tree-sitter incremental change tracking
- ✅ Replaced `{:ast_updated}` with `{:ast_incremental}` event
- ✅ Removed redundant `{:parsing_complete}` event
- ✅ Added command count to executable nodes
- ✅ CLI no longer auto-resets parser (maintains accumulated state)

The design is pragmatic, starting simple and allowing growth.