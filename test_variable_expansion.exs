# Test variable expansion in echo
alias RShell.CLI

# Test the failing case
IO.puts("\n=== Test: Variable expansion in echo ===")
script = """
X = 5
echo $X
"""

case CLI.execute_lines(script) do
  {:ok, state} ->
    stdout = Enum.flat_map(state.history, & &1.stdout)
    IO.puts("Stdout: #{inspect(stdout)}")
    if Enum.any?(stdout, &(&1 =~ "5")) do
      IO.puts("✅ SUCCESS: Variable expansion works!")
    else
      IO.puts("❌ FAILURE: Expected '5', got #{inspect(stdout)}")
    end
  {:error, reason} ->
    IO.puts("❌ FAILURE: #{inspect(reason)}")
end
