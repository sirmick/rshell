# CLI Foundational Refactoring Plan

## Problem Analysis

The current `lib/r_shell/cli.ex` (1282 lines) has serious structural issues:

### 🔴 Critical Issues

1. **Duplicate `is_executable_node?/1`** 
   - Lines 470-479 in `cli.ex` (incomplete - only 5 types)
   - Lines 149-168 in `executor.ex` (complete - all 15 types)
   - **Fix:** Delete from `cli.ex`, import from `BashParser.AST.Types` or create shared module

2. **ExecutionRecord Not Properly Plumbed**
   - `ExecutionRecord` has rich fields (metrics, AST, context)
   - Dot commands (`.result`, `.stdout`, `.stderr`) use `last_result` from loop state
   - `last_result` is built ad-hoc in `build_result_from_context/2`
   - Should use `List.last(state.history)` instead!

3. **Loop State Explosion**
   ```elixir
   loop(parser_pid, runtime_pid, session_id, previous_children, 
        last_incremental, input_buffer, last_result)
   # 7 parameters! Should be a struct
   ```

4. **Helpers Should Use Utils**
   - `format_output/1` (lines 1252-1261) - duplicate of `Utils.format_output/1`
   - `term_to_string/1` (lines 1264-1281) - duplicate of `Utils.term_to_string/1`

5. **File Execution Modes Are Messy**
   - `execute_file/1`, `execute_line_by_line/1`, `execute_parse_only/1`
   - Different output collection mechanisms
   - Should share common code

## Phase 1: Foundation Fixes (No UI changes)

### Step 1: Create Shared AST Module (30 min)

Move AST utilities to `lib/bash_parser/ast/utils.ex`:

```elixir
defmodule BashParser.AST.Utils do
  @moduledoc "Shared AST utilities"
  
  @doc "Check if node is executable"
  def executable?(typed_node) do
    case typed_node do
      %Types.Command{} -> true
      %Types.Pipeline{} -> true
      %Types.List{} -> true
      %Types.Subshell{} -> true
      %Types.CompoundStatement{} -> true
      %Types.ForStatement{} -> true
      %Types.WhileStatement{} -> true
      %Types.IfStatement{} -> true
      %Types.CaseStatement{} -> true
      %Types.FunctionDefinition{} -> true
      %Types.DeclarationCommand{} -> true
      %Types.VariableAssignment{} -> true
      %Types.UnsetCommand{} -> true
      %Types.TestCommand{} -> true
      %Types.CStyleForStatement{} -> true
      _ -> false
    end
  end
  
  @doc "Get node type as string"
  def node_type(node) when is_struct(node) do
    node.__struct__ |> Module.split() |> List.last()
  end
  def node_type(_), do: "Unknown"
  
  @doc "Get node text safely"
  def node_text(%{source_info: %{text: text}}) when is_binary(text), do: text
  def node_text(_), do: nil
  
  @doc "Get node line safely"
  def node_line(%{source_info: %{start_line: line}}) when is_integer(line), do: line
  def node_line(_), do: nil
  
  @doc "Pretty-print AST node"
  def print(node, indent \\ 0) do
    # Move print_typed_ast logic here
  end
end
```

**Update:**
- `cli.ex`: Remove `is_executable_node?/1`, import `AST.Utils`
- `executor.ex`: Remove `is_executable_node?/1`, import `AST.Utils`
- Both: Use `AST.Utils.executable?/1`

### Step 2: Create Interactive Session State (1 hour)

Replace 7-parameter loop with struct:

```elixir
# lib/r_shell/cli/interactive_state.ex
defmodule RShell.CLI.InteractiveState do
  @moduledoc "State for interactive REPL session"
  
  defstruct [
    :parser_pid,
    :runtime_pid,
    :session_id,
    # For .ast/.last commands
    :last_ast_metadata,
    # Input buffer (multi-line accumulation)
    :input_buffer
  ]
  
  def new(parser_pid, runtime_pid, session_id) do
    %__MODULE__{
      parser_pid: parser_pid,
      runtime_pid: runtime_pid,
      session_id: session_id,
      last_ast_metadata: nil,
      input_buffer: ""
    }
  end
  
  # Add execution history from CLI.State
  def get_last_record(%{session_id: session_id}) do
    # Look up from global State registry or pass State through
    # For now, can query parser/runtime for info
  end
end
```

