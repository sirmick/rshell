# RShell Incremental Parser Design Document

## Overview

This document describes the architecture for RShell's incremental parsing system, which enables streaming bash script parsing with real-time execution capabilities.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Client Code / Tests                       │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ├─ RShell.parse(script) [sync wrapper]
                       │       ↓
                       │  ┌──────────────────────────┐
                       │  │ RShell.StreamParser      │
                       │  │   (synchronous wrapper)   │
                       │  └──────────┬───────────────┘
                       │             │
                       ↓             ↓
            ┌─────────────────────────────────┐
            │  RShell.IncrementalParser       │
            │      (GenServer)                 │
            │                                  │
            │  State:                          │
            │    - parser_resource (Rust)      │
            │    - accumulated_input           │
            │    - current_tree                │
            │    - subscribers (PubSub)        │
            └──────────┬──────────────────────┘
                       │
                       ├─ Phoenix.PubSub
                       │    ↓
                       │  ┌─────────────────────────┐
                       │  │ Topics:                 │
                       │  │  - executable_nodes     │
                       │  │  - structural_changes   │
                       │  │  - full_ast             │
                       │  │  - parse_errors         │
                       │  └─────────────────────────┘
                       │
                       ↓
            ┌─────────────────────────────────┐
            │  Rust NIF Layer                 │
            │  (native/RShell.BashParser)     │
            │                                  │
            │  - ParserResource (ResourceArc) │
            │  - Tree-sitter Parser           │
            │  - Old Tree Cache               │
            └─────────────────────────────────┘
```

## Phase 1: Incremental Parser Core

### Components

#### 1. Rust NIF Layer

**Memory Management:**
- Use `ResourceArc<ParserResource>` for safe cross-NIF persistence
- Tree-sitter's incremental parsing with proper InputEdit tracking
- Old tree kept as reference, new tree created each parse
- Maximum buffer size limit (configurable, default 10MB)
- Automatic cleanup on resource drop
- Trees are immutable - tree-sitter creates new Tree, reusing unchanged subtrees internally

**Tree-sitter Incremental Parsing Strategy:**

Tree-sitter's incremental parsing requires explicit edit information via `InputEdit`:

```rust
// For append-only incremental parsing:
let old_len = accumulated_input.len();
accumulated_input.push_str(&fragment);
let new_len = accumulated_input.len();

let edit = InputEdit {
    start_byte: old_len,
    old_end_byte: old_len,
    new_end_byte: new_len,
    start_position: Point { row: old_row, column: 0 },
    old_end_position: Point { row: old_row, column: 0 },
    new_end_position: Point { row: new_row, column: 0 },
};

// Update old tree's metadata
old_tree.edit(&edit);

// Parse with old_tree as reference (tree-sitter reuses unchanged subtrees)
let new_tree = parser.parse(&accumulated_input, Some(&old_tree))?;

// Extract changed ranges
let changed_ranges = new_tree.changed_ranges(&old_tree);
```

**Changed Ranges:**
- Tree-sitter provides `changed_ranges()` to identify which AST nodes changed
- Returns ranges (byte offsets and positions) of modified subtrees
- Used to determine new vs modified vs unchanged nodes
- Critical for efficient PubSub event emission

**Functions:**
- `new_parser() -> ResourceArc<ParserResource>`
- `parse_incremental(resource, fragment) -> {:ok, ast, changes} | {:error, reason}`
  - Returns complete AST + change metadata: `%{new_nodes: [...], modified_nodes: [...], unchanged_ranges: [...]}`
- `reset_parser(resource) -> :ok`
- `get_current_ast(resource) -> {:ok, ast}`
- `has_errors(resource) -> boolean()`

#### 2. GenServer: RShell.IncrementalParser

**State:**
```elixir
%State{
  parser_resource: ResourceArc,
  pubsub_name: atom(),
  max_buffer_size: integer(),
  sequence_number: integer()
}
```

Note: `accumulated_input`, `current_ast`, and `old_tree` are managed in Rust NIF (ParserResource), not duplicated in Elixir state.

**Messages:**
```elixir
# Async (cast)
{:append_fragment, fragment}
:reset
:stream_end

