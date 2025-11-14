defmodule RShell.CLI do
  @moduledoc """
  Multi-mode CLI for Bash parsing and execution.

  ## Execution Modes

  1. **File Execution** (one-shot): `./rshell script.sh`
     - Parse entire file and execute immediately

  2. **Interactive** (REPL): `./rshell`
     - Interactive prompt with line-by-line parsing

  3. **Line-by-Line File**: `./rshell --line-by-line script.sh`
     - Process file line-by-line through InputBuffer (for testing)

  4. **Parse-Only**: `./rshell --parse-only script.sh`
     - Parse and display AST without execution

  ## Interactive Commands

  - `.reset` - Clear parser state
  - `.status` - Show parser/runtime status
  - `.ast` - Show full accumulated AST (all commands entered)
  - `.last` - Show incremental changes from last parse
  - `.help [builtin]` - Show help
  - `.quit` / `.exit` - Exit
  """

  alias RShell.{IncrementalParser, Runtime, PubSub, InputBuffer}
  alias RShell.CLI.{Executor, State}
  alias BashParser.AST.Types

  @commands %{
    ".reset" => "Clear parser state and start fresh",
    ".status" => "Show current parser status (buffer size, errors)",
    ".ast" => "Show full accumulated AST (all commands entered)",
    ".last" => "Show incremental changes from last parse",
    ".result" => "Show last execution result (full details)",
    ".stdout" => "Show stdout from last execution",
    ".stderr" => "Show stderr from last execution",
    ".help" => "Show this help message or help for a builtin command",
    ".quit" => "Exit the CLI"
  }

  # ============================================================================
  # New Public API (for testing and programmatic use)
  # ============================================================================

  @doc """
  Execute a script string and return state with full metrics.

  PERFECT FOR UNIT TESTS - returns complete execution data.

  Can be called multiple times on same state (accumulates).

  ## Options
    - `:state` - Existing state to continue from (default: new state)
    - `:env` - Initial environment variables
    - `:cwd` - Initial working directory
    - `:session_id` - Custom session ID

  ## Returns
    - `{:ok, state}` - Success with full state
    - `{:error, reason}` - Parse or execution error

  ## Examples

      # Single execution
      {:ok, state} = CLI.execute_string("echo hello")
      record = List.last(state.history)
      assert record.stdout == ["hello\\n"]
      assert record.exit_code == 0
      assert record.parse_metrics.duration_us > 0

      # Multiple executions (accumulates)
      {:ok, state1} = CLI.execute_string("X=5")
      {:ok, state2} = CLI.execute_string("echo $X", state: state1)
      assert length(state2.history) == 2
      assert List.last(state2.history).stdout == ["5\\n"]

      # Access full AST
      {:ok, state} = CLI.execute_string("echo test")
      record = List.last(state.history)
      assert record.full_ast != nil
      assert record.incremental_ast != nil

      # Access metrics
      parse_time = record.parse_metrics.duration_us
      exec_time = record.exec_metrics.duration_us
      memory_used = record.exec_metrics.memory_delta
  """
  @spec execute_string(String.t(), keyword()) :: {:ok, State.t()} | {:error, term()}
  def execute_string(script, opts \\ []) do
    # Get or create state
    case Keyword.get(opts, :state) do
      nil ->
        # Create new state
        case State.new(opts) do
          {:ok, state} -> Executor.execute_fragment(script, state)
          error -> error
        end
      existing_state when is_struct(existing_state, State) ->
        # Execute with existing state
        Executor.execute_fragment(script, existing_state)
    end
  end

  @doc """
  Reset CLI state, parser, and runtime to defaults.

  Clears:
    - CLI execution history
    - Parser accumulated buffer and AST
    - Runtime context (env/cwd reset to initial values)

  Preserves:
    - Parser and Runtime PIDs (just resets their state)
    - Session ID
    - Initial options

  Broadcasts:
    - {:runtime_reset, ...} event on :context topic

  ## Example

      {:ok, state1} = CLI.execute_string("X=5")
      {:ok, state2} = CLI.execute_string("echo $X", state: state1)
      assert length(state2.history) == 2

      {:ok, state3} = CLI.reset(state2)
      assert length(state3.history) == 0

      {:ok, state4} = CLI.execute_string("echo $X", state: state3)
      # $X is empty - runtime was reset
  """
  @spec reset(State.t()) :: {:ok, State.t()}
  def reset(%State{} = state) do
    # Reset parser
    :ok = IncrementalParser.reset(state.parser_pid)

    # Reset runtime
    :ok = Runtime.reset(state.runtime_pid)

    # Clear CLI history
    {:ok, %{state | history: []}}
  end

  @doc """
  Execute a script string line-by-line, simulating interactive mode.

  This feeds lines through InputBuffer first to determine when complete
  chunks are ready for parsing. This properly simulates how the interactive
  CLI works with control structures.

  ## Options

  - `:state` - Existing state to continue from (optional, creates new if not provided)

  ## Returns

  - `{:ok, state}` with updated state including all execution records

  ## Examples

      # Execute multi-line script incrementally
      script = \"\"\"
      X=5
      if test $X = 5; then
        echo "X equals 5!"
      fi
      \"\"\"
      {:ok, state} = CLI.execute_lines(script)

      # Continue from existing state
      {:ok, state2} = CLI.execute_lines("echo done", state: state)
  """
  @spec execute_lines(String.t(), keyword()) :: {:ok, State.t()} | {:error, term()}
  def execute_lines(script, opts \\ []) do
    state = Keyword.get_lazy(opts, :state, fn ->
      {:ok, s} = State.new(opts)
      s
    end)

    # Split into lines, preserving empty lines
    lines = String.split(script, "\n", trim: false)

    # Remove the last line if it's empty (from trailing newline)
    lines = if List.last(lines) == "" do
      List.delete_at(lines, -1)
    else
      lines
    end

    # Process lines through InputBuffer, accumulating until ready
    process_lines_with_buffer(lines, state, "")
  end

  # Process lines through InputBuffer to simulate interactive mode
  defp process_lines_with_buffer([], state, buffer) do
    # If there's remaining buffer content, it should have been flushed already
    # or it's incomplete (which is an error condition)
    if buffer != "" && !InputBuffer.ready_to_parse?(buffer) do
      {:error, {:incomplete_input, buffer}}
    else
      {:ok, state}
    end
  end

  defp process_lines_with_buffer([line | rest], state, buffer) do
    # Add line to buffer with newline
    new_buffer = buffer <> line <> "\n"

    # Check if buffer is ready to parse
    if InputBuffer.ready_to_parse?(new_buffer) do
      # Send complete fragment to parser
      case Executor.execute_fragment(new_buffer, state) do
        {:ok, new_state} ->
          # Clear buffer and continue with remaining lines
          process_lines_with_buffer(rest, new_state, "")
        error ->
          error
      end
    else
      # Not ready yet - continue accumulating
      process_lines_with_buffer(rest, state, new_buffer)
    end
  end

  ## Main Entry Point

  def main(args) do
    case args do
      [] ->
        # Mode 2: Interactive
        execute_interactive()

      [file_path] ->
        # Mode 1: File execution (one-shot)
        execute_file(file_path)

      ["--line-by-line", file_path] ->
        # Mode 3: Line-by-line file processing
        execute_line_by_line(file_path)

      ["--parse-only", file_path] ->
        # Mode 4: Parse-only mode
        execute_parse_only(file_path)

      ["--help"] ->
        show_usage()

      ["-h"] ->
        show_usage()

      _ ->
        IO.puts(:stderr, "❌ Invalid arguments")
        show_usage()
        System.halt(1)
    end
  end

  defp show_usage do
    IO.puts("""

    🐚 RShell - Multi-Mode Bash Parser & Executor

    Usage:
      rshell                        # Interactive mode (REPL)
      rshell script.sh              # Execute file (one-shot)
      rshell --line-by-line file    # Process file line-by-line
      rshell --parse-only file      # Parse and display AST only
      rshell --help                 # Show this help

    Interactive mode commands start with '.' (type .help for list)
    """)
  end

  ## Mode 1: File Execution (One-Shot)
  # Note: Only executes Command nodes (builtins). Variables, pipelines, etc. not supported yet.

  defp execute_file(file_path) do
    case File.read(file_path) do
      {:ok, content} ->
        # Parse entire file
        case BashParser.parse_bash(content) do
          {:ok, ast_map} ->
            typed_ast = Types.from_map(ast_map)

            IO.puts("⚠️  File execution mode only supports builtin commands")
            IO.puts("   Variables, pipelines, and control structures will be skipped\n")

            # Start runtime
            session_id = "file_#{:erlang.phash2(file_path)}"
            {:ok, runtime} = Runtime.start_link(
              session_id: session_id,
              auto_execute: false
            )

            # Subscribe to output
            PubSub.subscribe(session_id, [:output, :runtime])

            # Execute only Command nodes from the Program
            case typed_ast do
              %Types.Program{children: children} ->
                Enum.each(children, fn child ->
                  case child do
                    %Types.Command{} ->
                      try do
                        Runtime.execute_node(runtime, child)
                        collect_output(1000)
                      rescue
                        e ->
                          IO.puts(:stderr, "❌ Error executing command: #{Exception.message(e)}")
                      end

                    other ->
                      node_type = other.__struct__ |> Module.split() |> List.last()
                      IO.puts("⊘ Skipping #{node_type}: #{String.slice(other.source_info.text || "", 0, 40)}")
                  end
                end)

              other ->
                # Single node
                if match?(%Types.Command{}, other) do
                  Runtime.execute_node(runtime, other)
                  collect_output(1000)
                else
                  IO.puts(:stderr, "❌ Only Command nodes supported in file execution")
                  System.halt(1)
                end
            end

          {:error, reason} ->
            IO.puts(:stderr, "❌ Parse error: #{inspect(reason)}")
            System.halt(1)
        end

      {:error, reason} ->
        IO.puts(:stderr, "❌ Error reading #{file_path}: #{:file.format_error(reason)}")
        System.halt(1)
    end
  end

  ## Mode 2: Interactive (REPL) - Current Implementation

  defp execute_interactive do
    IO.puts("\n🐚 RShell - Interactive Bash Shell")
    IO.puts("=" |> String.duplicate(50))
    IO.puts("Type bash commands. Built-in commands start with '.'")
    IO.puts("Type .help for available commands\n")

    # Generate session ID
    session_id = "cli_#{System.unique_integer([:positive, :monotonic])}"

    # Start the parser GenServer with session ID
    {:ok, parser_pid} = IncrementalParser.start_link(
      name: :rshell_cli_parser,
      session_id: session_id,
      broadcast: true
    )

    # Start the runtime GenServer (no auto-execute - now synchronous)
    {:ok, runtime_pid} = Runtime.start_link(
      session_id: session_id
    )

    IO.puts("✅ Parser started (PID: #{inspect(parser_pid)})")
    IO.puts("✅ Runtime started (PID: #{inspect(runtime_pid)})")
    IO.puts("📡 Session ID: #{session_id}\n")

    # Subscribe to parser and runtime events
    PubSub.subscribe(session_id, [:ast, :executable, :runtime, :output])

    # Start the input loop with state tracking
    # last_incremental tracks the incremental changes from the last parse
    # last_result tracks the last execution result for debugging
    loop(parser_pid, runtime_pid, session_id, _previous_children = [], _last_incremental = nil, _input_buffer = "", _last_result = nil)
  end

  ## Mode 3: Line-by-Line File Processing
  # Note: Same as Mode 1, only supports Command nodes (builtins)

  defp execute_line_by_line(file_path) do
    IO.puts("⚠️  Line-by-line mode only supports builtin commands")
    IO.puts("   This mode is primarily for testing incremental parsing\n")

    case File.read(file_path) do
      {:ok, content} ->
        session_id = "line_by_line_#{:erlang.phash2(file_path)}"

        {:ok, parser} = IncrementalParser.start_link(session_id: session_id, broadcast: true)
        {:ok, runtime} = Runtime.start_link(session_id: session_id)

        PubSub.subscribe(session_id, [:output, :runtime])

        # Process lines through InputBuffer
        lines = String.split(content, "\n", trim: false)
        process_lines(lines, parser, runtime, session_id, "")

      {:error, reason} ->
        IO.puts(:stderr, "❌ Error reading #{file_path}: #{:file.format_error(reason)}")
        System.halt(1)
    end
  end

  defp process_lines([], _parser, _runtime, _session_id, _buffer) do
    :ok
  end

  defp process_lines([line | rest], parser, runtime, session_id, buffer) do
    new_buffer = buffer <> line <> "\n"

    if InputBuffer.ready_to_parse?(new_buffer) do
      # Parse the fragment
      case IncrementalParser.append_fragment(parser, new_buffer) do
        {:ok, ast} ->
          # Synchronously execute any executable nodes
          execute_ast_nodes(ast, runtime)
          IncrementalParser.reset(parser)
          process_lines(rest, parser, runtime, session_id, "")

        {:error, reason} ->
          IO.puts(:stderr, "❌ Parse error: #{inspect(reason)}")
          process_lines(rest, parser, runtime, session_id, "")
      end
    else
      # Continue accumulating
      process_lines(rest, parser, runtime, session_id, new_buffer)
    end
  end

  # Helper to execute AST nodes synchronously
  defp execute_ast_nodes(%{children: children}, runtime) when is_list(children) do
    Enum.each(children, fn node ->
      if is_executable_node?(node) do
        case Runtime.execute_node(runtime, node) do
          {:ok, context} ->
            # Display output
            stdout = format_output(context.last_output.stdout)
            stderr = format_output(context.last_output.stderr)
            if stdout != "", do: IO.write(stdout)
            if stderr != "", do: IO.write(:stderr, stderr)

          {:error, error} ->
            IO.puts(:stderr, "Error: #{error}")
        end
      end
    end)
  end
  defp execute_ast_nodes(_, _), do: :ok

  # Check if node is executable (same logic as elsewhere)
  defp is_executable_node?(node) do
    case node do
      %Types.Command{} -> true
      %Types.VariableAssignment{} -> true
      %Types.IfStatement{} -> true
      %Types.ForStatement{} -> true
      %Types.WhileStatement{} -> true
      _ -> false
    end
  end

  # wait_for_execution/0 removed - no longer needed with synchronous execution

  ## Mode 4: Parse-Only

  defp execute_parse_only(file_path) do
    case File.read(file_path) do
      {:ok, content} ->
        case BashParser.parse_bash(content) do
          {:ok, ast_map} ->
            typed_ast = Types.from_map(ast_map)
            IO.puts("✅ Parse successful!\n")
            print_typed_ast(typed_ast, 0)

          {:error, reason} ->
            IO.puts(:stderr, "❌ Parse error: #{inspect(reason)}")
            System.halt(1)
        end

      {:error, reason} ->
        IO.puts(:stderr, "❌ Error reading #{file_path}: #{:file.format_error(reason)}")
        System.halt(1)
    end
  end

  ## Interactive Mode Helper (collect execution results)

  defp collect_output(timeout) do
    receive do
      {:execution_result, %{status: :success, stdout: stdout, stderr: stderr}} ->
        # Convert native term lists to strings for display
        stdout_str = format_output(stdout)
        stderr_str = format_output(stderr)

        if stdout_str != "", do: IO.write(stdout_str)
        if stderr_str != "", do: IO.write(:stderr, stderr_str)
        collect_output(timeout)

      {:execution_result, %{status: :error, error: error}} ->
        IO.puts(:stderr, "Error: #{error}")
        collect_output(timeout)
    after
      timeout -> :ok
    end
  end

  defp loop(parser_pid, runtime_pid, session_id, previous_children, last_incremental, input_buffer, last_result \\ nil) do
    # Determine prompt based on input buffer state
    prompt = get_prompt(input_buffer)

    # Read input with a short timeout to check for PubSub messages
    case IO.gets(prompt) do
      :eof ->
        IO.puts("\n👋 Goodbye!")
        :ok

      {:error, reason} ->
        IO.puts("❌ Error reading input: #{inspect(reason)}")
        loop(parser_pid, runtime_pid, session_id, previous_children, last_incremental, input_buffer)

      line ->
        line = String.trim_trailing(line, "\n")
        handle_input(parser_pid, runtime_pid, session_id, line, previous_children, last_incremental, input_buffer, last_result)
    end
  end

  # Get appropriate prompt based on input buffer state
  defp get_prompt(input_buffer) do
    if input_buffer == "" do
      # Empty buffer - normal prompt
      "rshell> "
    else
      # Input buffer has content - check continuation type
      continuation_type = InputBuffer.continuation_type(input_buffer)
      continuation_prompt(continuation_type)
    end
  end

  # Map continuation types to prompts
  defp continuation_prompt(:complete), do: "rshell> "
  defp continuation_prompt(:line_continuation), do: "     > "
  defp continuation_prompt(:quote_continuation), do: "quote> "
  defp continuation_prompt(:heredoc_continuation), do: "  doc> "
  defp continuation_prompt(:structure_continuation), do: "     > "

  defp handle_input(_parser_pid, _runtime_pid, _session_id, ".quit", _prev_children, _last_incremental, _input_buffer, _last_result), do: IO.puts("\n👋 Goodbye!")
  defp handle_input(_parser_pid, _runtime_pid, _session_id, ".exit", _prev_children, _last_incremental, _input_buffer, _last_result), do: IO.puts("\n👋 Goodbye!")

  defp handle_input(parser_pid, runtime_pid, session_id, ".help", prev_children, last_incremental, input_buffer, last_result) do
    IO.puts("\n📖 Available Commands:\n")

    Enum.each(@commands, fn {cmd, desc} ->
      IO.puts("  #{String.pad_trailing(cmd, 12)} - #{desc}")
    end)

    IO.puts("\n💡 For help on builtins, use: .help <builtin>")
    IO.puts("   Example: .help echo\n")

    loop(parser_pid, runtime_pid, session_id, prev_children, last_incremental, input_buffer, last_result)
  end

  defp handle_input(parser_pid, runtime_pid, session_id, ".help " <> builtin_name, prev_children, last_incremental, input_buffer, last_result) do
    builtin = String.trim(builtin_name)

    if RShell.Builtins.is_builtin?(builtin) do
      help_text = RShell.Builtins.get_builtin_help(builtin)
      IO.puts("\n" <> help_text <> "\n")
    else
      IO.puts("\n❌ Unknown builtin: #{builtin}")
      IO.puts("💡 Use '.help' to see available commands\n")
    end

    loop(parser_pid, runtime_pid, session_id, prev_children, last_incremental, input_buffer, last_result)
  end

  defp handle_input(parser_pid, runtime_pid, session_id, ".reset", _prev_children, _last_incremental, _input_buffer, _last_result) do
    :ok = IncrementalParser.reset(parser_pid)
    IO.puts("🔄 Parser state reset\n")
    # Also clear input buffer, incremental state, and last result on reset
    loop(parser_pid, runtime_pid, session_id, [], nil, "", nil)
  end

  defp handle_input(parser_pid, runtime_pid, session_id, ".status", prev_children, last_incremental, input_buffer, last_result) do
    buffer_size = IncrementalParser.get_buffer_size(parser_pid)
    has_errors = IncrementalParser.has_errors?(parser_pid)
    input = IncrementalParser.get_accumulated_input(parser_pid)
    context = Runtime.get_context(runtime_pid)

    IO.puts("\n📊 Status:")
    IO.puts("  Session ID: #{session_id}")
    IO.puts("  Buffer size: #{buffer_size} bytes")
    IO.puts("  Has errors: #{has_errors}")
    IO.puts("  Lines accumulated: #{length(String.split(input, "\n")) - 1}")
    IO.puts("  Commands executed: #{context.command_count}")
    IO.puts("  Exit code: #{context.exit_code}")

    # Show input buffer state
    if input_buffer != "" do
      IO.puts("\n📝 Input Buffer (not yet sent to parser):")
      IO.puts(String.duplicate("-", 50))
      IO.puts(input_buffer)
      IO.puts(String.duplicate("-", 50))
      IO.puts("  Ready to parse: #{InputBuffer.ready_to_parse?(input_buffer)}")
      IO.puts("  Continuation type: #{InputBuffer.continuation_type(input_buffer)}")
    end

    if buffer_size > 0 do
      IO.puts("\n📝 Parser Buffer:")
      IO.puts(String.duplicate("-", 50))
      IO.puts(input)
      IO.puts(String.duplicate("-", 50))
    end

    IO.puts("")
    loop(parser_pid, runtime_pid, session_id, prev_children, last_incremental, input_buffer, last_result)
  end

  defp handle_input(parser_pid, runtime_pid, session_id, ".ast", prev_children, last_incremental, input_buffer, last_result) do
    case IncrementalParser.get_current_ast(parser_pid) do
      {:ok, ast} ->
        IO.puts("\n🌳 Full Accumulated AST:")
        IO.puts(String.duplicate("-", 50))
        print_typed_ast(ast, 0)
        IO.puts(String.duplicate("-", 50))

      {:error, %{"reason" => "no_tree"}} ->
        IO.puts("\n⚠️  No AST yet - add some input first")

      {:error, reason} ->
        IO.puts("\n❌ Error getting AST: #{inspect(reason)}")
    end

    IO.puts("")
    loop(parser_pid, runtime_pid, session_id, prev_children, last_incremental, input_buffer, last_result)
  end

  defp handle_input(parser_pid, runtime_pid, session_id, ".last", prev_children, last_incremental, input_buffer, last_result) do
    case last_incremental do
      nil ->
        IO.puts("\n⚠️  No incremental changes yet")

      %{changed_nodes: changed_nodes} when changed_nodes != [] ->
        IO.puts("\n🔄 Last Incremental Changes:")
        IO.puts(String.duplicate("-", 50))
        Enum.each(changed_nodes, fn node ->
          print_typed_ast(node, 0)
        end)
        IO.puts(String.duplicate("-", 50))

      _ ->
        IO.puts("\n⚠️  No changes in last parse")
    end

    IO.puts("")
    loop(parser_pid, runtime_pid, session_id, prev_children, last_incremental, input_buffer, last_result)
  end

  # New commands for debugging execution results
  defp handle_input(parser_pid, runtime_pid, session_id, ".result", prev_children, last_incremental, input_buffer, last_result) do
    case last_result do
      nil ->
        IO.puts("\n⚠️  No execution result yet")
      result ->
        IO.puts("\n📊 Last Execution Result:")
        IO.puts(String.duplicate("-", 50))
        IO.puts("Status:     #{result.status}")
        IO.puts("Node Type:  #{result.node_type}")
        if result[:node_text], do: IO.puts("Command:    #{result.node_text}")
        if result[:exit_code], do: IO.puts("Exit Code:  #{result.exit_code}")
        if result[:duration_us], do: IO.puts("Duration:   #{result.duration_us}μs")
        if result[:error], do: IO.puts("Error:      #{result.error}")
        if result[:reason], do: IO.puts("Reason:     #{result.reason}")
        IO.puts("\nStdout: #{inspect(result[:stdout] || "")}")
        IO.puts("Stderr: #{inspect(result[:stderr] || "")}")
        IO.puts(String.duplicate("-", 50))
    end
    IO.puts("")
    loop(parser_pid, runtime_pid, session_id, prev_children, last_incremental, input_buffer, last_result)
  end

  defp handle_input(parser_pid, runtime_pid, session_id, ".stdout", prev_children, last_incremental, input_buffer, last_result) do
    case last_result do
      nil ->
        IO.puts("\n⚠️  No execution result yet")
      result ->
        stdout = result[:stdout] || ""
        if stdout == "" do
          IO.puts("\n📭 No stdout from last execution")
        else
          IO.puts("\n📤 Stdout from last execution:")
          IO.puts(String.duplicate("-", 50))
          IO.write(stdout)
          IO.puts(String.duplicate("-", 50))
        end
    end
    IO.puts("")
    loop(parser_pid, runtime_pid, session_id, prev_children, last_incremental, input_buffer, last_result)
  end

  defp handle_input(parser_pid, runtime_pid, session_id, ".stderr", prev_children, last_incremental, input_buffer, last_result) do
    case last_result do
      nil ->
        IO.puts("\n⚠️  No execution result yet")
      result ->
        stderr = result[:stderr] || ""
        if stderr == "" do
          IO.puts("\n📭 No stderr from last execution")
        else
          IO.puts("\n⚠️  Stderr from last execution:")
          IO.puts(String.duplicate("-", 50))
          IO.write(:stderr, stderr)
          IO.puts(String.duplicate("-", 50))
        end
    end
    IO.puts("")
    loop(parser_pid, runtime_pid, session_id, prev_children, last_incremental, input_buffer, last_result)
  end

  # Handle empty input - just continue accumulating if buffer is not empty
  defp handle_input(parser_pid, runtime_pid, session_id, "", prev_children, last_incremental, input_buffer, last_result) do
    # If buffer is empty, just loop with empty buffer
    # If buffer has content, add newline and check if ready
    if input_buffer == "" do
      loop(parser_pid, runtime_pid, session_id, prev_children, last_incremental, input_buffer, last_result)
    else
      # Add newline to buffer
      new_buffer = input_buffer <> "\n"

      # Check if ready to parse
      if InputBuffer.ready_to_parse?(new_buffer) do
        # Send complete fragment to parser
        send_to_parser(parser_pid, runtime_pid, session_id, new_buffer, prev_children, last_incremental, last_result)
      else
        # Continue accumulating
        loop(parser_pid, runtime_pid, session_id, prev_children, last_incremental, new_buffer, last_result)
      end
    end
  end

  # Handle regular input - accumulate and check if ready to parse
  defp handle_input(parser_pid, runtime_pid, session_id, line, previous_children, last_incremental, input_buffer, last_result) do
    # Add line to buffer with newline
    new_buffer = input_buffer <> line <> "\n"

    # Check if buffer is ready to parse
    if InputBuffer.ready_to_parse?(new_buffer) do
      # Send complete fragment to parser
      send_to_parser(parser_pid, runtime_pid, session_id, new_buffer, previous_children, last_incremental, last_result)
    else
      # Not ready yet - continue accumulating
      loop(parser_pid, runtime_pid, session_id, previous_children, last_incremental, new_buffer, last_result)
    end
  end

  # Helper function to send complete fragment to parser and execute synchronously
  defp send_to_parser(parser_pid, runtime_pid, session_id, fragment, previous_children, last_incremental, _last_result) do
    # Submit complete fragment to parser (will trigger PubSub events)
    case IncrementalParser.append_fragment(parser_pid, fragment) do
      {:ok, ast} ->
        # Collect parser events (AST updates, etc.)
        {new_children, new_incremental} = handle_parser_events(session_id, previous_children, 100, last_incremental)

        # Execute nodes synchronously
        execution_result = execute_interactive_nodes(ast, runtime_pid)

        # Display output if any
        display_execution_result(execution_result)

        # Clear input buffer after successful parse
        loop(parser_pid, runtime_pid, session_id, new_children, new_incremental, "", execution_result)

      {:error, %{"reason" => "buffer_overflow"} = error} ->
        IO.puts("\n❌ Buffer overflow!")
        IO.puts("   Current: #{error["current_size"]} bytes")
        IO.puts("   Fragment: #{error["fragment_size"]} bytes")
        IO.puts("   Max: #{error["max_size"]} bytes")
        IO.puts("   Use .reset to clear buffer\n")
        # Keep input buffer on error
        loop(parser_pid, runtime_pid, session_id, previous_children, last_incremental, "", nil)

      {:error, reason} ->
        IO.puts("\n❌ Parse error: #{inspect(reason)}\n")
        # Clear input buffer on error
        loop(parser_pid, runtime_pid, session_id, previous_children, last_incremental, "", nil)
    end
  end

  # Handle PubSub events from the parser only (no execution events)
  # Returns {children, incremental_metadata} tuple
  defp handle_parser_events(session_id, previous_children, timeout, last_incremental) do
    receive do
      {:ast_incremental, metadata} ->
        # Get current children from typed struct
        current_children = case metadata.full_ast do
          %{children: children} when is_list(children) -> children
          _ -> []
        end

        # Store incremental metadata for .last command
        # Continue collecting events
        handle_parser_events(session_id, current_children, timeout, metadata)

      {:parsing_failed, error} ->
        # Parser failed - display error and return
        IO.puts("\n❌ Parsing failed: #{inspect(error)}\n")
        {previous_children, last_incremental}

      {:parsing_crashed, error} ->
        # Parser crashed unexpectedly - display error and return
        IO.puts("\n❌ Parser crashed: #{error.reason}")
        if error[:exception] do
          IO.puts("   #{error.exception}\n")
        end
        {previous_children, last_incremental}

      {:executable_node, _typed_node, _count} ->
        # Executable node detected - just note it and continue
        # (execution happens synchronously now)
        handle_parser_events(session_id, previous_children, timeout, last_incremental)

      {:variable_set, info} ->
        # Variable was set
        IO.puts("✓ #{info.name}=#{info.value}")
        handle_parser_events(session_id, previous_children, timeout, last_incremental)

    after
      timeout ->
        # No more events, return current state
        {previous_children, last_incremental}
    end
  end

  # Execute AST nodes synchronously in interactive mode
  defp execute_interactive_nodes(%{children: children}, runtime_pid) when is_list(children) do
    Enum.reduce(children, nil, fn node, _last_result ->
      if is_executable_node?(node) do
        case Runtime.execute_node(runtime_pid, node) do
          {:ok, _context} = result ->
            # Convert to result map format
            build_result_from_context(result, node)
          {:error, error} ->
            %{status: :error, error: error, node: node}
        end
      else
        nil
      end
    end)
  end
  defp execute_interactive_nodes(_, _), do: nil

  # Build result map from Runtime.execute_node response
  defp build_result_from_context({:ok, context}, node) do
    %{
      status: :success,
      node: node,
      node_type: node.__struct__ |> Module.split() |> List.last(),
      stdout: context.last_output.stdout,
      stderr: context.last_output.stderr,
      exit_code: context.exit_code,
      context: context
    }
  end

  # Display execution result in interactive mode
  defp display_execution_result(nil), do: :ok
  defp display_execution_result(%{status: :success} = result) do
    # Display output (convert native term lists to strings)
    stdout_str = format_output(result.stdout)
    stderr_str = format_output(result.stderr)

    if stdout_str != "", do: IO.write(stdout_str)
    if stderr_str != "", do: IO.write(:stderr, stderr_str)

    # Show exit code if non-zero
    if result.exit_code != 0 do
      IO.puts("⚠️  Exit code: #{result.exit_code}")
    end
  end
  defp display_execution_result(%{status: :error} = result) do
    IO.puts("\n❌ Execution failed: #{inspect(result.error)}")
    if result[:node] do
      node_text = result.node.source_info.text
      node_line = result.node.source_info.start_line
      IO.puts("   Line #{node_line}: #{node_text}")
    end
  end

  # Pretty-print typed AST
  defp print_typed_ast(typed_node, indent) when is_atom(typed_node) do
    # Handle error nodes (atoms like :error_node)
    prefix = String.duplicate("  ", indent)
    IO.puts("#{prefix}[ERROR_NODE] #{inspect(typed_node)}")
  end

  defp print_typed_ast(typed_node, indent) when is_struct(typed_node) do
    prefix = String.duplicate("  ", indent)

    type = typed_node.__struct__ |> Module.split() |> List.last()
    text = typed_node.source_info.text || ""

    # Truncate long text
    display_text =
      if String.length(text) > 40 do
        String.slice(text, 0, 37) <> "..."
      else
        text
      end

    IO.puts("#{prefix}[#{type}] #{inspect(display_text)}")

    # Print children recursively if present
    if Map.has_key?(typed_node, :children) && is_list(typed_node.children) do
      Enum.each(typed_node.children, fn child ->
        print_typed_ast(child, indent + 1)
      end)
    end

    # Also print named fields that contain nodes
    typed_node
    |> Map.from_struct()
    |> Map.drop([:__struct__, :source_info, :children])
    |> Enum.each(fn
      {key, value} when is_struct(value) ->
        IO.puts("#{prefix}  .#{key}:")
        print_typed_ast(value, indent + 2)

      {key, values} when is_list(values) ->
        # Check if it's a list of nodes
        if Enum.all?(values, &is_struct/1) && values != [] do
          IO.puts("#{prefix}  .#{key}: [#{length(values)} items]")
          Enum.each(values, fn item ->
            print_typed_ast(item, indent + 2)
          end)
        end

      _ -> :skip
    end)
  end

  # Format output for display - convert native term lists to strings
  defp format_output([]), do: ""
  defp format_output(output) when is_list(output) do
    output
    |> Enum.map(&term_to_string/1)
    |> Enum.join("")
  end
  defp format_output(output) when is_binary(output), do: output
  defp format_output(output), do: term_to_string(output)

  # Convert a single term to string for display
  defp term_to_string(term) when is_binary(term), do: term
  defp term_to_string(term) when is_map(term), do: Jason.encode!(term)
  defp term_to_string(term) when is_list(term) do
    # Check if it's a charlist
    if Enum.all?(term, &(is_integer(&1) and &1 >= 32 and &1 <= 126)) do
      List.to_string(term)
    else
      Jason.encode!(term)
    end
  end
  defp term_to_string(term) when is_integer(term), do: Integer.to_string(term)
  defp term_to_string(term) when is_float(term), do: Float.to_string(term)
  defp term_to_string(true), do: "true"
  defp term_to_string(false), do: "false"
  defp term_to_string(nil), do: ""
  defp term_to_string(atom) when is_atom(atom), do: Atom.to_string(atom)
end
