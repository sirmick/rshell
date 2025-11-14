defmodule RShell.CLIIfInteractiveTest do
  use ExUnit.Case, async: true

  alias RShell.CLI

  test "if statement works with line-by-line execution using execute_lines" do
    script = """
    if true; then
    echo a
    fi
    """

    IO.puts("\n=== Testing Line-by-Line Execution with execute_lines ===")
    IO.puts("Script:")
    IO.puts(script)
    IO.puts("")

    {:ok, state} = CLI.execute_lines(script)

    IO.puts("=== Execution Results ===")
    IO.puts("Total records: #{length(state.history)}")

    state.history
    |> Enum.with_index(1)
    |> Enum.each(fn {record, idx} ->
      IO.puts("\nRecord #{idx}:")
      IO.puts("  Fragment: #{String.trim(record.fragment)}")
      IO.puts("  Exit code: #{record.exit_code}")

      if record.stdout != [] do
        IO.puts("  Stdout: #{inspect(record.stdout)}")
      end

      if record.stderr != [] do
        IO.puts("  Stderr: #{inspect(record.stderr)}")
      end
    end)

    # Check if we got the echo output
    echo_records =
      Enum.filter(state.history, fn record ->
        record.stdout != [] and
          record.stdout != [""] and
          Enum.any?(record.stdout, &(&1 =~ "a"))
      end)

    IO.puts("\n=== Assertion ===")
    IO.puts("Found #{length(echo_records)} echo record(s) with output 'a'")

    if length(echo_records) == 0 do
      IO.puts("❌ FAILED: If statement body did not execute!")
      IO.puts("This shows the incremental parsing issue in interactive mode")
    else
      IO.puts("✅ SUCCESS: If statement executed correctly")
    end

    assert length(echo_records) >= 1, "Expected at least 1 echo output containing 'a'"
  end
end
