defmodule DemoVariableForTest do
  use ExUnit.Case, async: true

  alias RShell.CLI

  # Demo script for for loop with native types
  @demo_script_simple """
  X=5
  for i in 1 2 3; do
    echo "Loop iteration: $i"
  done
  echo "After loop, X=$X"
  """

  # Demo script with native type preservation
  @demo_script_types """
  env ITEMS='["alpha","beta","gamma"]'
  for item in $ITEMS; do
    inspect item
    echo "Processing: $item"
  done
  """

  # Demo script with map type
  @demo_script_map """
  env CONFIG='{"host":"localhost","port":5432}'
  inspect CONFIG
  echo "Host is $CONFIG"
  """

  describe "execute_string/2 - for loop with simple values" do
    test "iterates over explicit values and preserves outer variable" do
      IO.puts("\n=== Testing for loop with execute_string ===")
      IO.puts(@demo_script_simple)
      IO.puts("=== Execution Results ===\n")

      # Execute entire script as one unit
      {:ok, state} = CLI.execute_string(@demo_script_simple)

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

      # Verify we have the expected echo outputs
      echo_records = find_echo_records(state.history)

      # Should have 3 loop iterations + 1 after loop = 4 echo outputs
      assert length(echo_records) >= 4,
             "Expected at least 4 echo outputs, got #{length(echo_records)}"

      # Check loop iterations
      loop_outputs =
        Enum.filter(echo_records, fn record ->
          Enum.any?(record.stdout, &(&1 =~ "Loop iteration"))
        end)

      assert length(loop_outputs) == 3, "Expected 3 loop iterations"

      # Check after-loop output (X should still be 5)
      after_outputs =
        Enum.filter(echo_records, fn record ->
          Enum.any?(record.stdout, &(&1 =~ "After loop, X=5"))
        end)

      assert length(after_outputs) == 1, "Expected 1 after-loop output"

      IO.puts("\n✅ execute_string for loop test passed!")
    end
  end

  describe "execute_lines/2 - for loop with InputBuffer" do
    test "iterates over explicit values line-by-line" do
      IO.puts("\n=== Testing for loop with execute_lines (line-by-line) ===")
      IO.puts(@demo_script_simple)
      IO.puts("=== Execution Results ===\n")

      # Execute line-by-line through InputBuffer
      {:ok, state} = CLI.execute_lines(@demo_script_simple)

      IO.puts("\n=== Collected #{length(state.history)} execution records ===")

      # Print each execution record
      Enum.each(state.history, fn record ->
        IO.puts("[#{get_node_type(record)}] fragment: #{String.trim(record.fragment)}")

        if record.stdout != [] do
          IO.puts("  stdout: #{inspect(record.stdout)}")
        end

        IO.puts("  Parse time: #{record.parse_metrics.duration_us}μs")
        IO.puts("  Exec time: #{record.exec_metrics.duration_us}μs")
      end)

      # Verify InputBuffer accumulated the for loop correctly
      # Should have 3 execution records:
      # 1. X=5 (single line, ready immediately)
      # 2. for...done (accumulated until 'done')
      # 3. echo "After loop..." (single line, ready immediately)
      assert length(state.history) >= 2, "Expected at least 2 execution records with InputBuffer"

      # Check that for loop was accumulated
      for_record =
        Enum.find(state.history, fn record ->
          record.fragment =~ "for i in" and record.fragment =~ "done"
        end)

      assert for_record != nil, "For loop should be in a single execution record"

      # Verify echo outputs
      echo_records = find_echo_records(state.history)
      assert length(echo_records) >= 4, "Expected at least 4 echo outputs"

      IO.puts(
        "\n✅ execute_lines for loop test passed! InputBuffer correctly accumulated for loop."
      )
    end
  end

  describe "execute_string/2 - for loop with native type preservation" do
    test "preserves list type through for loop iterations" do
      IO.puts("\n=== Testing type preservation with execute_string ===")
      IO.puts(@demo_script_types)
      IO.puts("=== Execution Results ===\n")

      # Execute entire script
      {:ok, state} = CLI.execute_string(@demo_script_types)

      IO.puts("\n=== Collected #{length(state.history)} execution records ===")

      # Print execution records
      Enum.each(state.history, fn record ->
        IO.puts("[#{get_node_type(record)}] fragment: #{String.trim(record.fragment)}")

        if record.stdout != [] do
          IO.puts("  stdout: #{inspect(record.stdout)}")
        end
      end)

      # Find inspect outputs to verify type preservation
      inspect_records =
        Enum.filter(state.history, fn record ->
          record.stdout != [] and Enum.any?(record.stdout, &(&1 =~ "Type:"))
        end)

      # Should have 3 inspect outputs (one per loop iteration)
      assert length(inspect_records) >= 3,
             "Expected at least 3 inspect outputs, got #{length(inspect_records)}"

      # Verify each inspect shows the item type
      Enum.each(inspect_records, fn record ->
        stdout_str = Enum.join(record.stdout, "")
        # Each iteration should show the variable type
        assert stdout_str =~ "item:", "Should show variable name"
        assert stdout_str =~ "Type:", "Should show type information"
      end)

      IO.puts("\n✅ Type preservation test passed!")
    end
  end

  describe "execute_lines/2 - for loop with native type preservation" do
    test "preserves list type through for loop iterations (line-by-line)" do
      IO.puts("\n=== Testing type preservation with execute_lines ===")
      IO.puts(@demo_script_types)
      IO.puts("=== Execution Results ===\n")

      # Execute line-by-line
      {:ok, state} = CLI.execute_lines(@demo_script_types)

      IO.puts("\n=== Collected #{length(state.history)} execution records ===")

      # Print execution records
      Enum.each(state.history, fn record ->
        IO.puts("[#{get_node_type(record)}] fragment: #{String.trim(record.fragment)}")

        if record.stdout != [] do
          IO.puts("  stdout: #{inspect(record.stdout)}")
        end
      end)

      # Verify the for loop was accumulated as a single fragment
      for_record =
        Enum.find(state.history, fn record ->
          record.fragment =~ "for item in" and record.fragment =~ "done"
        end)

      assert for_record != nil, "For loop should be accumulated by InputBuffer"

      # Find inspect outputs
      inspect_records =
        Enum.filter(state.history, fn record ->
          record.stdout != [] and Enum.any?(record.stdout, &(&1 =~ "Type:"))
        end)

      assert length(inspect_records) >= 3, "Expected at least 3 inspect outputs"

      IO.puts("\n✅ Type preservation with execute_lines passed!")
    end
  end

  describe "execute_string/2 - for loop with map type" do
    test "handles map type in for loop variable" do
      IO.puts("\n=== Testing map type with execute_string ===")
      IO.puts(@demo_script_map)
      IO.puts("=== Execution Results ===\n")

      # Execute script
      {:ok, state} = CLI.execute_string(@demo_script_map)

      IO.puts("\n=== Collected #{length(state.history)} execution records ===")

      # Print execution records
      Enum.each(state.history, fn record ->
        IO.puts("[#{get_node_type(record)}] fragment: #{String.trim(record.fragment)}")

        if record.stdout != [] do
          IO.puts("  stdout: #{inspect(record.stdout)}")
        end
      end)

      # Find inspect record
      inspect_records =
        Enum.filter(state.history, fn record ->
          record.stdout != [] and Enum.any?(record.stdout, &(&1 =~ "Type:"))
        end)

      assert length(inspect_records) >= 1, "Expected at least 1 inspect output"

      # Verify map type is preserved
      inspect_output = inspect_records |> List.first() |> Map.get(:stdout) |> Enum.join("")
      assert inspect_output =~ "Type: :map", "Should show map type"
      assert inspect_output =~ "CONFIG:", "Should show variable name"

      IO.puts("\n✅ Map type test passed!")
    end
  end

  describe "performance comparison" do
    test "both methods complete quickly without timeouts" do
      IO.puts("\n=== Performance Comparison ===")

      # Test execute_string
      start = System.monotonic_time(:millisecond)
      {:ok, state1} = CLI.execute_string(@demo_script_simple)
      duration1 = System.monotonic_time(:millisecond) - start
      IO.puts("execute_string: #{duration1}ms (#{length(state1.history)} records)")

      # Test execute_lines
      start = System.monotonic_time(:millisecond)
      {:ok, state2} = CLI.execute_lines(@demo_script_simple)
      duration2 = System.monotonic_time(:millisecond) - start
      IO.puts("execute_lines:  #{duration2}ms (#{length(state2.history)} records)")

      # Both should complete quickly (< 2 seconds for safety)
      assert duration1 < 2000, "execute_string took too long: #{duration1}ms"
      assert duration2 < 2000, "execute_lines took too long: #{duration2}ms"

      IO.puts("\n✅ Both methods complete quickly!")
    end
  end

  # Helper functions

  defp find_echo_records(history) do
    Enum.filter(history, fn record ->
      record.stdout != [] and
        record.stdout != [""]
    end)
  end

  defp get_node_type(%{execution_result: %{node_type: type}}), do: type
  defp get_node_type(_), do: "Unknown"
end
