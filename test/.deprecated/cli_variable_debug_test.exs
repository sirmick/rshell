defmodule RShell.CLIVariableDebugTest do
  use ExUnit.Case, async: true

  alias RShell.CLI

  test "debug variable assignment and expansion" do
    IO.puts("\n=== Test 1: Variable assignment ===")
    {:ok, state1} = CLI.execute_string("X=5\n")

    record1 = List.last(state1.history)
    IO.puts("Fragment: #{inspect(record1.fragment)}")
    IO.puts("Exit code: #{inspect(record1.exit_code)}")
    IO.puts("Stdout: #{inspect(record1.stdout)}")
    IO.puts("Stderr: #{inspect(record1.stderr)}")
    IO.puts("Context.env[\"X\"]: #{inspect(record1.context.env["X"])}")
    IO.puts("Execution result: #{inspect(record1.execution_result)}")

    IO.puts("\n=== Test 2: Variable expansion ===")
    {:ok, state2} = CLI.execute_string("echo $X\n", state: state1)

    record2 = List.last(state2.history)
    IO.puts("Fragment: #{inspect(record2.fragment)}")
    IO.puts("Exit code: #{inspect(record2.exit_code)}")
    IO.puts("Stdout: #{inspect(record2.stdout)}")
    IO.puts("Stderr: #{inspect(record2.stderr)}")
    IO.puts("Execution result: #{inspect(record2.execution_result)}")
  end
end
