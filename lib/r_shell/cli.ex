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
  alias RShell.CLI.{Executor, State, InteractiveState}
  alias RShell.Builtins.Utils
  alias BashParser.AST.Types
  alias BashParser.AST.Utils, as: ASTUtils

  @commands %{
    ".reset" => "Clear parser state and start fresh",
    ".status" => "Show current parser status (buffer size, errors)",
    ".ast" => "Show full accumulated AST (all commands entered)",
    ".last" => "Show incremental changes from last parse",
    ".result" => "Show last execution result (full details)",
    ".stdout" => "Show stdout from last execution",
    ".stderr" => "Show stderr from last execution",
    ".debug" => "Toggle debug logging on/off",
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
    state =
      Keyword.get_lazy(opts, :state, fn ->
        {:ok, s} = State.new(opts)
        s
      end)

    # Split into lines, preserving empty lines
    lines = String.split(script, "\n", trim: false)

    # Remove the last line if it's empty (from trailing newline)
    lines =
      if List.last(lines) == "" do
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
        # Use RShell grammar for file parsing
        {:ok, parser} = RShell.Grammar.new_parser()
        case RShell.Grammar.parse_incremental(parser, content <> "\n") do
          {:ok, ast_map} ->
            typed_ast = Types.from_map(ast_map)

            IO.puts("⚠️  File execution mode only supports builtin commands")
            IO.puts("   Variables, pipelines, and control structures will be skipped\n")

            # Start runtime
            session_id = "file_#{:erlang.phash2(file_path)}"

            {:ok, runtime} =
              Runtime.start_link(
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

                      IO.puts(
                        "⊘ Skipping #{node_type}: #{String.slice(other.source_info.text || "", 0, 40)}"
                      )
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
    # Set default logger level to :warning (hides debug messages)
    Logger.configure(level: :warning)

    IO.puts("\n🐚 RShell - Interactive Bash Shell")
    IO.puts("=" |> String.duplicate(50))
    IO.puts("Type bash commands. Built-in commands start with '.'")
    IO.puts("Type .help for available commands\n")

    # Initialize readline history
    history_file = Path.expand("~/.rshell_history")
    setup_readline_history(history_file)

    # Create CLI state (includes parser, runtime, session)
    {:ok, cli_state} = State.new()

    IO.puts("✅ Parser started (PID: #{inspect(cli_state.parser_pid)})")
    IO.puts("✅ Runtime started (PID: #{inspect(cli_state.runtime_pid)})")
    IO.puts("📡 Session ID: #{cli_state.session_id}\n")

    # Subscribe to parser and runtime events
    PubSub.subscribe(cli_state.session_id, [:ast, :executable, :runtime, :output])

    # Create interactive state and start loop
    istate = InteractiveState.new(cli_state)
    loop(istate)
  end

  # Initialize readline with history file support
  defp setup_readline_history(history_file) do
    # Store history file path in process dictionary for later use
    Process.put(:rshell_history_file, history_file)

    # Read history from file if it exists
    if File.exists?(history_file) do
      case File.read(history_file) do
        {:ok, content} ->
          content
          |> String.split("\n", trim: true)
          |> Enum.each(&ExReadline.add_to_history/1)

        {:error, _reason} ->
          # Ignore read errors, just start with empty history
          :ok
      end
    end
  end

  # Save a line to the history file
  defp save_to_history_file(line) do
    case Process.get(:rshell_history_file) do
      nil -> :ok
      history_file ->
        # Append line to history file
        File.write(history_file, line <> "\n", [:append])
    end
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
      if ASTUtils.executable?(node) do
        case Runtime.execute_node(runtime, node) do
          {:ok, _context} ->
            # Get output from FrameStack instead of context
            runtime_state = :sys.get_state(runtime)
            frame_output = RShell.Runtime.FrameStack.get_output(runtime_state.frame_stack)

            # Display output
            stdout = Utils.format_output(frame_output.stdout)
            stderr = Utils.format_output(frame_output.stderr)
            if stdout != "", do: IO.write(stdout)
            if stderr != "", do: IO.write(:stderr, stderr)

          {:error, error} ->
            IO.puts(:stderr, "Error: #{error}")
        end
      end
    end)
  end

  defp execute_ast_nodes(_, _), do: :ok

  ## Mode 4: Parse-Only

  defp execute_parse_only(file_path) do
    case File.read(file_path) do
      {:ok, content} ->
        # Use RShell grammar for file parsing
        {:ok, parser} = RShell.Grammar.new_parser()
        case RShell.Grammar.parse_incremental(parser, content <> "\n") do
          {:ok, ast_map} ->
            typed_ast = Types.from_map(ast_map)
            IO.puts("✅ Parse successful!\n")
            ASTUtils.print(typed_ast)

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
        stdout_str = Utils.format_output(stdout)
        stderr_str = Utils.format_output(stderr)

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

  defp loop(%InteractiveState{} = istate) do
    # Determine prompt based on input buffer state
    prompt = get_prompt(istate.input_buffer)

    # Read input using ExReadline for history support
    case ExReadline.read_line(prompt) do
      line when is_binary(line) ->
        # Add non-empty lines to history (skip dot commands and empty lines)
        if line != "" && !String.starts_with?(line, ".") do
          ExReadline.add_to_history(line)
          # Save to history file
          save_to_history_file(line)
        end

        handle_input(istate, line)

      :eof ->
        IO.puts("\n👋 Goodbye!")
        :ok

      {:error, reason} ->
        IO.puts("❌ Error reading input: #{inspect(reason)}")
        loop(istate)
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

  defp handle_input(%InteractiveState{} = _istate, ".quit"),
    do: IO.puts("\n👋 Goodbye!")

  defp handle_input(%InteractiveState{} = _istate, ".exit"),
    do: IO.puts("\n👋 Goodbye!")

  defp handle_input(%InteractiveState{} = istate, ".help") do
    IO.puts("\n📖 Available Commands:\n")

    Enum.each(@commands, fn {cmd, desc} ->
      IO.puts("  #{String.pad_trailing(cmd, 12)} - #{desc}")
    end)

    IO.puts("\n💡 For help on builtins, use: .help <builtin>")
    IO.puts("   Example: .help echo\n")

    loop(istate)
  end

  defp handle_input(%InteractiveState{} = istate, ".help " <> builtin_name) do
    builtin = String.trim(builtin_name)

    if RShell.Builtins.is_builtin?(builtin) do
      help_text = RShell.Builtins.get_builtin_help(builtin)
      IO.puts("\n" <> help_text <> "\n")
    else
      IO.puts("\n❌ Unknown builtin: #{builtin}")
      IO.puts("💡 Use '.help' to see available commands\n")
    end

    loop(istate)
  end

  defp handle_input(%InteractiveState{} = istate, ".reset") do
    :ok = IncrementalParser.reset(istate.parser_pid)
    IO.puts("🔄 Parser state reset\n")
    # Reset interactive state
    loop(InteractiveState.reset(istate))
  end

  defp handle_input(%InteractiveState{} = istate, ".status") do
    buffer_size = IncrementalParser.get_buffer_size(istate.parser_pid)
    has_errors = IncrementalParser.has_errors?(istate.parser_pid)
    input = IncrementalParser.get_accumulated_input(istate.parser_pid)
    context = Runtime.get_context(istate.runtime_pid)

    IO.puts("\n📊 Status:")
    IO.puts("  Session ID: #{istate.session_id}")
    IO.puts("  Buffer size: #{buffer_size} bytes")
    IO.puts("  Has errors: #{has_errors}")
    IO.puts("  Lines accumulated: #{length(String.split(input, "\n")) - 1}")
    IO.puts("  Commands executed: #{context.command_count}")
    IO.puts("  Exit code: #{context.exit_code}")

    # Show input buffer state
    if istate.input_buffer != "" do
      IO.puts("\n📝 Input Buffer (not yet sent to parser):")
      IO.puts(String.duplicate("-", 50))
      IO.puts(istate.input_buffer)
      IO.puts(String.duplicate("-", 50))
      IO.puts("  Ready to parse: #{InputBuffer.ready_to_parse?(istate.input_buffer)}")
      IO.puts("  Continuation type: #{InputBuffer.continuation_type(istate.input_buffer)}")
    end

    if buffer_size > 0 do
      IO.puts("\n📝 Parser Buffer:")
      IO.puts(String.duplicate("-", 50))
      IO.puts(input)
      IO.puts(String.duplicate("-", 50))
    end

    IO.puts("")

    loop(istate)
  end

  defp handle_input(%InteractiveState{} = istate, ".ast") do
    case IncrementalParser.get_current_ast(istate.parser_pid) do
      {:ok, ast} ->
        IO.puts("\n🌳 Full Accumulated AST:")
        IO.puts(String.duplicate("-", 50))
        ASTUtils.print(ast)
        IO.puts(String.duplicate("-", 50))

      {:error, %{"reason" => "no_tree"}} ->
        IO.puts("\n⚠️  No AST yet - add some input first")

      {:error, reason} ->
        IO.puts("\n❌ Error getting AST: #{inspect(reason)}")
    end

    IO.puts("")

    loop(istate)
  end

  defp handle_input(%InteractiveState{} = istate, ".last") do
    case istate.last_ast_metadata do
      nil ->
        IO.puts("\n⚠️  No incremental changes yet")

      %{changed_nodes: changed_nodes} when changed_nodes != [] ->
        IO.puts("\n🔄 Last Incremental Changes:")
        IO.puts(String.duplicate("-", 50))

        Enum.each(changed_nodes, fn node ->
          ASTUtils.print(node)
        end)

        IO.puts(String.duplicate("-", 50))

      _ ->
        IO.puts("\n⚠️  No changes in last parse")
    end

    IO.puts("")

    loop(istate)
  end

  # New commands for debugging execution results
  defp handle_input(%InteractiveState{} = istate, ".result") do
    case InteractiveState.get_last_record(istate) do
      nil ->
        IO.puts("\n⚠️  No execution result yet")

      record ->
        IO.puts("\n📊 Last Execution Result:")
        IO.puts(String.duplicate("-", 50))
        IO.puts("Fragment:      #{String.trim(record.fragment)}")
        IO.puts("Exit Code:     #{record.exit_code}")
        IO.puts("Parse Time:    #{record.parse_metrics.duration_us}μs")
        IO.puts("Exec Time:     #{record.exec_metrics.duration_us}μs")
        IO.puts("Memory Delta:  #{record.exec_metrics.memory_delta} bytes")

        if record.execution_result do
          IO.puts("\nExecution Details:")
          IO.puts("  Status:      #{record.execution_result.status}")
          IO.puts("  Node Type:   #{record.execution_result.node_type}")
          if record.execution_result[:node_text], do: IO.puts("  Command:     #{record.execution_result.node_text}")
          if record.execution_result[:error], do: IO.puts("  Error:       #{record.execution_result.error}")
        end

        IO.puts("\nStdout: #{inspect(record.stdout)}")
        IO.puts("Stderr: #{inspect(record.stderr)}")
        IO.puts(String.duplicate("-", 50))
    end

    IO.puts("")

    loop(istate)
  end

  defp handle_input(%InteractiveState{} = istate, ".stdout") do
    case InteractiveState.get_last_record(istate) do
      nil ->
        IO.puts("\n⚠️  No execution result yet")

      record ->
        stdout = Utils.format_output(record.stdout)

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

    loop(istate)
  end

  defp handle_input(%InteractiveState{} = istate, ".stderr") do
    case InteractiveState.get_last_record(istate) do
      nil ->
        IO.puts("\n⚠️  No execution result yet")

      record ->
        stderr = Utils.format_output(record.stderr)

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

    loop(istate)
  end

  # Handle .debug command - toggle debug logging
  defp handle_input(%InteractiveState{} = istate, ".debug") do
    current_level = Logger.level()

    new_level = if current_level == :debug do
      :warning
    else
      :debug
    end

    Logger.configure(level: new_level)

    status = if new_level == :debug do
      "ON"
    else
      "OFF"
    end

    IO.puts("\n🔧 Debug logging is now #{status}")
    IO.puts("   Logger level: #{new_level}\n")

    loop(istate)
  end

  # Handle empty input - just continue accumulating if buffer is not empty
  defp handle_input(%InteractiveState{} = istate, "") do
    # If buffer is empty, just loop with empty buffer
    # If buffer has content, add newline and check if ready
    if istate.input_buffer == "" do
      loop(istate)
    else
      # Add newline to buffer
      new_buffer = istate.input_buffer <> "\n"

      # Check if ready to parse
      if InputBuffer.ready_to_parse?(new_buffer) do
        # Execute fragment using Executor
        execute_and_loop(%{istate | input_buffer: new_buffer})
      else
        # Continue accumulating
        loop(%{istate | input_buffer: new_buffer})
      end
    end
  end

  # Handle regular input - accumulate and check if ready to parse
  defp handle_input(%InteractiveState{} = istate, line) do
    # Add line to buffer with newline
    new_buffer = istate.input_buffer <> line <> "\n"

    # Check if buffer is ready to parse
    if InputBuffer.ready_to_parse?(new_buffer) do
      # Execute fragment using Executor
      execute_and_loop(%{istate | input_buffer: new_buffer})
    else
      # Not ready yet - continue accumulating
      loop(%{istate | input_buffer: new_buffer})
    end
  end

  # Execute fragment using Executor and update interactive state
  defp execute_and_loop(%InteractiveState{} = istate) do
    # Use Executor to parse, execute, and create ExecutionRecord
    case Executor.execute_fragment(istate.input_buffer, istate.cli_state) do
      {:ok, new_cli_state} ->
        # Drain any remaining PubSub events to prevent them from being processed later
        drain_pubsub_events(istate.session_id)

        # Get the last execution record
        last_record = List.last(new_cli_state.history)

        # Display output
        if last_record do
          stdout_str = Utils.format_output(last_record.stdout)
          stderr_str = Utils.format_output(last_record.stderr)

          if stdout_str != "", do: IO.write(stdout_str)
          if stderr_str != "", do: IO.write(:stderr, stderr_str)

          # Check for execution errors and display them
          if last_record.execution_result && last_record.execution_result.status == :error do
            error_msg = Map.get(last_record.execution_result, :error, "Unknown error")
            IO.puts(:stderr, "❌ #{error_msg}")
          else
            # Show exit code if non-zero (only for successful executions)
            if last_record.exit_code != 0 && last_record.exit_code != nil do
              IO.puts("⚠️  Exit code: #{last_record.exit_code}")
            end
          end
        end

        # Update state with new cli_state and clear input buffer
        # Wrap incremental_ast in expected format for .last command
        last_ast_metadata = if last_record && last_record.incremental_ast do
          %{changed_nodes: last_record.incremental_ast}
        else
          nil
        end

        new_istate = %{istate |
          cli_state: new_cli_state,
          input_buffer: "",
          last_ast_metadata: last_ast_metadata,
          previous_children: last_record && extract_children(last_record.full_ast)
        }
        loop(new_istate)

      {:error, %{"reason" => "parse_error"} = error} ->
        IO.puts(:stderr, "\n❌ Syntax error: Unable to parse input")
        if error["message"] do
          IO.puts(:stderr, "   #{error["message"]}")
        end
        IO.puts(:stderr, "")
        # Clear input buffer on error
        loop(%{istate | input_buffer: ""})

      {:error, reason} when is_binary(reason) ->
        IO.puts(:stderr, "\n❌ Error: #{reason}\n")
        # Clear input buffer on error
        loop(%{istate | input_buffer: ""})

      {:error, reason} ->
        IO.puts(:stderr, "\n❌ Execution error: #{inspect(reason)}\n")
        # Clear input buffer on error
        loop(%{istate | input_buffer: ""})
    end
  end

  # Drain any remaining PubSub events to prevent stale messages
  defp drain_pubsub_events(session_id) do
    receive do
      {:ast_incremental, _} -> drain_pubsub_events(session_id)
      {:executable_node, _, _} -> drain_pubsub_events(session_id)
      {:variable_set, _} -> drain_pubsub_events(session_id)
      {:parsing_failed, _} -> drain_pubsub_events(session_id)
      {:parsing_crashed, _} -> drain_pubsub_events(session_id)
    after
      0 -> :ok
    end
  end

  # Extract children from AST for tracking
  defp extract_children(%{children: children}) when is_list(children), do: children
  defp extract_children(_), do: []

end
