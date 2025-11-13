# PubSub Event System Improvements

**Date Created**: 2025-11-13  
**Priority**: High  
**Status**: Planning

---

## Current State (as of 2025-11-13)

### Existing PubSub Events

#### Success Path
1. **`{:ast_updated, typed_ast}`** - Full accumulated AST (`:ast` topic)
   - Contains complete AST of all input accumulated so far
   - Sent after every successful `append_fragment()` call
   - File: `lib/r_shell/incremental_parser.ex:174`

2. **`{:parsing_complete}`** - Redundant completion signal (`:ast` topic)  
   - ⚠️ **TO BE REMOVED** - duplicates information already in `{:ast_updated, ...}`
   - File: `lib/r_shell/incremental_parser.ex:186`
   - All references need cleanup (CLI, tests, etc.)

3. **`{:executable_node, typed_node}`** - Ready for execution (`:executable` topic)
   - Only sent if tree is error-free AND contains executable nodes
   - Runtime subscribes and auto-executes
   - File: `lib/r_shell/incremental_parser.ex:318`
   - ✅ **COMPLETED**: Removed `command_count` parameter

#### Error Paths
4. **`{:parsing_failed, error}`** - NIF returned error (`:ast` topic)
   - Sent when `BashParser.parse_incremental()` returns `{:error, reason}`
   - Replaces `{:ast_updated, ...}` in error cases
   - File: `lib/r_shell/incremental_parser.ex:194`

5. **`{:parsing_crashed, error}`** - Exception caught (`:ast` topic)
   - Sent when parser crashes (caught by `rescue` clause)
   - Guarantees clients never timeout silently
   - File: `lib/r_shell/incremental_parser.ex:210`

---

## Completed Work

✅ **Removed row-counting logic** from IncrementalParser
   - Removed `last_executable_row` tracking
   - Removed `command_count` from state
   - Simplified executable node broadcasting
   - Files: `lib/r_shell/incremental_parser.ex`, `lib/r_shell/cli.ex`, `lib/r_shell/runtime.ex`

✅ **Added try/catch for timeout prevention**
   - Wraps all parsing in rescue clause
   - Always broadcasts at least one message per fragment
   - File: `lib/r_shell/incremental_parser.ex:166`

---

## TODO: Remove {:parsing_complete} Event

### Files to Update

1. **`lib/r_shell/incremental_parser.ex:186`**
   - Remove: `PubSub.broadcast(state.session_id, :ast, {:parsing_complete})`

2. **`lib/r_shell/cli.ex`**
   - Search for: `{:parsing_complete}` pattern matches
   - Remove handling logic (lines ~543)
   - Update event loop to only wait for `{:ast_updated, ...}`

3. **`test/pubsub_guarantees_test.exs`**
   - Update tests that check for `{:parsing_complete}`
   - Lines: 58, 74, 91, 110, 133
   - Replace with only checking for `{:ast_updated, ...}`

4. **`test/parser_runtime_integration_test.exs`**
   - Check if any tests expect `{:parsing_complete}`
   - Update accordingly

5. **Documentation**
   - Update `lib/r_shell/pubsub.ex` module docs (if mentioned)
   - Update any README or design docs mentioning this event

---

## TODO: Implement Incremental AST via Tree-Sitter

### Overview

Instead of sending the full accumulated AST every time, send only the **changed nodes** 
using tree-sitter's native change tracking functionality.

### Tree-Sitter Change Tracking API

Tree-sitter provides built-in support for tracking changes:

```rust
// Check if tree changed
tree.root_node().has_changes() -> bool

// Get changed byte ranges
tree.changed_ranges(old_tree) -> Vec<Range>

// Node-level change detection
node.has_changes() -> bool
node.is_changed() -> bool
```

### Implementation Plan

#### Phase 1: Rust NIF Changes (`native/RShell.BashParser/src/lib.rs`)

**New NIF Functions to Add:**

1. **`get_changed_ranges() -> Vec<Range>`**
   ```rust
   #[rustler::nif]
   fn get_changed_ranges(parser: ResourceArc<ParserResource>) -> Result<Vec<ByteRange>, Error> {
       // Compare current tree with previous tree
       // Return list of changed byte ranges
   }
   ```

2. **`get_changed_nodes() -> Vec<Node>`**
   ```rust
   #[rustler::nif]
   fn get_changed_nodes(parser: ResourceArc<ParserResource>) -> Result<Vec<NodeData>, Error> {
       // Walk tree and collect only nodes with has_changes() == true
       // Return only the changed AST subtrees
   }
   ```

3. **Modify `parse_incremental()` to include change metadata:**
   ```rust
   // Return structure:
   {
     "tree": full_ast,
     "changes": {
       "has_changes": bool,
       "changed_ranges": vec![{start_byte, end_byte}],
       "changed_nodes": vec![node_ast]
     }
   }
   ```

