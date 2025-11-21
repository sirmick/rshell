# RShell Hard Cutover Plan - Full Bash Replacement

**Date**: 2025-11-20  
**Strategy**: Complete replacement of bash parser with rshell parser  
**Goal**: Single parser system using rshell grammar (97.7% test pass rate)

---

## Executive Summary

**Approach**: Remove bash parser, make rshell the only parser  
**Timeline**: 1-2 weeks  
**Risk**: High (breaking change) but cleaner architecture  
**Benefit**: No dual-parser complexity, simpler codebase

---

## Why Hard Cutover?

### ✅ Benefits
1. **Simpler Architecture** - One parser, one AST type system
2. **No Compatibility Layer** - No need to support both grammars
3. **Cleaner Code** - No language switching logic
4. **Better Testing** - Single test suite, no duplication
5. **RShell is Superset** - Supports bash commands + native types

### ⚠️ Risks
1. **Breaking Change** - Existing bash scripts may need updates
2. **Migration Effort** - All tests need conversion
3. **User Impact** - Users must learn RShell syntax (minimal differences)

### 🎯 Decision
**Proceed with hard cutover** because:
- RShell grammar is 97.7% complete
- RShell is bash-compatible for most use cases
- Clean architecture > backward compatibility
- Better long-term maintainability

---

## Current State (Bash)

```
┌─────────────────────────────────────────┐
│ User Input (bash syntax)                │
└────────────┬────────────────────────────┘
             │
             ▼
┌─────────────────────────────────────────┐
│ BashParser NIF (tree-sitter-bash)       │
│ - new_parser_with_language("bash")      │
└────────────┬────────────────────────────┘
             │
             ▼
┌─────────────────────────────────────────┐
│ BashParser.AST.Types (59 node types)    │
│ - Command, VariableAssignment           │
│ - IfStatement, ForStatement, etc.       │
└────────────┬────────────────────────────┘
             │
             ▼
┌─────────────────────────────────────────┐
│ Runtime.do_execute_node()                │
│ - Pattern match on bash node types      │
│ - Execute commands, control flow        │
└─────────────────────────────────────────┘
```

---

## Target State (RShell Only)

```
┌─────────────────────────────────────────┐
│ User Input (rshell syntax)              │
│ - Bash commands still work              │
│ - NEW: Lists [1,2,3], Maps {'x':1}     │
│ - NEW: X = value (clean assignments)    │
└────────────┬────────────────────────────┘
             │
             ▼
┌─────────────────────────────────────────┐
│ BashParser NIF (tree-sitter-rshell)     │
│ - Default to rshell grammar             │
│ - Remove bash support                   │
└────────────┬────────────────────────────┘
             │
             ▼
┌─────────────────────────────────────────┐
│ BashParser.AST.RShellTypes (64 types)   │
│ - All bash types PLUS:                  │
│ - ListLiteral, MapLiteral               │
│ - RshellAssignment, RshellExpression    │
└────────────┬────────────────────────────┘
             │
             ▼
┌─────────────────────────────────────────┐
│ Runtime.do_execute_node()                │
│ - Pattern match on rshell node types    │
│ - Execute ALL rshell features           │
└─────────────────────────────────────────┘
```

---

## Implementation Steps

### Step 1: Update Rust NIF (Default to RShell)

**File**: `native/RShell.BashParser/src/lib.rs`

#### Before:
```rust
fn new_parser() -> NifResult<(Atom, ResourceArc<ParserResource>)> {
    match ParserResource::new(10 * 1024 * 1024) {
        Ok(resource) => Ok((atoms::ok(), ResourceArc::new(resource))),
        Err(msg) => Err(Error::Term(Box::new(msg))),
    }
}

impl ParserResource {
    fn new(max_buffer_size: usize) -> Result<Self, String> {
        Self::new_with_language(max_buffer_size, LanguageType::Bash)  // ← Bash default
    }
}
```

#### After:
```rust
fn new_parser() -> NifResult<(Atom, ResourceArc<ParserResource>)> {
    match ParserResource::new(10 * 1024 * 1024) {
        Ok(resource) => Ok((atoms::ok(), ResourceArc::new(resource))),
        Err(msg) => Err(Error::Term(Box::new(msg))),
    }
}

impl ParserResource {
    fn new(max_buffer_size: usize) -> Result<Self, String> {
        Self::new_with_language(max_buffer_size, LanguageType::RShell)  // ← RShell default
    }
}
```

**Remove bash-specific functions**:
- Remove `new_parser_with_language()` (only rshell now)
- Remove `LanguageType::Bash` enum variant
- Remove tree-sitter-bash dependency from Cargo.toml