# Sync (call)
:get_current_ast
:get_state_info
```

**PubSub Topics:**
- `"rshell:executable_nodes"` - Completed, ready-to-execute nodes
- `"rshell:structural_changes"` - New statements/blocks for visualization
- `"rshell:full_ast"` - Complete AST (configurable frequency)
- `"rshell:parse_errors"` - Parse errors with position info

#### 3. Synchronous Wrapper: RShell.StreamParser

**Purpose:** Provides backward-compatible synchronous API for tests

**Features:**
- Auto-starts GenServer if not running
- Resets parser before each use
- Timeout-based synchronous waiting
- Returns `{:ok, ast}` or `{:error, reason}`

#### 4. PubSub Module: RShell.PubSub

**Purpose:** Centralized topic definitions and subscription helpers

**Topics:**
```elixir
@executable_nodes "rshell:executable_nodes"
@structural_changes "rshell:structural_changes"
@full_ast "rshell:full_ast"
@parse_errors "rshell:parse_errors"
```

## Node Emission Strategy

### Execution-Ready Detection

Nodes are marked as executable when:
- **Statement-level**: Commands, assignments, pipes terminated by `\n`, `;`, `&&`, `||`
- **Structure-level**: Complete control structures (`fi`, `done`, `esac`, `}`)

Each node includes:
```elixir
%{
  node: %AST.Types.Command{...},
  sequence_number: 42,
  executable: true,
  reason: "complete_statement" | "complete_structure" | "incomplete_syntax",
  position: {line: 5, col: 0}
}
```

### Partial Node Strategy

Emit on structural changes with 50ms debouncing:
- New statement/block start
- Block completion
- Significant syntax changes
- Completion percentage for control structures

### Full AST Emission

Configurable via options:
- `:always` - After every fragment (verbose)
- `:on_boundaries` - After complete statements (default)
- `:on_request` - Only via `get_current_ast/0` (pull model)
- `:never` - Disabled

## Memory Management

### Rust Side

- **ResourceArc lifecycle**: Lives as long as GenServer reference exists
- **Tree lifecycle**:
  - Old tree stored in `Mutex<Option<Tree>>` within ParserResource
  - Each parse creates NEW tree (immutable)
  - Old tree kept as reference for next parse
  - Tree-sitter internally reuses unchanged subtrees for performance
  - Old tree dropped when replaced or on reset
  - No manual memory management needed - Rust handles via Drop trait
- **InputEdit tracking**: Calculated from accumulated input length changes
- **Buffer limits**: Check size before appending, reject if exceeded
- **Reset behavior**: Clears accumulated input and drops old tree
- **Memory safety**: No leaks - Trees are freed when Option<Tree> is replaced or dropped

### Elixir Side

- **GenServer supervision**: Ensures cleanup on crash
- **Message queue monitoring**: Prevent unbounded growth
- **PubSub cleanup**: Unsubscribe on termination

## Implementation Phases

### Phase 1: Parser Core (Current)
- ✅ Rust NIF with ResourceArc
- ✅ Tree-sitter InputEdit tracking with changed_ranges()
- ✅ IncrementalParser GenServer with change metadata
- ✅ StreamParser wrapper
- ✅ CLI change detection (client-side, ready for PubSub migration)
- ✅ Comprehensive tests (105 passing)
- ✅ Node evolution tests (ERROR → valid structures)

### Phase 2: Lazy Executor (Future)
- Separate Executor GenServer
- Subscribe to executable_nodes
- Maintain execution context (variables, functions, cwd)
- Support `:execute`, `:dry_run`, `:parse_only` modes

### Phase 3: Bytecode Compiler (Future)
- Separate Compiler GenServer
- Hash-based bytecode caching
- Incremental compilation
- Full-tree optimizations

### Phase 4: Visualizer & Tooling (Future)
- Real-time AST visualization
- Debug tools
- Performance monitoring

## Testing Strategy

### Unit Tests (Rust)
- Incremental parsing correctness
- Memory management (no leaks)
- Buffer size limits
- Reset functionality

### Integration Tests (Elixir)
- Fragment sequencing
- Node emission correctness
- PubSub message delivery
- Error handling
- Timeout behavior

### Regression Tests
- Convert existing tests to use StreamParser
- Ensure backward compatibility
- Performance benchmarks

## Configuration

```elixir
config :rshell, RShell.IncrementalParser,
  max_buffer_size: 10_485_760,  # 10MB
  full_ast_mode: :on_boundaries,
  debounce_ms: 50,
  pubsub_name: RShell.PubSub
```

## API Examples

### Streaming API
```elixir
{:ok, parser} = RShell.IncrementalParser.start_link([])
RShell.IncrementalParser.subscribe([:executable_nodes, :parse_errors])

GenServer.cast(parser, {:append_fragment, "echo 'hello'\n"})
receive do
  {:executable_nodes, node} -> IO.inspect(node)
end

GenServer.cast(parser, :reset)
GenServer.cast(parser, {:append_fragment, "if [ -f file ]; then\n"})
GenServer.cast(parser, {:append_fragment, "  echo 'exists'\n"})
GenServer.cast(parser, {:append_fragment, "fi\n"})
GenServer.cast(parser, :stream_end)
```

### Synchronous API (Tests)
```elixir
{:ok, ast} = RShell.parse("echo 'hello'")
```

## Performance Considerations

- **Incremental parsing**: Only re-parses changed regions
- **Debouncing**: Reduces emission spam on rapid typing
- **Buffer limits**: Prevents memory exhaustion
- **PubSub**: Efficient message distribution
- **Lazy execution**: Only executes when requested

## Security Considerations

- Buffer size limits prevent DOS attacks
- No code execution in parser (only in separate executor)
- Resource cleanup on crash
- Configurable timeouts

## Future Enhancements

- Syntax highlighting data emission
- Autocomplete suggestions
- Static analysis warnings
- Multi-file parsing
- Shell script formatting