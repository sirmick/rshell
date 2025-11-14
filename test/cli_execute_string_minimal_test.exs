defmodule RShell.CLIExecuteStringMinimalTest do
  use ExUnit.Case, async: true

  alias RShell.CLI

  test "minimal test - just execute and inspect" do
    IO.puts("\n=== Starting minimal test ===")
    result = CLI.execute_string("echo hello\n")
    IO.puts("Result: #{inspect(result)}")

    case result do
      {:ok, state} ->
        IO.puts("State session_id: #{state.session_id}")
        IO.puts("History length: #{length(state.history)}")

        if length(state.history) > 0 do
          record = List.last(state.history)
          IO.puts("\nRecord details:")
          IO.puts("  Fragment: #{inspect(record.fragment)}")
          IO.puts("  Timestamp: #{inspect(record.timestamp)}")
          IO.puts("  Exit code: #{inspect(record.exit_code)}")
          IO.puts("  Stdout: #{inspect(record.stdout)}")
          IO.puts("  Stderr: #{inspect(record.stderr)}")
          IO.puts("  Execution result: #{inspect(record.execution_result)}")
          IO.puts("  Full AST: #{inspect(record.full_ast != nil)}")
          IO.puts("  Incremental AST: #{inspect(record.incremental_ast != nil)}")
        else
          IO.puts("No history!")
        end

        assert true

      {:error, reason} ->
        IO.puts("Error: #{inspect(reason)}")
        flunk("execute_string failed")
    end
  end
end