---

### Step 2: Rename AST Types Module

**Goal**: Make RShellTypes the primary (and only) type system

#### File Changes:

1. **Backup and rename**:
```bash
# Backup old bash types
mv lib/bash_parser/ast/types.ex lib/bash_parser/ast/types_bash_old.ex

# Make rshell types THE types
mv lib/bash_parser/ast/rshell_types.ex lib/bash_parser/ast/types.ex
```

2. **Update module name**:
```elixir
# lib/bash_parser/ast/types.ex (formerly rshell_types.ex)

defmodule BashParser.AST.Types do
  @moduledoc """
  Typed AST structures for RShell scripts.
  
  Auto-generated from tree-sitter-rshell grammar (64 node types).
  
  Includes RShell-specific extensions like list literals, map literals,
  boolean literals, and RShell-style assignments alongside bash-compatible constructs.
  """
  
  # Change all module references from RShellTypes to Types
  # Find/Replace: BashParser.AST.RShellTypes → BashParser.AST.Types
  
  # All nodes now under BashParser.AST.Types namespace
  defmodule ListLiteral do
    # ...
  end
  
  defmodule RshellAssignment do
    # Rename to just Assignment? Or keep RshellAssignment?
    # ...
  end
  
  # etc.
end
```

3. **Global find/replace**:
```bash
# Update all references
grep -r "BashParser.AST.RShellTypes" lib/ test/ | wc -l  # Check count
sed -i 's/BashParser.AST.RShellTypes/BashParser.AST.Types/g' lib/**/*.ex
sed -i 's/BashParser.AST.RShellTypes/BashParser.AST.Types/g' test/**/*.exs
```

---

### Step 3: Update IncrementalParser

**File**: `lib/r_shell/incremental_parser.ex`

#### Changes:

1. **Remove language parameter** (no longer needed):
```elixir
def start_link(opts \\ []) do
  session_id = Keyword.get(opts, :session_id)
  buffer_size = Keyword.get(opts, :buffer_size, @default_buffer_size)
  # REMOVED: language parameter
  
  init_arg = %{
    session_id: session_id,
    buffer_size: buffer_size,
    broadcast: Keyword.get(opts, :broadcast, true)
  }
  
  # ...
end
```

2. **Parser creation always uses RShell**:
```elixir
def init(%{buffer_size: buffer_size, ...}) do
  # Always creates rshell parser now
  case BashParser.new_parser_with_size(buffer_size) do
    {:ok, resource} -> 
      Logger.debug("RShell parser started (buffer_size=#{buffer_size})")
      # ...
  end
end
```

3. **Type conversion uses RShell types** (already done if types.ex is renamed):
```elixir
def handle_call({:append_fragment, fragment}, _from, state) do
  case BashParser.parse_incremental(state.resource, fragment) do
    {:ok, ast_map} ->
      # Always convert to RShell types (now just "Types")
      typed_ast = BashParser.AST.Types.from_map(ast_map)
      # ...
  end
end
```

---

### Step 4: Update Runtime for RShell Nodes

**File**: `lib/r_shell/runtime.ex`

#### Key Changes:

1. **Update alias** at top of file:
```elixir
alias BashParser.AST.Types  # Now points to RShell types
```

2. **Add RShell node handlers**:
```elixir
def do_execute_node(node, context, session_id) do
  case node do
    # Standard nodes (work in both bash and rshell)
    %Types.Command{} = cmd -> 
      execute_command(cmd, context, session_id)
    
    %Types.IfStatement{} = stmt -> 
      execute_if_statement(stmt, context, session_id)
    
    %Types.ForStatement{} = stmt ->
      execute_for_statement(stmt, context, session_id)
    
    %Types.WhileStatement{} = stmt ->
      execute_while_statement(stmt, context, session_id)
    
    # NEW: RShell-specific nodes
    %Types.RshellAssignment{} = asgn -> 
      execute_rshell_assignment(asgn, context, session_id)
    
    %Types.ListLiteral{} = lit -> 
      # ListLiterals are evaluated, not executed directly
      # They appear as part of assignments: X = [1,2,3]
      raise "ListLiteral should not be executed directly"
    
    %Types.MapLiteral{} = lit -> 
      # Same as ListLiteral
      raise "MapLiteral should not be executed directly"
    
    %Types.RshellBinaryExpression{} = expr -> 
      # Expressions are evaluated, not executed
      raise "RshellBinaryExpression should not be executed directly"
    
    other ->
      node_type = other.__struct__ |> Module.split() |> List.last()
      raise "Execution not implemented for #{node_type}"
  end
end
```

