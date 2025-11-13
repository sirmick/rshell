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
  - `.ast` - Show current accumulated AST
  - `.last` - Show last executed fragment AST
  - `.help [builtin]` - Show help
  - `.quit` / `.exit` - Exit
  """

  alias RShell.{IncrementalParser, Runtime, PubSub, InputBuffer}
  alias BashParser.AST.Types

  @commands %{
    ".reset" => "Clear parser state and start fresh",
    ".status" => "Show current parser status (buffer size, errors)",
    ".ast" => "Show current AST without adding new input",
    ".last" => "Show the last executed command's AST",
    ".help" => "Show this help message or help for a builtin command",
    ".quit" => "Exit the CLI"
  }

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

    # Start the runtime GenServer
    {:ok, runtime_pid} = Runtime.start_link(
      session_id: session_id,
      auto_execute: true
    )

    IO.puts("✅ Parser started (PID: #{inspect(parser_pid)})")
    IO.puts("✅ Runtime started (PID: #{inspect(runtime_pid)})")
    IO.puts("📡 Session ID: #{session_id}\n")

    # Subscribe to parser and runtime events
    PubSub.subscribe(session_id, [:ast, :executable, :runtime, :output])

    # Start the input loop with state tracking
    loop(parser_pid, runtime_pid, session_id, _previous_children = [], _last_ast = nil, _input_buffer = "")
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
        {:ok, _runtime} = Runtime.start_link(session_id: session_id, auto_execute: true)

        PubSub.subscribe(session_id, [:output, :runtime])

        # Process lines through InputBuffer
        lines = String.split(content, "\n", trim: false)
        process_lines(lines, parser, session_id, "")

      {:error, reason} ->
        IO.puts(:stderr, "❌ Error reading #{file_path}: #{:file.format_error(reason)}")
        System.halt(1)
    end
  end

  defp process_lines([], _parser, _session_id, _buffer) do
    # Wait for any remaining output
    collect_output(500)
    :ok
  end

  defp process_lines([line | rest], parser, session_id, buffer) do
    new_buffer = buffer <> line <> "\n"

    if InputBuffer.ready_to_parse?(new_buffer) do
      # Send to parser (will trigger auto-execution via Runtime)
      # Only Command nodes will execute - others will be skipped/fail
      case IncrementalParser.append_fragment(parser, new_buffer) do
        {:ok, _} ->
          wait_for_execution()
          IncrementalParser.reset(parser)
          process_lines(rest, parser, session_id, "")

        {:error, reason} ->
          IO.puts(:stderr, "❌ Parse error: #{inspect(reason)}")
          process_lines(rest, parser, session_id, "")
      end
    else
      # Continue accumulating
      process_lines(rest, parser, session_id, new_buffer)
    end
  end

  # Wait for execution_completed or execution_failed event
  defp wait_for_execution do
    receive do
      {:stdout, output} ->
        IO.write(output)
        wait_for_execution()

      {:stderr, output} ->
        IO.write(:stderr, output)
        wait_for_execution()

      {:execution_completed, _info} ->
        :ok

      {:execution_failed, _error} ->
        # Runtime couldn't execute (e.g., not a Command node)
        :ok
    after
      1000 ->
        # Timeout means nothing executable
        :ok
    end
  end

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

  ## Interactive Mode Helper (collect terminal output)

  defp collect_output(timeout) do
    receive do
      {:stdout, output} ->
        IO.write(output)
        collect_output(timeout)

      {:stderr, output} ->
        IO.write(:stderr, output)
        collect_output(timeout)
    after
      timeout -> :ok
    end
  end

  defp loop(parser_pid, runtime_pid, session_id, previous_children, last_ast, input_buffer) do
    # Determine prompt based on input buffer state
    prompt = get_prompt(input_buffer)

    # Read input with a short timeout to check for PubSub messages
    case IO.gets(prompt) do
      :eof ->
        IO.puts("\n👋 Goodbye!")
        :ok

      {:error, reason} ->
        IO.puts("❌ Error reading input: #{inspect(reason)}")
        loop(parser_pid, runtime_pid, session_id, previous_children, last_ast, input_buffer)

      line ->
        line = String.trim_trailing(line, "\n")
        handle_input(parser_pid, runtime_pid, session_id, line, previous_children, last_ast, input_buffer)
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

  defp handle_input(_parser_pid, _runtime_pid, _session_id, ".quit", _prev_children, _last_ast, _input_buffer), do: IO.puts("\n👋 Goodbye!")
  defp handle_input(_parser_pid, _runtime_pid, _session_id, ".exit", _prev_children, _last_ast, _input_buffer), do: IO.puts("\n👋 Goodbye!")

  defp handle_input(parser_pid, runtime_pid, session_id, ".help", prev_children, last_ast, input_buffer) do
    IO.puts("\n📖 Available Commands:\n")

    Enum.each(@commands, fn {cmd, desc} ->
      IO.puts("  #{String.pad_trailing(cmd, 12)} - #{desc}")
    end)

    IO.puts("\n💡 For help on builtins, use: .help <builtin>")
    IO.puts("   Example: .help echo\n")

    loop(parser_pid, runtime_pid, session_id, prev_children, last_ast, input_buffer)
  end

  defp handle_input(parser_pid, runtime_pid, session_id, ".help " <> builtin_name, prev_children, last_ast, input_buffer) do
    builtin = String.trim(builtin_name)

    if RShell.Builtins.is_builtin?(builtin) do
      help_text = RShell.Builtins.get_builtin_help(builtin)
      IO.puts("\n" <> help_text <> "\n")
    else
      IO.puts("\n❌ Unknown builtin: #{builtin}")
      IO.puts("💡 Use '.help' to see available commands\n")
    end

    loop(parser_pid, runtime_pid, session_id, prev_children, last_ast, input_buffer)
  end

  defp handle_input(parser_pid, runtime_pid, session_id, ".reset", _prev_children, last_ast, _input_buffer) do
    :ok = IncrementalParser.reset(parser_pid)
    IO.puts("🔄 Parser state reset\n")
    # Also clear input buffer on reset
    loop(parser_pid, runtime_pid, session_id, [], last_ast, "")
  end

  defp handle_input(parser_pid, runtime_pid, session_id, ".status", prev_children, last_ast, input_buffer) do
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
    loop(parser_pid, runtime_pid, session_id, prev_children, last_ast, input_buffer)
  end

  defp handle_input(parser_pid, runtime_pid, session_id, ".ast", prev_children, last_ast, input_buffer) do
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
    loop(parser_pid, runtime_pid, session_id, prev_children, last_ast, input_buffer)
  end

  defp handle_input(parser_pid, runtime_pid, session_id, ".last", prev_children, last_ast, input_buffer) do
    case last_ast do
      nil ->
        IO.puts("\n⚠️  No previous command executed yet")

      ast ->
        IO.puts("\n🌳 Last Executed AST:")
        IO.puts(String.duplicate("-", 50))
        print_typed_ast(ast, 0)
        IO.puts(String.duplicate("-", 50))
    end

    IO.puts("")
    loop(parser_pid, runtime_pid, session_id, prev_children, last_ast, input_buffer)
  end

  # Handle empty input - just continue accumulating if buffer is not empty
  defp handle_input(parser_pid, runtime_pid, session_id, "", prev_children, last_ast, input_buffer) do
    # If buffer is empty, just loop with empty buffer
    # If buffer has content, add newline and check if ready
    if input_buffer == "" do
      loop(parser_pid, runtime_pid, session_id, prev_children, last_ast, input_buffer)
    else
      # Add newline to buffer
      new_buffer = input_buffer <> "\n"

      # Check if ready to parse
      if InputBuffer.ready_to_parse?(new_buffer) do
        # Send complete fragment to parser
        send_to_parser(parser_pid, runtime_pid, session_id, new_buffer, prev_children, last_ast)
      else
        # Continue accumulating
        loop(parser_pid, runtime_pid, session_id, prev_children, last_ast, new_buffer)
      end
    end
  end

  # Handle regular input - accumulate and check if ready to parse
  defp handle_input(parser_pid, runtime_pid, session_id, line, previous_children, last_ast, input_buffer) do
    # Add line to buffer with newline
    new_buffer = input_buffer <> line <> "\n"

    # Check if buffer is ready to parse
    if InputBuffer.ready_to_parse?(new_buffer) do
      # Send complete fragment to parser
      send_to_parser(parser_pid, runtime_pid, session_id, new_buffer, previous_children, last_ast)
    else
      # Not ready yet - continue accumulating
      loop(parser_pid, runtime_pid, session_id, previous_children, last_ast, new_buffer)
    end
  end

  # Helper function to send complete fragment to parser
  defp send_to_parser(parser_pid, runtime_pid, session_id, fragment, previous_children, last_ast) do
    # Submit complete fragment to parser (will trigger PubSub events)
    case IncrementalParser.append_fragment(parser_pid, fragment) do
      {:ok, _ast} ->
        # Wait for and handle PubSub events
        # Use longer timeout to make problems visible
        {new_children, executed_ast} = handle_pubsub_events(parser_pid, session_id, previous_children, 1000, _execution_pending = false, last_ast)
        # Clear input buffer after successful parse
        loop(parser_pid, runtime_pid, session_id, new_children, executed_ast, "")

      {:error, %{"reason" => "buffer_overflow"} = error} ->
        IO.puts("\n❌ Buffer overflow!")
        IO.puts("   Current: #{error["current_size"]} bytes")
        IO.puts("   Fragment: #{error["fragment_size"]} bytes")
        IO.puts("   Max: #{error["max_size"]} bytes")
        IO.puts("   Use .reset to clear buffer\n")
        # Keep input buffer on error
        loop(parser_pid, runtime_pid, session_id, previous_children, last_ast, "")

      {:error, reason} ->
        IO.puts("\n❌ Parse error: #{inspect(reason)}\n")
        # Clear input buffer on error
        loop(parser_pid, runtime_pid, session_id, previous_children, last_ast, "")
    end
  end

  # Handle PubSub events from the parser and runtime
  # execution_pending tracks if we've seen an executable_node and are waiting for execution_completed
  # Returns {children, executed_ast} tuple
  defp handle_pubsub_events(parser_pid, session_id, previous_children, timeout, execution_pending, last_ast) do
    receive do
      {:ast_updated, typed_ast} ->
        # Get current children from typed struct
        current_children = case typed_ast do
          %{children: children} when is_list(children) -> children
          _ -> []
        end

        # Continue collecting events
        handle_pubsub_events(parser_pid, session_id, current_children, timeout, execution_pending, last_ast)

      {:parsing_complete} ->
        # Parser has finished - if no execution is pending, return immediately
        if execution_pending do
          # Still waiting for execution, continue listening
          handle_pubsub_events(parser_pid, session_id, previous_children, timeout, execution_pending, last_ast)
        else
          # No execution expected, return immediately
          {previous_children, last_ast}
        end

      {:parsing_failed, error} ->
        # Parser failed - display error and return
        IO.puts("\n❌ Parsing failed: #{inspect(error)}\n")
        {previous_children, last_ast}

      {:parsing_crashed, error} ->
        # Parser crashed unexpectedly - display error and return
        IO.puts("\n❌ Parser crashed: #{error.reason}")
        if error[:exception] do
          IO.puts("   #{error.exception}\n")
        end
        {previous_children, last_ast}

      {:executable_node, _typed_node} ->
        # Executable node detected - runtime will handle execution
        # Mark that we're now waiting for execution to complete
        # Use longer timeout (5 seconds) for actual execution
        handle_pubsub_events(parser_pid, session_id, previous_children, 5000, true, last_ast)

      {:execution_started, _info} ->
        # Command execution started
        handle_pubsub_events(parser_pid, session_id, previous_children, timeout, execution_pending, last_ast)

      {:execution_completed, info} ->
        # Command execution completed
        exit_code = info.exit_code
        if exit_code != 0 do
          IO.puts("⚠️  Exit code: #{exit_code}")
        end

        # Capture the current AST before reset
        executed_ast = case IncrementalParser.get_current_ast(parser_pid) do
          {:ok, ast} -> ast
          _ -> last_ast
        end

        # Auto-reset parser buffer after successful execution
        :ok = IncrementalParser.reset(parser_pid)

        # Execution is done - return with executed AST
        {previous_children, executed_ast}

      {:execution_failed, error_info} ->
        # Runtime execution failed (crashed)
        IO.puts("\n❌ Execution failed: #{error_info.reason}")
        if error_info[:message] do
          IO.puts("   #{error_info.message}")
        end

        # Capture the current AST before reset (even on failure)
        executed_ast = case IncrementalParser.get_current_ast(parser_pid) do
          {:ok, ast} -> ast
          _ -> last_ast
        end

        # Auto-reset parser buffer even on execution failure
        :ok = IncrementalParser.reset(parser_pid)

        # Return with executed AST
        {previous_children, executed_ast}

      {:stdout, output} ->
        # Display command output
        IO.write(output)
        handle_pubsub_events(parser_pid, session_id, previous_children, timeout, execution_pending, last_ast)

      {:stderr, output} ->
        # Display error output
        IO.write(:stderr, output)
        handle_pubsub_events(parser_pid, session_id, previous_children, timeout, execution_pending, last_ast)

      {:variable_set, info} ->
        # Variable was set
        IO.puts("✓ #{info.name}=#{info.value}")
        handle_pubsub_events(parser_pid, session_id, previous_children, timeout, execution_pending, last_ast)

    after
      timeout ->
        # No more events, return current state
        if execution_pending do
          IO.puts("\n⏱️  Timeout waiting for execution to complete (#{timeout}ms)")
          IO.puts("   This should not happen - runtime may have crashed or is not responding")
        end
        {previous_children, last_ast}
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
end