**Update loop signature:**
```elixir
defp loop(%InteractiveState{} = state) do
  prompt = get_prompt(state.input_buffer)
  # ...
  handle_input(state, line)
end
```

### Step 3: Fix Dot Commands to Use ExecutionRecord (1 hour)

Problem: Dot commands use ad-hoc `last_result`, should use `state.history`.

**Solution:** Pass CLI.State through interactive loop:

```elixir
# Option A: Add CLI.State to InteractiveState
defmodule RShell.CLI.InteractiveState do
  defstruct [
    # ... existing fields ...
    :cli_state  # %CLI.State{} with history
  ]
end

# Option B: Query history from separate process
# Not ideal - adds complexity

# Recommendation: Option A
```

**Update dot commands:**
```elixir
defp handle_input(%InteractiveState{} = istate, \".result\") do
  case List.last(istate.cli_state.history) do
    nil -> 
      IO.puts("\\n⚠️  No execution result yet")
    
    %ExecutionRecord{} = record ->
      IO.puts(\"\\n📊 Last Execution Result:\")
      IO.puts(\"Fragment:   #{record.fragment}\")
      IO.puts(\"Timestamp:  #{record.timestamp}\")
      IO.puts(\"Parse Time: #{record.parse_metrics.duration_us}μs\")
      IO.puts(\"Exec Time:  #{record.exec_metrics.duration_us}μs\")
      IO.puts(\"Exit Code:  #{record.exit_code}\")
      
      if record.execution_result do
        IO.puts(\"\\nExecution Details:\")
        IO.puts(\"  Status: #{record.execution_result.status}\")
        IO.puts(\"  Node:   #{record.execution_result.node_type}\")
      end
      
      IO.puts(\"\\nStdout: #{inspect(record.stdout)}\")
      IO.puts(\"Stderr: #{inspect(record.stderr)}\")
  end
  
  loop(istate)
end

defp handle_input(%InteractiveState{} = istate, \".stdout\") do
  case List.last(istate.cli_state.history) do
    nil -> IO.puts("\\n⚠️  No execution yet")
    record -> 
      stdout = RShell.Builtins.Utils.format_output(record.stdout)
      if stdout == "", do: IO.puts("\\n📭 No stdout")
      else IO.write(stdout)
  end
  loop(istate)
end
```

### Step 4: Use Utils Module (30 min)

Replace local helpers:

```elixir
# DELETE from cli.ex (lines 1252-1281)
# defp format_output(...), defp term_to_string(...)

# REPLACE with:
alias RShell.Builtins.Utils

# Use Utils.format_output/1, Utils.term_to_string/1
```

### Step 5: Consolidate File Execution (2 hours)

Create `lib/r_shell/cli/file_executor.ex`:

```elixir
defmodule RShell.CLI.FileExecutor do
  @moduledoc "Execute Bash scripts from files"
  
  def execute_file(path, mode \\\\ :full) do
    case mode do
      :full -> execute_full(path)
      :line_by_line -> execute_incremental(path)
      :parse_only -> parse_only(path)
    end
  end
  
  defp execute_full(path) do
    # Use CLI.execute_string (unified API)
    {:ok, content} = File.read!(path)
    {:ok, state} = RShell.CLI.execute_string(content)
    
    # Display results
    for record <- state.history do
      IO.write(Utils.format_output(record.stdout))
      IO.write(:stderr, Utils.format_output(record.stderr))
    end
  end
  
  defp execute_incremental(path) do
    # Use CLI.execute_lines (unified API)
    {:ok, content} = File.read!(path)
    {:ok, state} = RShell.CLI.execute_lines(content)
    
    # Results already displayed during execution
    :ok
  end
  
  defp parse_only(path) do
    {:ok, content} = File.read!(path)
    {:ok, ast} = BashParser.parse_bash(content)
    typed_ast = BashParser.AST.Types.from_map(ast)
    
    IO.puts(\"✅ Parse successful!\\n\")
    BashParser.AST.Utils.print(typed_ast)
  end
end
```