3. **Add RShell execution functions**:
```elixir
# Execute RShell assignment: X = [1,2,3]
defp execute_rshell_assignment(
  %Types.RshellAssignment{name: name_node, value: value_node},
  context,
  _session_id
) do
  var_name = extract_identifier(name_node)
  value = evaluate_rshell_expression(value_node, context)
  
  new_env = Map.put(context.env, var_name, value)
  %{context | env: new_env, last_output: %{stdout: [], stderr: []}}
end

# Extract identifier from node
defp extract_identifier(%Types.VariableName{source_info: %{text: name}}), do: name
defp extract_identifier(%{source_info: %{text: name}}), do: name
defp extract_identifier(_), do: ""

# Evaluate RShell expression (lists, maps, binary ops, etc.)
defp evaluate_rshell_expression(node, context) do
  case node do
    %Types.ListLiteral{children: elements} ->
      Enum.map(elements, &evaluate_rshell_expression(&1, context))
    
    %Types.MapLiteral{children: entries} ->
      Enum.into(entries, %{}, fn %Types.MapEntry{key: k, value: v} ->
        {evaluate_rshell_expression(k, context), evaluate_rshell_expression(v, context)}
      end)
    
    %Types.Number{source_info: %{text: text}} ->
      parse_number(text)
    
    %Types.BooleanLiteral{source_info: %{text: "true"}} -> true
    %Types.BooleanLiteral{source_info: %{text: "false"}} -> false
    
    %Types.String{children: children} ->
      # Extract string content
      children
      |> Enum.map(&extract_string_content(&1, context))
      |> Enum.join("")
    
    %Types.RshellBinaryExpression{left: l, operator: op, right: r} ->
      left_val = evaluate_rshell_expression(l, context)
      right_val = evaluate_rshell_expression(r, context)
      apply_rshell_operator(op, left_val, right_val)
    
    %Types.VariableReference{children: children} ->
      # Extract variable name from children
      var_name = children
        |> Enum.map(&extract_identifier/1)
        |> Enum.join("")
      Map.get(context.env, var_name)
    
    %Types.VariableName{source_info: %{text: name}} ->
      # Literal variable name (used in property access)
      name
    
    _ -> nil
  end
end

defp parse_number(text) do
  cond do
    String.contains?(text, ".") ->
      {float, ""} = Float.parse(text)
      float
    true ->
      {int, ""} = Integer.parse(text)
      int
  end
end

defp extract_string_content(%Types.StringContent{source_info: %{text: text}}, _context), do: text
defp extract_string_content(_, _context), do: ""

defp apply_rshell_operator(%{source_info: %{text: "+"}}, l, r), do: l + r
defp apply_rshell_operator(%{source_info: %{text: "-"}}, l, r), do: l - r
defp apply_rshell_operator(%{source_info: %{text: "*"}}, l, r), do: l * r
defp apply_rshell_operator(%{source_info: %{text: "/"}}, l, r), do: l / r
defp apply_rshell_operator(%{source_info: %{text: "%"}}, l, r), do: rem(l, r)
defp apply_rshell_operator(%{source_info: %{text: ">"}}, l, r), do: l > r
defp apply_rshell_operator(%{source_info: %{text: "<"}}, l, r), do: l < r
defp apply_rshell_operator(%{source_info: %{text: ">="}}, l, r), do: l >= r
defp apply_rshell_operator(%{source_info: %{text: "<="}}, l, r), do: l <= r
defp apply_rshell_operator(%{source_info: %{text: "=="}}, l, r), do: l == r
defp apply_rshell_operator(%{source_info: %{text: "!="}}, l, r), do: l != r
defp apply_rshell_operator(%{source_info: %{text: "and"}}, l, r), do: l && r
defp apply_rshell_operator(%{source_info: %{text: "or"}}, l, r), do: l || r
defp apply_rshell_operator(%{source_info: %{text: "&&"}}, l, r), do: l && r
defp apply_rshell_operator(%{source_info: %{text: "||"}}, l, r), do: l || r
```

---

### Step 5: Update All Tests

**Goal**: Convert all bash syntax tests to rshell syntax

#### Bash → RShell Syntax Changes:

