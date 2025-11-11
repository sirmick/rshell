defmodule RShell.CLI do
  @moduledoc """
  Interactive CLI for incremental Bash parsing with PubSub event handling.

  Reads input from stdin line by line, sends fragments to the
  incremental parser GenServer, and receives parse events via PubSub.

  ## Usage

      # Run the CLI
      mix run -e "RShell.CLI.main([])"

      # Or with escript
      ./rshell_cli

  ## Commands

  - Enter bash code line by line (each line is appended as a fragment)
  - Type `.reset` to clear parser state
  - Type `.status` to see current buffer info
  - Type `.ast` to show full accumulated AST
  - Type `.help` to show help
  - Type `.quit` or press Ctrl+D to exit
  """

  alias RShell.{IncrementalParser, Runtime, PubSub}

  @commands %{
    ".reset" => "Clear parser state and start fresh",
    ".status" => "Show current parser status (buffer size, errors)",
    ".ast" => "Show current AST without adding new input",
    ".help" => "Show this help message",
    ".quit" => "Exit the CLI"
  }

  def main(_args) do
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
      mode: :simulate,
      auto_execute: true
    )

    IO.puts("✅ Parser started (PID: #{inspect(parser_pid)})")
    IO.puts("✅ Runtime started (PID: #{inspect(runtime_pid)})")
    IO.puts("📡 Session ID: #{session_id}")
    IO.puts("🎬 Mode: simulate\n")

    # Subscribe to parser and runtime events
    PubSub.subscribe(session_id, [:ast, :executable, :runtime, :output])

    # Start the input loop with state tracking
    loop(parser_pid, runtime_pid, session_id, _previous_children = [])
  end

  defp loop(parser_pid, runtime_pid, session_id, previous_children) do
    # Read input with a short timeout to check for PubSub messages
    case IO.gets("rshell> ") do
      :eof ->
        IO.puts("\n👋 Goodbye!")
        :ok

      {:error, reason} ->
        IO.puts("❌ Error reading input: #{inspect(reason)}")
        loop(parser_pid, runtime_pid, session_id, previous_children)

      line ->
        line = String.trim(line)
        handle_input(parser_pid, runtime_pid, session_id, line, previous_children)
    end
  end

  defp handle_input(_parser_pid, _runtime_pid, _session_id, ".quit", _prev_children), do: IO.puts("\n👋 Goodbye!")
  defp handle_input(_parser_pid, _runtime_pid, _session_id, ".exit", _prev_children), do: IO.puts("\n👋 Goodbye!")

  defp handle_input(parser_pid, runtime_pid, session_id, ".help", prev_children) do
    IO.puts("\n📖 Available Commands:\n")

    Enum.each(@commands, fn {cmd, desc} ->
      IO.puts("  #{String.pad_trailing(cmd, 12)} - #{desc}")
    end)

    IO.puts("")
    loop(parser_pid, runtime_pid, session_id, prev_children)
  end

  defp handle_input(parser_pid, runtime_pid, session_id, ".reset", _prev_children) do
    :ok = IncrementalParser.reset(parser_pid)
    IO.puts("🔄 Parser state reset\n")
    loop(parser_pid, runtime_pid, session_id, [])
  end

  defp handle_input(parser_pid, runtime_pid, session_id, ".status", prev_children) do
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
    IO.puts("  Mode: #{context.mode}")

    if buffer_size > 0 do
      IO.puts("\n📝 Current Input:")
      IO.puts(String.duplicate("-", 50))
      IO.puts(input)
      IO.puts(String.duplicate("-", 50))
    end

    IO.puts("")
    loop(parser_pid, runtime_pid, session_id, prev_children)
  end

  defp handle_input(parser_pid, runtime_pid, session_id, ".ast", prev_children) do
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
    loop(parser_pid, runtime_pid, session_id, prev_children)
  end

  defp handle_input(parser_pid, runtime_pid, session_id, "", prev_children), do: loop(parser_pid, runtime_pid, session_id, prev_children)

  defp handle_input(parser_pid, runtime_pid, session_id, line, previous_children) do
    # Add newline to make it a complete line
    fragment = line <> "\n"

    # Submit fragment to parser (will trigger PubSub events)
    case IncrementalParser.append_fragment(parser_pid, fragment) do
      {:ok, _ast} ->
        # Wait for and handle PubSub events with timeout
        new_children = handle_pubsub_events(session_id, previous_children, 500, _execution_pending = false)
        loop(parser_pid, runtime_pid, session_id, new_children)

      {:error, %{"reason" => "buffer_overflow"} = error} ->
        IO.puts("\n❌ Buffer overflow!")
        IO.puts("   Current: #{error["current_size"]} bytes")
        IO.puts("   Fragment: #{error["fragment_size"]} bytes")
        IO.puts("   Max: #{error["max_size"]} bytes")
        IO.puts("   Use .reset to clear buffer\n")
        loop(parser_pid, runtime_pid, session_id, previous_children)

      {:error, reason} ->
        IO.puts("\n❌ Parse error: #{inspect(reason)}\n")
        loop(parser_pid, runtime_pid, session_id, previous_children)
    end
  end

  # Handle PubSub events from the parser and runtime
  # execution_pending tracks if we've seen an executable_node and are waiting for execution_completed
  defp handle_pubsub_events(session_id, previous_children, timeout, execution_pending) do
    receive do
      {:ast_updated, typed_ast} ->
        # Get current children from typed struct
        current_children = case typed_ast do
          %{children: children} when is_list(children) -> children
          _ -> []
        end

        # Continue collecting events
        handle_pubsub_events(session_id, current_children, timeout, execution_pending)

      {:executable_node, _typed_node, _command_count} ->
        # Executable node detected - runtime will handle execution
        # Mark that we're now waiting for execution to complete
        handle_pubsub_events(session_id, previous_children, timeout, true)

      {:execution_started, _info} ->
        # Command execution started
        handle_pubsub_events(session_id, previous_children, timeout, execution_pending)

      {:execution_completed, info} ->
        # Command execution completed
        exit_code = info.exit_code
        if exit_code != 0 do
          IO.puts("⚠️  Exit code: #{exit_code}")
        end
        
        # Execution is done - return immediately instead of waiting
        previous_children

      {:stdout, output} ->
        # Display command output
        IO.write(output)
        handle_pubsub_events(session_id, previous_children, timeout, execution_pending)

      {:stderr, output} ->
        # Display error output
        IO.write(:stderr, output)
        handle_pubsub_events(session_id, previous_children, timeout, execution_pending)

      {:variable_set, info} ->
        # Variable was set
        IO.puts("✓ #{info.name}=#{info.value}")
        handle_pubsub_events(session_id, previous_children, timeout, execution_pending)

    after
      timeout ->
        # No more events, return current state
        previous_children
    end
  end

  # Classify parse state from typed AST
  defp classify_parse_state_from_typed_ast(_typed_ast) do
    # For now, simplified - we'll assume complete if we got an executable node
    # In reality, we'd check the tree structure more carefully
    {:complete, %{has_errors: false}}
  end

  # Detect changes between previous and current children
  # Returns {new_nodes, modified_nodes}
  defp detect_changes(previous_children, current_children) do
    prev_count = length(previous_children)
    curr_count = length(current_children)

    cond do
      # More nodes now than before -> new nodes added
      curr_count > prev_count ->
        new_nodes = Enum.slice(current_children, prev_count..-1)
        {new_nodes, []}

      # Same count but content might have changed
      curr_count == prev_count && prev_count > 0 ->
        # Compare signatures (type + has_errors status)
        modified =
          Enum.zip(previous_children, current_children)
          |> Enum.with_index()
          |> Enum.filter(fn {{prev, curr}, _idx} ->
            node_signature(prev) != node_signature(curr)
          end)
          |> Enum.map(fn {{_prev, curr}, _idx} -> curr end)

        {[], modified}

      # No changes or count decreased (shouldn't happen in append-only)
      true ->
        {[], []}
    end
  end

  # Create a signature for a node to detect changes
  # Signature includes: type and text length
  defp node_signature(node) do
    type = node.__struct__ |> Module.split() |> List.last()
    text_len = String.length(node.source_info.text || "")
    {type, text_len}
  end

  # Pretty-print typed AST
  defp print_typed_ast(typed_node, indent) do
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
