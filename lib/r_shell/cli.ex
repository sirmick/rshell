defmodule RShell.CLI do
  @moduledoc """
  Interactive CLI for incremental Bash parsing.

  Reads input from stdin line by line, sends fragments to the
  incremental parser GenServer, and prints the resulting AST.

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
  - Type `.quit` or press Ctrl+D to exit
  """

  alias RShell.IncrementalParser

  @commands %{
    ".reset" => "Clear parser state and start fresh",
    ".status" => "Show current parser status (buffer size, errors)",
    ".ast" => "Show current AST without adding new input",
    ".help" => "Show this help message",
    ".quit" => "Exit the CLI"
  }

  def main(_args) do
    IO.puts("\n🐚 RShell - Interactive Incremental Bash Parser")
    IO.puts("=" |> String.duplicate(50))
    IO.puts("Type bash code line by line. Commands start with '.'")
    IO.puts("Type .help for available commands\n")

    # Start the parser GenServer
    {:ok, pid} = IncrementalParser.start_link(name: :rshell_cli_parser)
    IO.puts("✅ Parser started (PID: #{inspect(pid)})\n")

    # Start the input loop with state tracking for incremental display
    # Track previous children signatures (type + has_errors) to detect changes
    loop(pid, _previous_children = [])
  end

  defp loop(parser_pid, previous_children) do
    # Read input
    case IO.gets("rshell> ") do
      :eof ->
        IO.puts("\n👋 Goodbye!")
        :ok

      {:error, reason} ->
        IO.puts("❌ Error reading input: #{inspect(reason)}")
        loop(parser_pid, previous_children)

      line ->
        line = String.trim(line)
        handle_input(parser_pid, line, previous_children)
    end
  end

  defp handle_input(_parser_pid, ".quit", _prev_children), do: IO.puts("\n👋 Goodbye!")
  defp handle_input(_parser_pid, ".exit", _prev_children), do: IO.puts("\n👋 Goodbye!")

  defp handle_input(parser_pid, ".help", prev_children) do
    IO.puts("\n📖 Available Commands:\n")

    Enum.each(@commands, fn {cmd, desc} ->
      IO.puts("  #{String.pad_trailing(cmd, 12)} - #{desc}")
    end)

    IO.puts("")
    loop(parser_pid, prev_children)
  end

  defp handle_input(parser_pid, ".reset", _prev_children) do
    :ok = IncrementalParser.reset(parser_pid)
    IO.puts("🔄 Parser state reset\n")
    loop(parser_pid, [])
  end

  defp handle_input(parser_pid, ".status", prev_children) do
    buffer_size = IncrementalParser.get_buffer_size(parser_pid)
    has_errors = IncrementalParser.has_errors?(parser_pid)
    input = IncrementalParser.get_accumulated_input(parser_pid)

    IO.puts("\n📊 Parser Status:")
    IO.puts("  Buffer size: #{buffer_size} bytes")
    IO.puts("  Has errors: #{has_errors}")
    IO.puts("  Lines accumulated: #{length(String.split(input, "\n")) - 1}")

    if buffer_size > 0 do
      IO.puts("\n📝 Current Input:")
      IO.puts(String.duplicate("-", 50))
      IO.puts(input)
      IO.puts(String.duplicate("-", 50))
    end

    IO.puts("")
    loop(parser_pid, prev_children)
  end

  defp handle_input(parser_pid, ".ast", prev_children) do
    case IncrementalParser.get_current_ast(parser_pid) do
      {:ok, ast} ->
        IO.puts("\n🌳 Full Accumulated AST:")
        IO.puts(String.duplicate("-", 50))
        print_ast(ast)
        IO.puts(String.duplicate("-", 50))

      {:error, %{"reason" => "no_tree"}} ->
        IO.puts("\n⚠️  No AST yet - add some input first")

      {:error, reason} ->
        IO.puts("\n❌ Error getting AST: #{inspect(reason)}")
    end

    IO.puts("")
    loop(parser_pid, prev_children)
  end

  defp handle_input(parser_pid, "", prev_children), do: loop(parser_pid, prev_children)

  defp handle_input(parser_pid, line, previous_children) do
    # Add newline to make it a complete line
    fragment = line <> "\n"

    new_children = case IncrementalParser.append_fragment(parser_pid, fragment) do
      {:ok, ast} ->
        IO.puts("\n✅ Parsed successfully!")

        # Check for errors
        if ast["has_errors"] do
          IO.puts("⚠️  Parse tree has errors\n")
        end

        # Get current children
        current_children = ast["children"] || []

        # Determine what changed: new nodes or modified nodes
        {new_nodes, modified_nodes} = detect_changes(previous_children, current_children)

        cond do
          length(new_nodes) > 0 ->
            IO.puts("➕ New nodes added (#{length(new_nodes)}):")
            IO.puts(String.duplicate("-", 50))
            Enum.each(new_nodes, fn node ->
              print_ast(node, 0)
            end)
            IO.puts(String.duplicate("-", 50))
            IO.puts("💡 Use `.ast` to see full accumulated AST\n")

          length(modified_nodes) > 0 ->
            IO.puts("🔄 Nodes updated (#{length(modified_nodes)}):")
            IO.puts(String.duplicate("-", 50))
            Enum.each(modified_nodes, fn node ->
              print_ast(node, 0)
            end)
            IO.puts(String.duplicate("-", 50))
            IO.puts("💡 Use `.ast` to see full accumulated AST\n")

          true ->
            IO.puts("ℹ️  No changes detected (fragment may be whitespace)\n")
        end

        current_children

      {:error, %{"reason" => "buffer_overflow"} = error} ->
        IO.puts("\n❌ Buffer overflow!")
        IO.puts("   Current: #{error["current_size"]} bytes")
        IO.puts("   Fragment: #{error["fragment_size"]} bytes")
        IO.puts("   Max: #{error["max_size"]} bytes")
        IO.puts("   Use .reset to clear buffer\n")
        previous_children

      {:error, reason} ->
        IO.puts("\n❌ Parse error: #{inspect(reason)}\n")
        previous_children
    end

    loop(parser_pid, new_children)
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
  # Signature includes: type, has_errors, and text length
  defp node_signature(node) when is_map(node) do
    type = node["type"] || "unknown"
    has_errors = node["has_errors"] || false
    text_len = String.length(node["text"] || "")
    {type, has_errors, text_len}
  end
  defp node_signature(_), do: nil

  # Pretty-print AST (simplified version)
  defp print_ast(ast, indent \\ 0) do
    prefix = String.duplicate("  ", indent)

    type = ast["type"] || "unknown"
    text = ast["text"] || ""

    # Truncate long text
    display_text =
      if String.length(text) > 40 do
        String.slice(text, 0, 37) <> "..."
      else
        text
      end

    IO.puts("#{prefix}[#{type}] #{inspect(display_text)}")

    # Print children recursively
    if children = ast["children"] do
      if is_list(children) do
        Enum.each(children, fn child ->
          if is_map(child) do
            print_ast(child, indent + 1)
          end
        end)
      end
    end

    # Print named fields
    ast
    |> Map.drop(["type", "text", "children", "start_row", "start_col", "end_row", "end_col", "has_errors"])
    |> Enum.each(fn {key, value} ->
      cond do
        is_map(value) ->
          IO.puts("#{prefix}  .#{key}:")
          print_ast(value, indent + 2)

        is_list(value) && Enum.all?(value, &is_map/1) ->
          IO.puts("#{prefix}  .#{key}: [#{length(value)} items]")
          Enum.each(value, fn item ->
            print_ast(item, indent + 2)
          end)

        true ->
          :skip
      end
    end)
  end
end