**Key Implementation Details:**
- Store `old_tree` in `ParserResource` to compare against
- After each parse, save current tree as `old_tree` for next comparison
- Tree-sitter's `tree.changed_ranges(old_tree)` does the heavy lifting
- Walk tree recursively to find nodes with `node.has_changes() == true`

#### Phase 2: Elixir Changes (`lib/r_shell/incremental_parser.ex`)

**Update `handle_call({:append_fragment, ...})`:**

```elixir
{:ok, result} = BashParser.parse_incremental(state.resource, fragment)

# result now contains:
# %{
#   "tree" => full_ast,
#   "changes" => %{
#     "has_changes" => true,
#     "changed_ranges" => [...],
#     "changed_nodes" => [...]
#   }
# }

typed_ast = Types.from_map(result["tree"])
typed_changes = Enum.map(result["changes"]["changed_nodes"], &Types.from_map/1)

# Broadcast incremental update
if state.broadcast && state.session_id do
  PubSub.broadcast(state.session_id, :ast, {:ast_incremental, %{
    new_nodes: typed_changes,
    full_ast: typed_ast,  # Include full AST for fallback
    changed_ranges: result["changes"]["changed_ranges"]
  }})
end
```

**Add new API for requesting full AST:**

```elixir
# Clients can explicitly request full AST
def get_full_ast(server) do
  GenServer.call(server, :get_full_ast)
end

# Broadcasts {:ast_full, typed_ast}
def handle_call(:get_full_ast, _from, state) do
  {:ok, ast} = BashParser.get_current_ast(state.resource)
  typed_ast = Types.from_map(ast)
  
  if state.broadcast && state.session_id do
    PubSub.broadcast(state.session_id, :ast, {:ast_full, typed_ast})
  end
  
  {:reply, {:ok, typed_ast}, state}
end
```

#### Phase 3: Client Updates

**`lib/r_shell/cli.ex`** - Handle incremental updates:

```elixir
def handle_pubsub_events(...) do
  receive do
    {:ast_incremental, %{new_nodes: nodes, full_ast: ast}} ->
      # Display only new nodes for efficiency
      # Keep full_ast for commands like .ast that need complete view
      ...
    
    {:ast_full, ast} ->
      # Handle explicit full AST requests
      ...
  end
end
```

#### Phase 4: Testing

**`test/incremental_ast_test.exs`** - New test suite:

```elixir
test "incremental parsing sends only changed nodes" do
  {:ok, parser} = IncrementalParser.start_link(session_id: "test", broadcast: true)
  PubSub.subscribe("test", [:ast])
  
  # First fragment
  IncrementalParser.append_fragment(parser, "echo first\n")
  assert_receive {:ast_incremental, %{new_nodes: nodes1}}
  assert length(nodes1) == 1
  
  # Second fragment - only new command should be in changed nodes
  IncrementalParser.append_fragment(parser, "echo second\n")
  assert_receive {:ast_incremental, %{new_nodes: nodes2}}
  assert length(nodes2) == 1  # Only the new command
end
```

---

## New Event Schema (After Implementation)

### Success Path
1. **`{:ast_incremental, %{new_nodes: [...], full_ast: ast, changed_ranges: [...]}}`**
   - Primary event for each fragment
   - Includes only changed nodes for efficiency
   - Includes full AST for fallback/debugging
   - Includes byte ranges that changed

2. **`{:ast_full, typed_ast}`** (on explicit request)
   - Only sent when explicitly requested via `get_full_ast()`
   - Used for commands like `.ast` that need complete tree

3. **`{:executable_node, typed_node}`** (unchanged)
   - Continues to work as before

### Error Path (unchanged)
4. **`{:parsing_failed, error}`**
5. **`{:parsing_crashed, error}`**

---

## Benefits of Tree-Sitter Native Approach

1. **Most Accurate**: Tree-sitter knows exactly what changed
2. **Efficient**: Only send changed subtrees, not entire AST
3. **Correct Semantics**: Changed nodes ≠ new nodes (edits vs additions)
4. **Future-Proof**: Supports edit commands, not just append

---

## Estimated Effort

- **Rust NIF work**: 4-6 hours (change tracking + node extraction)
- **Elixir integration**: 2-3 hours (event handling + state management)
- **Client updates**: 1-2 hours (CLI + existing clients)
- **Testing**: 2-3 hours (unit + integration tests)
- **Total**: ~10-15 hours

---

## References

- Tree-sitter change tracking: https://tree-sitter.github.io/tree-sitter/using-parsers#editing
- Current IncrementalParser: `lib/r_shell/incremental_parser.ex`
- NIF implementation: `native/RShell.BashParser/src/lib.rs`