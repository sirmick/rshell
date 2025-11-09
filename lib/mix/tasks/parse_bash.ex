defmodule Mix.Tasks.ParseBash do
  @shortdoc "Parse a Bash script and display its AST"
  @moduledoc """
  Parses a Bash script using tree-sitter-bash and displays the AST structure.

  ## Usage

      mix parse_bash <script_file>

  ## Examples

      mix parse_bash script.sh
      mix parse_bash /path/to/bash/script.sh

  """

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    case parse_args(args) do
      :help ->
        help()

      {:error, message} ->
        Mix.shell().error(message)
        help()

      {:ok, script_path} ->
        parse_and_display(script_path)
    end
  end

  defp parse_args([]), do: {:error, "No script file provided"}
  defp parse_args(["-h" | _]), do: :help
  defp parse_args(["--help" | _]), do: :help
  defp parse_args([script_path]) do
    if File.exists?(script_path) do
      {:ok, script_path}
    else
      {:error, "File not found: #{script_path}"}
    end
  end

  defp help do
    Mix.shell().info("""
    Usage: mix parse_bash <script_file>

    Parse a Bash script and display its Abstract Syntax Tree.

    Options:
      -h, --help    Show this help message

    Examples:
      mix parse_bash script.sh
      mix parse_bash /path/to/bash/script.sh

    The output shows the hierarchical structure of the parsed Bash script,
    including node types, positions in the source code, and the actual text.
    """)
  end

  defp parse_and_display(script_path) do
    Mix.shell().info("Parsing Bash script: #{script_path}")

    case RShell.parse_file(script_path) do
      {:ok, ast} ->
        Mix.shell().info("✅ Parse successful!")
        Mix.shell().info("=")

        display_ast(ast, 0)

        Mix.shell().info("=")
        Mix.shell().info("AST Summary:")
        display_summary(ast)

      {:error, reason} ->
        Mix.shell().error("❌ Parse failed: #{reason}")
        System.halt(1)
    end
  end

  defp display_ast(%{kind: kind, text: text, start_row: start_row, start_col: start_col, end_row: end_row, end_col: end_col, children: children} = ast_node, indent) do
    indent_str = String.duplicate("  ", indent)

    node_info = """
    #{indent_str}#{kind} [#{start_row + 1}:#{start_col + 1} - #{end_row + 1}:#{end_col + 1}] '#{String.replace(text, "\n", "\\n")}'
    """
    Mix.shell().info(node_info)

    Enum.each(children, &display_ast(&1, indent + 1))
  end

  defp display_summary(ast) do
    commands = RShell.commands(ast)
    functions = RShell.function_definitions(ast)

    Mix.shell().info("  Commands: #{length(commands)}")
    Mix.shell().info("  Functions: #{length(functions)}")
  end
end
