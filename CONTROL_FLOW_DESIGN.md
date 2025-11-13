# Control Flow Execution Design

**Status**: Design Document  
**Last Updated**: 2025-11-13

---

## Overview

This document describes the implementation plan for executing control flow statements (if, for, while) in the RShell runtime. The design is based on analysis of actual AST structures from tree-sitter-bash.

---

## AST Structure Analysis

### If Statement

**Observed Structure** (from test output):
```elixir
%BashParser.AST.Types.IfStatement{
  condition: [
    %Types.Command{...},  # true
    %Types.Command{...}   # false  
  ],
  children: [
    %Types.Command{...},           # then-body command
    %Types.ElseClause{
      children: [%Types.Command{...}]  # else-body command
    }
  ]
}
```

**Key Observations**:
- `condition`: List of commands to execute (last exit code determines branch)
- `children`: Mixed list containing:
  - Then-body nodes (commands that aren't ElifClause/ElseClause)
  - Optional ElifClause nodes
  - Optional ElseClause node

**Execution Strategy**:
1. Execute all commands in `condition` list sequentially
2. Use final `exit_code` from context to determine branch
3. If `exit_code == 0`: Execute then-body (first non-elif/else child)
4. If `exit_code != 0`: Check elif clauses, then else clause

### For Statement

**Expected Structure** (from types.ex):
```elixir
%BashParser.AST.Types.ForStatement{
  variable: %Types.VariableName{source_info: %{text: "i"}},
  value: [%Types.Word{...}, %Types.Word{...}],  # iteration values
  body: %Types.DoGroup{
    children: [%Types.Command{...}]
  }
}
```

**Key Observations**:
- `variable`: Single VariableName node with loop variable name
- `value`: List of word nodes to iterate over (may contain expansions)
- `body`: DoGroup containing commands to execute each iteration

**Execution Strategy** (with native type support):
1. Extract variable name from `variable.source_info.text`
2. Extract values from `value` list with `extract_loop_values/2`:
   - Expand variables via `extract_text_from_node/2` (preserves native types!)
   - If value is a **native list**: return elements directly
   - If value is a **native map**: return `[map]`
   - If value is a **string**: split on whitespace (traditional bash)
   - If value is **other native type** (number, boolean): return `[value]`
3. For each value (which may be native Elixir type):
   - Set `context.env[var_name] = value` (stores native value!)
   - Execute DoGroup body with updated context
4. Loop variable persists after loop with last value (bash behavior)

**Critical**: This design preserves RShell's native type system through for loops, enabling iteration over structured data!

### While Statement

**Expected Structure** (from types.ex):
```elixir
%BashParser.AST.Types.WhileStatement{
  condition: [%Types.Command{...}],
  body: %Types.DoGroup{
    children: [%Types.Command{...}]
  }
}
```

**Key Observations**:
- `condition`: List of commands (last exit code determines continuation)
- `body`: DoGroup containing loop body

**Execution Strategy**:
1. Execute `condition` commands
2. If `exit_code == 0`: Execute body, repeat from step 1
3. If `exit_code != 0`: Exit loop
4. Return final context

---

## Implementation Plan

### Phase 1: Helper Functions

**New helper functions needed in runtime.ex**:

```elixir
# Execute a list of commands sequentially, returning final context
defp execute_command_list(nodes, context, session_id)

# Execute DoGroup, CompoundStatement, or single node
defp execute_do_group_or_node(node, context, session_id)

# Extract variable name from VariableName node
defp extract_variable_name(%Types.VariableName{source_info: info})

# Extract iteration values from for statement value nodes
defp extract_loop_values(value_nodes, context)
```

### Phase 2: If Statement Implementation

**Function signature**:
```elixir
defp execute_if_statement(
  %Types.IfStatement{condition: condition_nodes, children: children},
  context,
  session_id
)
```

**Algorithm**:
```
1. condition_context = execute_command_list(condition_nodes, context, session_id)
2. IF condition_context.exit_code == 0:
   a. Find first child that is NOT ElifClause or ElseClause (then-body)
   b. Execute then-body with condition_context
3. ELSE:
   a. Filter children for ElifClause nodes
   b. For each elif:
      - Execute elif condition commands
      - If exit_code == 0: execute elif body, return
   c. If no elif matched, find ElseClause
   d. If ElseClause exists: execute else body
4. Return final context
```

**Edge Cases**:
- No else clause: return context from condition
- Empty then-body: return condition context
- Multiple elif clauses: evaluate in order, first match wins

### Phase 3: For Statement Implementation

**Function signature**:
```elixir
defp execute_for_statement(
  %Types.ForStatement{variable: var_node, value: value_nodes, body: body},
  context,
  session_id
)
```

**Algorithm**:
```
1. var_name = extract_variable_name(var_node)
2. values = extract_loop_values(value_nodes, context)
3. final_context = Enum.reduce(values, context, fn value, acc_context ->
     a. new_env = Map.put(acc_context.env, var_name, value)
     b. loop_context = %{acc_context | env: new_env}
     c. execute_do_group_or_node(body, loop_context, session_id)
   end)
4. Return final_context
```

**Edge Cases**:
- Empty value list: Don't execute body, return context unchanged
- Value expansion: `$VAR` in values should expand before iteration
- Word splitting: Split expanded values on whitespace

### Phase 4: While Statement Implementation

**Function signature**:
```elixir
defp execute_while_statement(
  %Types.WhileStatement{condition: condition_nodes, body: body},
  context,
  session_id
)
```

**Algorithm** (recursive):
```
defp execute_while_loop(condition_nodes, body, context, session_id):
  1. condition_context = execute_command_list(condition_nodes, context, session_id)
  2. IF condition_context.exit_code != 0:
     RETURN condition_context  # Exit loop
  3. body_context = execute_do_group_or_node(body, condition_context, session_id)
  4. RETURN execute_while_loop(condition_nodes, body, body_context, session_id)
```

**Edge Cases**:
- Infinite loop protection: None (bash allows infinite loops)
- Condition never true: Don't execute body
- Tail-call optimization: Elixir handles this naturally

---

## Helper Function Implementations

### execute_command_list/3

```elixir
defp execute_command_list(nodes, context, session_id) when is_list(nodes) do
  Enum.reduce(nodes, context, fn node, acc_context ->
    simple_execute(node, acc_context, session_id)
  end)
end
defp execute_command_list(_, context, _session_id), do: context
```

**Purpose**: Execute multiple commands sequentially, threading context through each.

### execute_do_group_or_node/3

```elixir
defp execute_do_group_or_node(%Types.DoGroup{children: children}, context, session_id) do
  execute_command_list(children, context, session_id)
end

defp execute_do_group_or_node(%Types.CompoundStatement{children: children}, context, session_id) do
  execute_command_list(children, context, session_id)
end

defp execute_do_group_or_node(node, context, session_id) when is_struct(node) do
  simple_execute(node, context, session_id)
end

defp execute_do_group_or_node(_, context, _session_id), do: context
```

**Purpose**: Handle both DoGroup wrappers and direct nodes.

### extract_loop_values/2

```elixir
defp extract_loop_values(nil, _context), do: []
defp extract_loop_values([], _context), do: []
defp extract_loop_values(value_nodes, context) when is_list(value_nodes) do
  value_nodes
  |> Enum.flat_map(fn node ->
    value = extract_text_from_node(node, context)
    
    # CRITICAL: Variable expansion preserves native types!
    # $A where A=[1,2,3] returns [1,2,3], NOT string "[1, 2, 3]"
    # This is RShell's key enhancement over traditional bash
    case value do
      # Native list - iterate over elements
      list when is_list(list) ->
        list
      
      # Native map - single value
      map when is_map(map) ->
        [map]
      
      # String - split on whitespace (traditional bash)
      string when is_binary(string) ->
        String.split(string, ~r/\s+/, trim: true)
      
      # Other native types (numbers, booleans, atoms)
      other ->
        [other]
    end
  end)
end
```

**Purpose**: Extract and expand iteration values, **preserving native types** from variable expansion.

**Key Insight**: This is the mechanism that enables RShell's native type system to work correctly in for loops. When `extract_text_from_node/2` extracts `$A` where `A=[1,2,3]`, it returns the **native Elixir list** `[1,2,3]`, not the string `"[1, 2, 3]"`. The case statement then detects this is a list and returns the elements directly for iteration.

**Example**:
```bash
export A=[1,2,3]
for i in $A; do echo $i; done
# Output: 1, 2, 3 (iterates over list elements)
```

Without this native type detection, it would incorrectly split the string representation, yielding `["[1,", "2,", "3]"]`.

---

## Integration Points

### Existing Runtime Functions

**Functions we'll reuse**:
- `simple_execute/3` - Execute any AST node (recursive)
- `extract_text_from_node/2` - Extract text with variable expansion
- Context threading - All functions take and return context

**Modification needed**:
```elixir
# In simple_execute/3, replace raises with function calls
%Types.IfStatement{} = stmt ->
  execute_if_statement(stmt, new_context, session_id)

%Types.ForStatement{} = stmt ->
  execute_for_statement(stmt, new_context, session_id)

%Types.WhileStatement{} = stmt ->
  execute_while_statement(stmt, new_context, session_id)
```

---

## Testing Strategy

### Test Coverage

Created `test/control_flow_test.exs` with:
- **If statements**: 6 tests (then, else, elif, nested, multi-condition)
- **For loops**: 5 tests (explicit values, expansion, nesting, persistence)
- **While loops**: 4 tests (iteration, exit condition, nesting)
- **Mixed**: 3 tests (if-in-for, for-in-if, while-in-if)

### Test Approach

1. Use IncrementalParser + Runtime integration (realistic scenario)
2. Subscribe to PubSub events (`:stdout`, `:stderr`, `:executable`)
3. Verify output and context state
4. Test nested structures and edge cases

---

## Known Limitations

### Not Implementing (Yet)

- `break`/`continue` statements
- `until` loops (similar to while)
- C-style for loops `for ((i=0; i<10; i++))`
- `select` statements
- `case` statements (separate implementation)

### Assumptions

- External commands (true/false) must be implemented as builtins
- No infinite loop protection (matches bash behavior)
- Variable scoping is global (matches bash behavior)
- No subshell isolation for control flow bodies

---

## Summary

This design provides a clear path to implementing control flow:

1. ✅ **Analyzed actual AST structures** from parser output
2. ✅ **Created comprehensive tests** (18 test cases)
3. **Next**: Implement helper functions
4. **Then**: Implement if/for/while execution
5. **Finally**: Verify all tests pass

The approach reuses existing runtime infrastructure (context threading, `simple_execute`, variable expansion) and follows the project's test-first philosophy.

---

## Advanced Topics: Value Extraction & Type Handling

### Question 1: For Loop Value Parsing

**Input**: `for i in 1 2 3; do`

**AST Structure**:
```elixir
%Types.ForStatement{
  variable: %Types.VariableName{source_info: %{text: "i"}},
  value: [
    %Types.Word{source_info: %{text: "1"}},
    %Types.Word{source_info: %{text: "2"}},
    %Types.Word{source_info: %{text: "3"}}
  ],
  body: %Types.DoGroup{...}
}
```

**Processing**:
1. Parser creates separate Word nodes for each space-separated value
2. Each Word node has `source_info.text` containing the literal value
3. `extract_loop_values/2` extracts text from each Word node
4. Result: `["1", "2", "3"]` as strings

**Implementation** (UPDATED for native type support):
```elixir
defp extract_loop_values(value_nodes, context) do
  value_nodes
  |> Enum.flat_map(fn node ->
    value = extract_text_from_node(node, context)
    
    # CRITICAL: Preserve native types from variable expansion!
    case value do
      list when is_list(list) -> list
      map when is_map(map) -> [map]
      string when is_binary(string) -> String.split(string, ~r/\s+/, trim: true)
      other -> [other]
    end
  end)
end
```

**Key Change**: Instead of blindly converting to strings with `to_string(value)`, we now detect native types from variable expansion. This enables `for i in $A` where `A=[1,2,3]` to iterate over elements `1, 2, 3` as native numbers, not the split string `["[1,", "2,", "3]"]`.

### Question 2: Command Substitution in For Loop

**Input**: `for i in $(builtin); do` or `for i in \`builtin\`; do`

**AST Structure**:
```elixir
%Types.ForStatement{
  variable: %Types.VariableName{...},
  value: [
    %Types.CommandSubstitution{
      children: [%Types.Command{name: "builtin", ...}]
    }
  ],
  body: %Types.DoGroup{...}
}
```

**Challenge**: Command substitution needs to be **executed** to get values.

**Current Status**: ⚠️ **NOT YET IMPLEMENTED**

**Design Considerations**:

#### Option 1: Execute Command Substitution in extract_loop_values/2

```elixir
defp extract_loop_values(value_nodes, context) do
  value_nodes
  |> Enum.flat_map(fn node ->
    case node do
      %Types.CommandSubstitution{children: commands} ->
        # Execute command substitution
        result_context = execute_command_list(commands, context, session_id)
        
        # Get output from context
        output = List.first(result_context.output) || ""
        
        # Split output on whitespace (bash behavior)
        String.split(output, ~r/\s+/, trim: true)
      
      %Types.Word{} ->
        # Regular word - extract with native type awareness
        value = extract_text_from_node(node, context)
        
        # CRITICAL: extract_text_from_node can return native types!
        # (from variable expansion: $A where A=[1,2,3] returns list)
        case value do
          # Native list - iterate over elements
          list when is_list(list) ->
            list
          
          # Native map - single value
          map when is_map(map) ->
            [map]
          
          # String - split on whitespace (traditional bash)
          string when is_binary(string) ->
            String.split(string, ~r/\s+/, trim: true)
          
          # Other native types (numbers, booleans, atoms)
          other ->
            [other]
        end
      
      _ ->
        # Other node types - extract text
        [extract_text_from_node(node, context)]
    end
  end)
end
```

**Problem**: Needs `session_id` parameter, circular dependency.

#### Option 2: Pre-process Command Substitutions Before Loop

```elixir
defp execute_for_statement(%Types.ForStatement{variable: var_node, value: value_nodes, body: body}, context, session_id) do
  # Step 1: Expand command substitutions
  expanded_values = expand_command_substitutions(value_nodes, context, session_id)
  
  # Step 2: Extract text and split
  values = expanded_values
    |> Enum.map(&extract_text_from_node(&1, context))
    |> Enum.flat_map(&String.split(to_string(&1), ~r/\s+/, trim: true))
  
  # Step 3: Iterate
  var_name = extract_variable_name(var_node)
  Enum.reduce(values, context, fn value, acc_context ->
    new_env = Map.put(acc_context.env, var_name, value)
    loop_context = %{acc_context | env: new_env}
    execute_do_group_or_node(body, loop_context, session_id)
  end)
end

defp expand_command_substitutions(nodes, context, session_id) do
  Enum.flat_map(nodes, fn node ->
    case node do
      %Types.CommandSubstitution{children: commands} ->
        # Execute command, capture output
        result_context = execute_command_list(commands, context, session_id)
        output = materialize_output(List.first(result_context.output) || "")
        
        # Return synthetic Word nodes with output
        output
        |> String.split(~r/\s+/, trim: true)
        |> Enum.map(fn word ->
          %Types.Word{source_info: %{text: word}}
        end)
      
      other_node ->
        [other_node]
    end
  end)
end
```

**Preferred**: Option 2 - cleaner separation of concerns.

### Strongly-Typed Stream Values

**Question**: Can loop variable `i` be strongly typed to stream items?

**Answer**: Not directly in bash model, but we can preserve native types!

**Current Behavior** (from builtins):
- Builtin `echo` returns `{context, stdout, stderr, exit_code}`
- `stdout` can be a **Stream** (lazy evaluation)
- Output is materialized to string for display

**Proposed Enhancement for For Loops**:

```elixir
# In execute_for_statement
case node do
  %Types.CommandSubstitution{children: commands} ->
    result_context = execute_command_list(commands, context, session_id)
    
    # Check if output is a Stream
    output = List.first(result_context.output)
    
    case output do
      stream when is_function(stream) ->
        # Stream of native values - preserve types!
        stream
        |> Enum.map(fn item ->
          # Item could be string, map, list, etc.
          # Store native value in context.env
          item
        end)
      
      string when is_binary(string) ->
        # String output - split on whitespace
        String.split(string, ~r/\s+/, trim: true)
    end
end
```

**Benefits**:
- Loop variable `i` can hold **native Elixir values** (maps, lists, numbers)
- Builtins that return JSON can iterate over structured data
- No string conversion needed if next command is also a builtin

**Example**:
```bash
# Hypothetical: builtin returns stream of maps
for item in $(json_builtin); do
  echo ${item.name}  # Access map field directly
done
```

**Implementation Status**: ⚠️ **Future Enhancement**

**Updated Implementation Plan** (aligned with ENV_VAR_DESIGN.md):

1. **Phase 1**: Basic control flow (current design)
   - If/while/for with literal string values
   - Variable expansion using existing `extract_text_from_node/2`
   - Word splitting on whitespace

2. **Phase 2**: Command substitution + ENV_VAR integration
   - Execute `CommandSubstitution` nodes
   - Use `RShell.EnvJSON.parse/1` for JSON detection
   - Split output into iteration values
   - Variable expansion with `RShell.EnvJSON.encode/1`

3. **Phase 3**: Native type iteration (RShell enhancement)
   - Detect Stream output from builtins
   - Iterate over native Elixir types (maps, lists, etc.)
   - Use `RShell.EnvJSON` for JSON round-tripping
   - Enable structured data loops with existing env var infrastructure

---

## Updated Implementation Phases

### Phase 1: Basic Control Flow (Current Design)
- If/while/for with literal values
- Variable expansion in values
- Word splitting on whitespace

### Phase 2: Command Substitution Support
- Detect `CommandSubstitution` nodes in value lists
- Execute commands and capture output
- Split output into iteration values

### Phase 3: Native Type Preservation (RShell Enhancement)

**Goal**: Enable iteration over native Elixir types from builtin streams, not just strings.

#### For Loop: Stream Iteration

**Traditional Bash Behavior**:
```bash
# Output is always strings
for i in $(echo "a b c"); do
  echo $i  # i is always a string
done
```

**RShell Enhancement**:
```bash
# Builtin returns stream of maps
for item in $(json_parse '{"items": [{"id": 1}, {"id": 2}]}'); do
  echo $item.id  # item is a map! Access fields directly
done
```

**Implementation**:

```elixir
defp execute_for_statement(%Types.ForStatement{variable: var_node, value: value_nodes, body: body}, context, session_id) do
  var_name = extract_variable_name(var_node)
  
  # Extract values with native type support
  values = extract_loop_values_typed(value_nodes, context, session_id)
  
  # Iterate over native values
  Enum.reduce(values, context, fn value, acc_context ->
    # Store native value in env (not converted to string!)
    new_env = Map.put(acc_context.env, var_name, value)
    loop_context = %{acc_context | env: new_env}
    execute_do_group_or_node(body, loop_context, session_id)
  end)
end

defp extract_loop_values_typed(value_nodes, context, session_id) do
  value_nodes
  |> Enum.flat_map(fn node ->
    case node do
      %Types.CommandSubstitution{children: commands} ->
        # Execute command substitution
        result_context = execute_command_list(commands, context, session_id)
        output = List.first(result_context.output)
        
        case output do
          # Stream of native values (from builtin)
          stream when is_function(stream) ->
            stream
            |> Enum.to_list()
            # Values are already native types!
          
          # String output (traditional bash)
          string when is_binary(string) ->
            String.split(string, ~r/\s+/, trim: true)
          
          # Single native value
          other ->
            [other]
        end
      
      %Types.Word{} ->
        # Regular word - extract with native type awareness
        value = extract_text_from_node(node, context)
        
        case value do
          list when is_list(list) -> list
          map when is_map(map) -> [map]
          string when is_binary(string) -> String.split(string, ~r/\s+/, trim: true)
          other -> [other]
        end
      
      _ ->
        value = extract_text_from_node(node, context)
        case value do
          list when is_list(list) -> list
          other -> [other]
        end
    end
  end)
end
```

**Key Features**:
- Loop variable holds **native Elixir types** (maps, lists, numbers, atoms)
- No string conversion if not needed
- Builtins can return structured data streams
- Backwards compatible: strings still work

**Example Use Cases**:

```bash
# Iterate over JSON array
for user in $(cat users.json | jq '.users'); do
  echo "User: $user.name, Age: $user.age"
done

# Iterate over structured env data
for setting in $(env --json); do
  echo "Key: $setting.key, Value: $setting.value"
done

# Mix native and string values
for item in $(json_builtin) "literal_string" $OTHER_VAR; do
  # item can be map, string, or whatever $OTHER_VAR is
  echo $item
done
```

#### While Loop: Structured Condition Evaluation

**Traditional Bash Behavior**:
```bash
# Condition is always exit code (0 or non-zero)
while test $count -lt 10; do
  # ...
done
```

**RShell Enhancement - Option A: Native Predicates**:
```bash
# Builtin returns boolean map
while $(has_more_items); do
  item=$(get_next_item)
  echo $item.name
done
```

**Implementation**:

```elixir
defp execute_while_loop(condition_nodes, body, context, session_id) do
  # Execute condition with native type awareness
  condition_context = execute_command_list(condition_nodes, context, session_id)
  
  # Evaluate condition (supports both exit codes and native booleans)
  should_continue = evaluate_condition(condition_context)
  
  if should_continue do
    body_context = execute_do_group_or_node(body, condition_context, session_id)
    execute_while_loop(condition_nodes, body, body_context, session_id)
  else
    condition_context
  end
end

defp evaluate_condition(context) do
  case context.exit_code do
    0 -> true   # Traditional: exit code 0 = success
    _ ->
      # RShell enhancement: check if builtin returned native boolean
      last_output = List.first(context.output)
      
      case last_output do
        # Stream that yields boolean
        stream when is_function(stream) ->
          stream |> Enum.take(1) |> List.first() == true
        
        # Direct boolean value
        true -> true
        false -> false
        
        # String "true"/"false"
        "true" -> true
        "false" -> false
        
        # Default: non-zero exit = false
        _ -> false
      end
  end
end
```

**RShell Enhancement - Option B: Iterate Until Stream Empty**:
```bash
# Stream-based while loop
while item in $(stream_items); do
  echo "Processing: $item.name"
  # Loop continues while stream has items
done
```

**Implementation**:

```elixir
# New syntax: while VAR in STREAM
%Types.WhileStatement{
  variable: %Types.VariableName{...},  # Loop variable (like for)
  stream: %Types.CommandSubstitution{...},  # Stream source
  body: %Types.DoGroup{...}
}

defp execute_while_stream(var_name, stream_source, body, context, session_id) do
  # Execute stream command once
  stream_context = execute_command_substitution(stream_source, context, session_id)
  stream = List.first(stream_context.output)
  
  case stream do
    stream when is_function(stream) ->
      # Iterate over stream lazily
      Enum.reduce_while(stream, stream_context, fn item, acc_context ->
        # Set loop variable to current item
        new_env = Map.put(acc_context.env, var_name, item)
        loop_context = %{acc_context | env: new_env}
        
        # Execute body
        body_context = execute_do_group_or_node(body, loop_context, session_id)
        
        # Continue iteration
        {:cont, body_context}
      end)
    
    _ ->
      # Not a stream, fall back to traditional while
      execute_while_loop([stream_source], body, context, session_id)
  end
end
```

**Benefits of Option B**:
- Natural stream consumption
- Lazy evaluation (process items as they arrive)
- Automatic loop termination when stream ends
- Memory efficient for large datasets

**Example**:
```bash
# Process large file stream without loading all in memory
while line in $(cat huge_file.txt); do
  echo "Line: $line"
done

# Process infinite stream with break condition
while event in $(listen_events); do
  if test $event.type = "shutdown"; then
    break
  fi
  process_event $event
done
```

#### Design Decision: Which While Approach?

**Recommendation**: **Implement Both**

1. **Traditional While** (Phase 1): Exit code based
   - `while COMMANDS; do BODY; done`
   - Evaluates exit code for continuation

2. **Enhanced While** (Phase 3a): Native boolean support
   - Same syntax, but supports native boolean returns
   - Backwards compatible

3. **Stream While** (Phase 3b): New syntax
   - `while VAR in $(STREAM); do BODY; done`
   - Dedicated stream iteration
   - Explicit about stream consumption

**Syntax Disambiguation**:
```bash
# Traditional (exit code)
while test $x -lt 10; do ... done

# Enhanced (native boolean)
while $(has_more); do ... done  # Builtin returns boolean

# Stream iteration (new syntax)
while item in $(stream); do ... done  # Explicit 'in'
```

#### Type Safety in Context.env

**Current**: `context.env` is `%{String.t() => String.t()}`

**Enhanced**: `context.env` is `%{String.t() => any()}`

**Implementation**:

```elixir
# Update context type spec
@type context :: %{
  env: %{String.t() => any()},  # Changed from String.t()
  cwd: String.t(),
  exit_code: integer(),
  command_count: integer(),
  output: [any()],  # Can be streams, strings, native types
  errors: [String.t()]
}
```

**Variable Expansion with Native Types**:

```elixir
defp extract_text_from_node(%Types.SimpleExpansion{children: children}, context) do
  var_name = children |> Enum.map(&extract_variable_name/1) |> Enum.join("")
  
  case Map.get(context.env || %{}, var_name) do
    nil -> ""
    
    # Native types - preserve for builtin commands
    value when is_map(value) or is_list(value) ->
      value  # Pass native type to next command
    
    # String - return as-is
    value when is_binary(value) ->
      value
    
    # Other types - convert to string only when needed
    value ->
      to_string(value)
  end
end
```

**When to Convert to String**:
- **External commands**: Always convert (spawn expects strings)
- **Builtin commands**: Preserve native types
- **String concatenation**: Convert as needed
- **Output display**: Convert for stdout

#### Benefits of Phase 3

1. **Powerful Data Processing**:
   - Iterate over JSON/structured data directly
   - No string parsing needed
   - Type-safe operations

2. **Performance**:
   - No unnecessary serialization/deserialization
   - Stream processing for large datasets
   - Lazy evaluation

3. **Elixir Integration**:
   - Builtins return native Elixir types
   - Seamless interop with Elixir libraries
   - Full power of pattern matching

4. **Backwards Compatible**:
   - Traditional bash scripts still work
   - Strings are just one type of value
   - Gradual enhancement path


---

## Implementation Status

**Last Updated**: 2025-11-13

### ✅ Completed

**Core Control Flow Implementation** (lines 480-632 in [`lib/r_shell/runtime.ex`](lib/r_shell/runtime.ex:480))

1. **Helper Functions**:
   - [`execute_command_list/3`](lib/r_shell/runtime.ex:485) - Execute commands sequentially
   - [`execute_do_group_or_node/3`](lib/r_shell/runtime.ex:493) - Handle DoGroup/CompoundStatement
   - [`extract_loop_values/2`](lib/r_shell/runtime.ex:508) - Extract values with **native type preservation**

2. **Control Flow Functions**:
   - [`execute_if_statement/3`](lib/r_shell/runtime.ex:542) - If/elif/else execution
   - [`execute_elif_else_chain/3`](lib/r_shell/runtime.ex:559) - Elif/else processing
   - [`try_elif_clauses/3`](lib/r_shell/runtime.ex:582) - Recursive elif matching
   - [`execute_for_statement/3`](lib/r_shell/runtime.ex:597) - For loop with native types
   - [`execute_while_statement/3`](lib/r_shell/runtime.ex:614) - While loop entry
   - [`execute_while_loop/4`](lib/r_shell/runtime.ex:619) - Recursive while execution

3. **Integration**:
   - Updated [`simple_execute/3`](lib/r_shell/runtime.ex:227) to dispatch control flow

4. **Builtins**:
   - [`true` builtin](lib/r_shell/builtins.ex:215) - Returns exit code 0
   - [`false` builtin](lib/r_shell/builtins.ex:230) - Returns exit code 1

### ⏳ Pending Dependencies

**Blocking Test Failures** (6 tests):
1. **DeclarationCommand** not implemented - See [`ENV_VAR_DESIGN.md:742`](ENV_VAR_DESIGN.md:742)
   - Tests use `export COUNT=0` statements
   - Needs: Variable assignment extraction and context update
   - Priority: High (blocks all control flow tests that use export)

2. **`test` builtin** not implemented
   - Tests use `test $n -eq 2` for conditionals
   - Needs: Full conditional expression evaluation
   - Priority: Medium (user planning enhanced version)

3. **Arithmetic expansion** not evaluated
   - Tests use `$((COUNT + 1))` expressions
   - Needs: BinaryExpression/ArithmeticExpansion execution
   - Priority: Medium

### 📊 Test Results

**Total**: 408 tests (22 doctests + 386 regular tests)
- **Passing**: 402 tests (98.5%)
- **Failing**: 6 tests (all control flow tests blocked by dependencies)
- **Status**: ✅ No regressions - all existing tests still pass!

**Control Flow Tests** (18 total):
- **Passing**: 12 tests (66.7%)
  - Basic if/for/while structure works
  - Nested control flow works
  - Empty iteration works
  - Native type iteration works (for loops with `[1,2,3]`)
- **Failing**: 6 tests (33.3%)
  - All blocked by missing `DeclarationCommand` execution
  - All blocked by missing `test` builtin

### 🎯 Implementation Quality

**What Works**:
- ✅ If/elif/else chain evaluation
- ✅ For loop iteration (explicit values and native types)
- ✅ While loop with condition checking
- ✅ Nested control flow structures
- ✅ Context threading through all operations
- ✅ Native type preservation in for loops
- ✅ DoGroup and CompoundStatement handling

**Design Achievements**:
- ✅ Clean separation of helper functions
- ✅ Recursive patterns for elif and while
- ✅ Native type support throughout
- ✅ Zero impact on existing functionality

### 📝 Next Steps

1. **Immediate** (to unblock tests):
   - Implement basic `DeclarationCommand` execution
   - Extract variable assignments from AST
   - Update context.env with new values

2. **Short-term**:
   - Implement `test` builtin (or wait for enhanced version)
   - Add arithmetic expansion evaluation

3. **Future Enhancements**:
   - `break`/`continue` statements
   - `until` loops
   - C-style for loops
   - `case` statements
   - Command substitution in for loops

### 🔗 Related Documents

- [`ENV_VAR_DESIGN.md:742`](ENV_VAR_DESIGN.md:742) - DeclarationCommand TODO
- [`RUNTIME_DESIGN.md`](RUNTIME_DESIGN.md:1) - Context structure
- [`README.md`](README.md:1) - Native type examples
- [`test/control_flow_test.exs`](test/control_flow_test.exs:1) - 18 comprehensive tests

### 💡 Key Innovations

1. **Native Type Iteration**: For loops can iterate over Elixir lists/maps directly
   ```elixir
   # Variable expansion returns native list [1, 2, 3]
   for i in $A where A=[1,2,3]
   # Iterates over elements 1, 2, 3 as numbers!
   ```

2. **Type Boundaries Respected**: Conversion to strings only at:
   - Concatenation operations
   - External command arguments
   - Terminal display

3. **Elif Structure Fixed**: Correctly handles ElifClause AST node structure
   - ElifClause has only `source_info` and `children` fields
   - Condition and body are mixed in children (similar to IfStatement)

### Phase 3: Native Type Preservation (Future)