defmodule DemoVariableIfTest do
  use ExUnit.Case, async: true

  alias RShell.CLI

  # Demo script used by both tests
  @demo_script """
  X=5
  if test $X = 5; then
    echo "X equals 5!"
  else
    echo "X does not equal 5"
  fi
  """

  describe "execute_string/2 - whole script at once" do
    test "variable assignment with if statement works end-to-end" do
      IO.puts("\n=== Testing with execute_string (whole script) ===")
      IO.puts(@demo_script)
      IO.puts("=== Execution Results ===\n")

      # Execute entire script as one unit
      {:ok, state} = CLI.execute_string(@demo_script)

      IO.puts("\n=== Collected #{length(state.history)} execution records ===")

      # Print each execution record
      Enum.each(state.history, fn record ->
        IO.puts("[#{get_node_type(record)}] fragment: #{String.trim(record.fragment)}")

        if record.stdout != [] do
          IO.puts("  stdout: #{inspect(record.stdout)}")
        end

        if record.exit_code != 0 do
          IO.puts("  exit_code: #{record.exit_code}")
        end
      end)

      # Verify results
      echo_records = find_echo_records(state.history)
      assert length(echo_records) == 1, "Expected 1 echo output, got #{length(echo_records)}"

      [echo_record] = echo_records
      assert echo_record.exit_code == 0
      assert Enum.any?(echo_record.stdout, &(&1 =~ "X equals 5!"))

      IO.puts("\n✅ execute_string test passed!")
    end
  end

  describe "execute_lines/2 - line by line with InputBuffer" do
    test "variable assignment with if statement works end-to-end" do
      IO.puts("\n=== Testing with execute_lines (line-by-line with InputBuffer) ===")
      IO.puts(@demo_script)
      IO.puts("=== Execution Results ===\n")

      # Execute line-by-line through InputBuffer
      {:ok, state} = CLI.execute_lines(@demo_script)

      IO.puts("\n=== Collected #{length(state.history)} execution records ===")

      # Print each execution record
      Enum.each(state.history, fn record ->
        IO.puts("[#{get_node_type(record)}] fragment: #{String.trim(record.fragment)}")

        if record.stdout != [] do
          IO.puts("  stdout: #{inspect(record.stdout)}")
        end

        if record.exit_code != 0 do
          IO.puts("  exit_code: #{record.exit_code}")
        end

        IO.puts("  Parse time: #{record.parse_metrics.duration_us}μs")
        IO.puts("  Exec time: #{record.exec_metrics.duration_us}μs")
      end)

      # Verify results
      echo_records = find_echo_records(state.history)
      assert length(echo_records) == 1, "Expected 1 echo output, got #{length(echo_records)}"

      [echo_record] = echo_records
      assert echo_record.exit_code == 0
      assert Enum.any?(echo_record.stdout, &(&1 =~ "X equals 5!"))

      # Verify InputBuffer worked correctly:
      # - First record should be X=5 (line ready to parse)
      # - Second record should be entire if statement (accumulated until 'fi')
      assert length(state.history) == 2, "Expected 2 execution records with InputBuffer"

      first_record = List.first(state.history)
      assert first_record.fragment =~ "X=5"

      second_record = List.last(state.history)
      assert second_record.fragment =~ "if test"
      assert second_record.fragment =~ "fi"

      IO.puts(
        "\n✅ execute_lines test passed! InputBuffer correctly waited for complete if statement."
      )
    end
  end

  describe "performance comparison" do
    test "both methods complete quickly without timeouts" do
      IO.puts("\n=== Performance Comparison ===")

      # Test execute_string
      start = System.monotonic_time(:millisecond)
      {:ok, state1} = CLI.execute_string(@demo_script)
      duration1 = System.monotonic_time(:millisecond) - start
      IO.puts("execute_string: #{duration1}ms (#{length(state1.history)} records)")

      # Test execute_lines
      start = System.monotonic_time(:millisecond)
      {:ok, state2} = CLI.execute_lines(@demo_script)
      duration2 = System.monotonic_time(:millisecond) - start
      IO.puts("execute_lines:  #{duration2}ms (#{length(state2.history)} records)")

      # Both should complete quickly (< 1 second)
      assert duration1 < 1000, "execute_string took too long: #{duration1}ms"
      assert duration2 < 1000, "execute_lines took too long: #{duration2}ms"

      IO.puts("\n✅ Both methods complete quickly!")
    end
  end

  # Helper functions

  defp find_echo_records(history) do
    Enum.filter(history, fn record ->
      record.stdout != [] and
        record.stdout != [""] and
        Enum.any?(record.stdout, &(&1 =~ "X equals 5"))
    end)
  end

  defp get_node_type(%{execution_result: %{node_type: type}}), do: type
  defp get_node_type(_), do: "Unknown"
end
