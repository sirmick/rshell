defmodule DemoVariableWhileTest do
  use ExUnit.Case, async: true

  alias RShell.CLI

  # Demo script for while loop with counter
  @demo_script_simple """
  env COUNT=0
  while test $COUNT -lt 3; do
    echo "Count is: $COUNT"
    env COUNT=$((COUNT + 1))
  done
  echo "Final count: $COUNT"
  """

  # Demo script with native type preservation through while loop
  @demo_script_types """
  env ITEMS='["alpha","beta","gamma"]'
  env INDEX=0
  while test $INDEX -lt 3; do
    inspect INDEX
    echo "Processing index $INDEX"
    env INDEX=$((INDEX + 1))
  done
  inspect ITEMS
  """

  # Demo script with map type in while loop
  @demo_script_map """
  env CONFIG='{"retries":3,"timeout":1000}'
  env RETRY=0
  inspect CONFIG
  while test $RETRY -lt 2; do
    echo "Retry attempt $RETRY"
    env RETRY=$((RETRY + 1))
  done
  echo "Config still available"
  inspect CONFIG
  """

  describe "execute_string/2 - while loop with counter" do
    test "executes loop while condition is true" do
      IO.puts("\n=== Testing while loop with execute_string ===")
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

      # Should have 3 loop iterations + 1 final count = 4 echo outputs
      assert length(echo_records) >= 4,
             "Expected at least 4 echo outputs, got #{length(echo_records)}"

      # Check loop iterations
      loop_outputs =
        Enum.filter(echo_records, fn record ->
          Enum.any?(record.stdout, &(&1 =~ "Count is:"))
        end)

      assert length(loop_outputs) == 3, "Expected 3 loop iterations, got #{length(loop_outputs)}"

      # Check final count output
      final_outputs =
        Enum.filter(echo_records, fn record ->
          Enum.any?(record.stdout, &(&1 =~ "Final count: 3"))
        end)

      assert length(final_outputs) == 1, "Expected 1 final count output"

      IO.puts("\n✅ execute_string while loop test passed!")
    end
  end

  describe "execute_lines/2 - while loop with InputBuffer" do
    test "executes loop while condition is true (line-by-line)" do
      IO.puts("\n=== Testing while loop with execute_lines (line-by-line) ===")
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

      # Verify InputBuffer accumulated the while loop correctly
      # Should have execution records for:
      # 1. env COUNT=0
      # 2. while...done (accumulated until 'done')
      # 3. echo "Final count..."
      assert length(state.history) >= 2, "Expected at least 2 execution records with InputBuffer"

      # Check that while loop was accumulated
      while_record =
        Enum.find(state.history, fn record ->
          record.fragment =~ "while test" and record.fragment =~ "done"
        end)

      assert while_record != nil, "While loop should be in a single execution record"

      # Verify echo outputs
      echo_records = find_echo_records(state.history)
      assert length(echo_records) >= 4, "Expected at least 4 echo outputs"

      IO.puts(
        "\n✅ execute_lines while loop test passed! InputBuffer correctly accumulated while loop."
      )
    end
  end

  describe "execute_string/2 - while loop with native type preservation" do
    test "preserves integer type through while loop iterations" do
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

      # Should have 3 inspect INDEX outputs + 1 final ITEMS inspect = 4 total
      assert length(inspect_records) >= 4,
             "Expected at least 4 inspect outputs, got #{length(inspect_records)}"

      # Verify each inspect shows the variable type
      index_inspects =
        Enum.filter(inspect_records, fn record ->
          stdout_str = Enum.join(record.stdout, "")
          stdout_str =~ "INDEX:"
        end)

      assert length(index_inspects) == 3, "Should have 3 INDEX inspects"

      # Check that integer type is preserved
      Enum.each(index_inspects, fn record ->
        stdout_str = Enum.join(record.stdout, "")
        assert stdout_str =~ "Type: :integer", "INDEX should be integer type"
      end)

      IO.puts("\n✅ Type preservation test passed!")
    end
  end

  describe "execute_lines/2 - while loop with native type preservation" do
    test "preserves types through while loop iterations (line-by-line)" do
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

      # Verify the while loop was accumulated as a single fragment
      while_record =
        Enum.find(state.history, fn record ->
          record.fragment =~ "while test" and record.fragment =~ "done"
        end)

      assert while_record != nil, "While loop should be accumulated by InputBuffer"

      # Find inspect outputs
      inspect_records =
        Enum.filter(state.history, fn record ->
          record.stdout != [] and Enum.any?(record.stdout, &(&1 =~ "Type:"))
        end)

      assert length(inspect_records) >= 4, "Expected at least 4 inspect outputs"

      IO.puts("\n✅ Type preservation with execute_lines passed!")
    end
  end

  describe "execute_string/2 - while loop with map type" do
    test "handles map type in while loop context" do
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

      # Find inspect records
      inspect_records =
        Enum.filter(state.history, fn record ->
          record.stdout != [] and Enum.any?(record.stdout, &(&1 =~ "Type:"))
        end)

      assert length(inspect_records) >= 2, "Expected at least 2 inspect outputs"

      # Verify map type is preserved before and after loop
      config_inspects =
        Enum.filter(inspect_records, fn record ->
          stdout_str = Enum.join(record.stdout, "")
          stdout_str =~ "CONFIG:"
        end)

      assert length(config_inspects) == 2, "Should have 2 CONFIG inspects (before and after)"

      # Both should show map type
      Enum.each(config_inspects, fn record ->
        stdout_str = Enum.join(record.stdout, "")
        assert stdout_str =~ "Type: :map", "CONFIG should be map type"
      end)

      IO.puts("\n✅ Map type test passed!")
    end
  end

  describe "execute_lines/2 - while loop with map type" do
    test "handles map type in while loop context (line-by-line)" do
      IO.puts("\n=== Testing map type with execute_lines ===")
      IO.puts(@demo_script_map)
      IO.puts("=== Execution Results ===\n")

      # Execute line-by-line
      {:ok, state} = CLI.execute_lines(@demo_script_map)

      IO.puts("\n=== Collected #{length(state.history)} execution records ===")

      # Print execution records
      Enum.each(state.history, fn record ->
        IO.puts("[#{get_node_type(record)}] fragment: #{String.trim(record.fragment)}")

        if record.stdout != [] do
          IO.puts("  stdout: #{inspect(record.stdout)}")
        end
      end)

      # Verify the while loop was accumulated
      while_record =
        Enum.find(state.history, fn record ->
          record.fragment =~ "while test" and record.fragment =~ "done"
        end)

      assert while_record != nil, "While loop should be accumulated by InputBuffer"

      # Find inspect records
      inspect_records =
        Enum.filter(state.history, fn record ->
          record.stdout != [] and Enum.any?(record.stdout, &(&1 =~ "Type:"))
        end)

      assert length(inspect_records) >= 2, "Expected at least 2 inspect outputs"

      IO.puts("\n✅ Map type with execute_lines passed!")
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