**Update `cli.ex` main/1:**
```elixir
defp main(args) do
  case args do
    [] -> execute_interactive()
    [file] -> FileExecutor.execute_file(file, :full)
    ["--line-by-line", file] -> FileExecutor.execute_file(file, :line_by_line)
    ["--parse-only", file] -> FileExecutor.execute_file(file, :parse_only)
    # ...
  end
end
```

## Phase 2: Split Interactive Module (3 hours)

After Phase 1 fixes, split `cli.ex`:

```
lib/r_shell/cli.ex                    # 100-200 lines (entry point, public API)
├── execute_string/2                  # Keep
├── execute_lines/2                   # Keep  
├── reset/1                           # Keep
└── main/1                            # Route to modes

lib/r_shell/cli/
├── interactive.ex                    # NEW - REPL loop (400 lines)
│   ├── start/0
│   ├── loop/1  
│   └── handle_input/2 (all dot commands)
├── interactive_state.ex              # NEW - Session state (50 lines)
├── file_executor.ex                  # NEW - File modes (150 lines)
├── executor.ex                       # EXISTS - Execute fragments
├── state.ex                          # EXISTS - CLI state
├── metrics.ex                        # EXISTS - Metrics
└── execution_record.ex               # EXISTS - Record struct
```

**New `cli/interactive.ex`:**
```elixir
defmodule RShell.CLI.Interactive do
  @moduledoc "Interactive REPL mode"
  
  alias RShell.CLI.{State, InteractiveState}
  alias RShell.{IncrementalParser, Runtime, InputBuffer}
  
  def start(opts \\\\ []) do
    # Setup
    {:ok, cli_state} = State.new(opts)
    
    istate = InteractiveState.new(
      cli_state.parser_pid,
      cli_state.runtime_pid,
      cli_state.session_id
    )
    |> InteractiveState.set_cli_state(cli_state)
    
    print_welcome()
    loop(istate)
  end
  
  defp loop(%InteractiveState{} = istate) do
    prompt = get_prompt(istate.input_buffer)
    
    case IO.gets(prompt) do
      :eof -> goodbye()
      {:error, reason} -> handle_error(reason, istate)
      line -> handle_input(istate, String.trim_trailing(line, "\\n"))
    end
  end
  
  # Dot command handlers (move from cli.ex)
  defp handle_input(istate, ".quit"), do: goodbye()
  defp handle_input(istate, ".help"), do: show_help() |> then(fn _ -> loop(istate) end)
  # ... etc
end
```

## Phase 3: Rich Terminal UI (Future - After Foundation Fixed)

Once the code is clean, consider:
- **Ratatouille** for TUI (panels, syntax highlighting)
- **Owl** for live widgets (status bar, progress)
- Custom readline features (history, completion)

## Summary of Fixes

### Immediate (Phase 1 - 5 hours)

| Issue | Fix | Files Changed |
|-------|-----|---------------|
| Duplicate `is_executable_node?/1` | Create `BashParser.AST.Utils` | `cli.ex`, `executor.ex`, new file |
| ExecutionRecord not used | Use `state.history` in dot commands | `cli.ex` |
| 7-parameter loop | Create `InteractiveState` struct | `cli.ex`, new file |
| Duplicate helpers | Use `Utils` module | `cli.ex` |
| File execution mess | Consolidate in `FileExecutor` | `cli.ex`, new file |

### Result After Phase 1

- **`cli.ex`**: 1282 → ~400 lines (remove file exec, consolidate helpers)
- **New files**: 3 (AST.Utils, InteractiveState, FileExecutor)
- **Cleaner**: All execution uses unified API (`execute_string`, `execute_lines`)
- **Testable**: Each piece isolated and testable
- **No UI changes**: Just internal cleanup

### Phase 2 (Optional - 3 hours)

Split interactive mode into separate module:
- **`cli.ex`**: ~100-200 lines (API + routing only)
- **`cli/interactive.ex`**: ~400 lines (REPL logic)

## Next Steps

1. **Start with Phase 1, Step 1**: Create `BashParser.AST.Utils`
2. **Test after each step**: Run `mix test` to ensure no regressions
3. **Commit after each step**: Small, atomic commits
4. **Phase 2 is optional**: Only if you want maximum modularity

Ready to start? Let's begin with Step 1: Create `BashParser.AST.Utils`.