| Bash Syntax | RShell Syntax | Notes |
|-------------|---------------|-------|
| `X=12` | `X = 12` | Spaces around = |
| `[ "$X" == "12" ]` | `if (X == 12) { }` | Native boolean expressions |
| `arr=(1 2 3)` | `arr = [1, 2, 3]` | Native lists |
| `echo ${arr[0]}` | `echo ${arr[0]}` | Same (array access) |
| `if [ ... ]; then ... fi` | `if (...) { ... }` | C-style braces |
| `for x in $items; do ... done` | `for x in items { ... }` | Clean syntax |

#### Test Migration Example:

**Before** (bash syntax):
```elixir
# test/integration/control_flow_test.exs

test "if statement with variable comparison" do
  script = """
  X=12
  if [ "$X" == "12" ]; then
    echo "matched"
  fi
  """
  
  state = assert_cli_success(script)
  assert_cli_output_contains(state, "matched")
end
```

**After** (rshell syntax):
```elixir
# test/integration/control_flow_test.exs

test "if statement with variable comparison" do
  script = """
  X = 12
  if (X == 12) {
    echo "matched"
  }
  """
  
  state = assert_cli_success(script)
  assert_cli_output_contains(state, "matched")
end
```

#### Test Files to Update:
- `test/integration/cli_test.exs`
- `test/integration/control_flow_test.exs`
- `test/integration/control_flow_math_test.exs`
- `test/integration/incremental_parser_pubsub_test.exs`
- `test/integration/interactive_mode_test.exs`
- `test/integration/parser_runtime_integration_test.exs`
- All example scripts in `examples/rshell/*.rsh`

---

### Step 6: Update CLI and Documentation

#### CLI Changes:
```elixir
# lib/r_shell/cli.ex

def start(opts \\ []) do
  IO.puts("Starting RShell CLI...")
  IO.puts("RShell syntax: X = [1,2,3], if (X > 0) { echo 'positive' }")
  # ...
end
```

#### Documentation Updates:
- Update README.md with RShell syntax examples
- Create MIGRATION_GUIDE.md for bash → rshell conversion
- Update PROMPT.md to reflect rshell as primary syntax
- Add syntax cheat sheet

---

## Migration Timeline

### Week 1: Core Changes

**Day 1-2**: Rust NIF + Type System
- [ ] Update Rust NIF to default to rshell
- [ ] Rename RShellTypes → Types
- [ ] Remove old bash types
- [ ] Rebuild NIF: `cd native/RShell.BashParser && cargo build`
- [ ] Test: `mix test` (expect failures)

**Day 3-4**: Parser + Runtime
- [ ] Update IncrementalParser
- [ ] Add RShell node execution to Runtime
- [ ] Add expression evaluator
- [ ] Test: Unit tests for new nodes

**Day 5**: Test Migration
- [ ] Convert integration tests to rshell syntax
- [ ] Update test helpers
- [ ] Test: `mix test` (all green)

### Week 2: Cleanup + Documentation

**Day 6-7**: Cleanup
- [ ] Remove bash-specific code
- [ ] Update all example scripts
- [ ] Clean up documentation
- [ ] Final testing

**Day 8-9**: Migration Guide
- [ ] Write MIGRATION_GUIDE.md
- [ ] Create syntax comparison table
- [ ] Add troubleshooting section
- [ ] Update README

**Day 10**: Release Preparation
- [ ] Final integration testing
- [ ] Performance benchmarks
- [ ] Create release notes
- [ ] Tag release

---

## Rollback Plan

If major issues arise:

1. **Revert NIF default**:
```rust
// Temporarily revert to bash
Self::new_with_language(max_buffer_size, LanguageType::Bash)
```

2. **Restore old types**:
```bash
mv lib/bash_parser/ast/types_bash_old.ex lib/bash_parser/ast/types.ex
mv lib/bash_parser/ast/types.ex lib/bash_parser/ast/rshell_types.ex
```

3. **Revert commits**:
```bash
git revert HEAD~5..HEAD  # Revert last 5 commits
```

---

## Success Criteria

✅ **Cutover Complete When**:
- All tests pass with rshell syntax
- CLI starts with rshell parser
- Documentation updated
- No bash parser code remains
- Performance matches or exceeds bash parser

✅ **Quality Gates**:
- Test pass rate: 100%
- Performance: < 5% regression
- Documentation: Complete syntax guide
- Examples: All working with rshell syntax

---

## Next Actions

1. **Get approval** for hard cutover approach
2. **Create branch**: `feature/rshell-hard-cutover`
3. **Start Day 1**: Update Rust NIF
4. **Daily standup**: Track progress
5. **Release**: Week 2, Day 10

**Decision Required**: Approve hard cutover?
- ✅ Yes → Proceed with plan
- ❌ No → Fall back to gradual migration plan