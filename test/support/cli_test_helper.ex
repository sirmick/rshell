defmodule RShell.TestSupport.CLIHelper do
  @moduledoc """
  Test helper for CLI-based tests with silent success and verbose failure.

  Pattern inspired by demo_variable_*.exs tests but with better output control.
  All operations include timeout protection to prevent hanging tests.
  """

  import ExUnit.Assertions

  @default_timeout 5000

  @doc """
  Execute a script via CLI and assert it succeeds.

  Silent on success, verbose on failure with full diagnostics.
  Includes timeout protection.

  ## Options
  - `:mode` - `:execute_string` (default) or `:execute_lines`
  - `:timeout` - Timeout in milliseconds (default: 5000)
  """
  def assert_cli_success(script, opts \\ []) do
    # Auto-detect mode: use execute_lines for multi-line scripts
    default_mode = if String.contains?(script, "\n"), do: :execute_lines, else: :execute_string
    mode = Keyword.get(opts, :mode, default_mode)
    timeout = Keyword.get(opts, :timeout, @default_timeout)

    task =
      Task.async(fn ->
        case mode do
          :execute_string -> RShell.CLI.execute_string(script)
          :execute_lines -> RShell.CLI.execute_lines(script)
        end
      end)

    case Task.yield(task, timeout) || Task.shutdown(task) do
      {:ok, {:ok, state}} ->
        # Success - return state silently
        state

      {:ok, {:error, reason}} ->
        # Execution error - verbose output
        flunk(format_execution_error(script, reason, mode))

      nil ->
        # Timeout
        flunk(format_timeout_error(script, timeout, mode))

      {:exit, reason} ->
        # Process crashed
        flunk(format_crash_error(script, reason, mode))
    end
  end

  @doc """
  Execute script and assert specific output/conditions.

  Silent on success, verbose on failure.

  ## Assertions
  - `{:stdout_contains, pattern}` - Assert stdout contains pattern
  - `{:exit_code, code}` - Assert exit code matches
  - `{:record_count, count}` - Assert number of execution records
  - `{:variable, name, value}` - Assert environment variable value
  - `{:no_timeout, true}` - Just verify completion without assertions

  ## Options
  - `:mode` - `:execute_string` (default) or `:execute_lines`
  - `:timeout` - Timeout in milliseconds (default: 5000)
  """
  def assert_cli_output(script, assertions, opts \\ []) do
    state = assert_cli_success(script, opts)

    # Run assertions
    Enum.each(assertions, fn
      {:stdout_contains, pattern} ->
        assert_output_contains(state, pattern, script)

      {:exit_code, code} ->
        assert_exit_code(state, code, script)

      {:record_count, count} ->
        assert_record_count(state, count, script)

      {:variable, name, value} ->
        assert_variable(state, name, value, script)

      {:no_timeout, true} ->
        # Just verify we got a state (no timeout)
        :ok
    end)

    state
  end

  # Private helpers with verbose failure messages

  defp assert_output_contains(state, pattern, script) do
    outputs = extract_all_stdout(state.history)

    if !Enum.any?(outputs, &(&1 =~ pattern)) do
      flunk("""
      Expected output to contain: #{inspect(pattern)}

      Script:
      #{script}

      Actual outputs:
      #{format_outputs(outputs)}

      Full history:
      #{format_history(state.history)}
      """)
    end
  end

  defp assert_exit_code(state, expected_code, script) do
    last_record = List.last(state.history)
    actual_code = last_record.exit_code

    if actual_code != expected_code do
      flunk("""
      Expected exit code: #{expected_code}
      Actual exit code: #{actual_code}

      Script:
      #{script}

      Last record:
      #{format_record(last_record)}
      """)
    end
  end

  defp assert_record_count(state, expected_count, script) do
    actual_count = length(state.history)

    if actual_count != expected_count do
      flunk("""
      Expected #{expected_count} execution records
      Got #{actual_count} execution records

      Script:
      #{script}

      Records:
      #{format_history(state.history)}
      """)
    end
  end

  defp assert_variable(state, name, expected_value, script) do
    # Get runtime context from last record
    last_record = List.last(state.history)
    context = get_context_from_record(last_record)
    actual_value = get_in(context, [:env, name])

    if actual_value != expected_value do
      flunk("""
      Expected variable #{name} = #{inspect(expected_value)}
      Actual value: #{inspect(actual_value)}

      Script:
      #{script}

      Environment:
      #{format_env(context[:env] || %{})}
      """)
    end
  end

  # Formatting helpers

  defp format_execution_error(script, reason, mode) do
    """
    CLI execution failed (#{mode})

    Script:
    #{script}

    Error: #{inspect(reason, pretty: true)}
    """
  end

  defp format_timeout_error(script, timeout, mode) do
    """
    CLI execution TIMEOUT (#{mode})

    Script:
    #{script}

    Timeout: #{timeout}ms

    This usually indicates:
    - Infinite loop in control structure
    - Waiting for input that never arrives
    - Deadlock in parser/runtime communication
    """
  end

  defp format_crash_error(script, reason, mode) do
    """
    CLI execution CRASHED (#{mode})

    Script:
    #{script}

    Exit reason: #{inspect(reason, pretty: true)}
    """
  end

  defp format_outputs(outputs) do
    outputs
    |> Enum.with_index(1)
    |> Enum.map(fn {output, i} -> "  #{i}. #{inspect(output)}" end)
    |> Enum.join("\n")
  end

  defp format_history(history) do
    history
    |> Enum.with_index(1)
    |> Enum.map(fn {record, i} ->
      """
        Record #{i}:
          Type: #{get_node_type(record)}
          Fragment: #{String.trim(record.fragment)}
          Exit Code: #{record.exit_code}
          Stdout: #{inspect(record.stdout)}
          Parse Time: #{record.parse_metrics.duration_us}μs
          Exec Time: #{record.exec_metrics.duration_us}μs
      """
    end)
    |> Enum.join("\n")
  end

  defp format_record(record) do
    """
      Type: #{get_node_type(record)}
      Fragment: #{String.trim(record.fragment)}
      Exit Code: #{record.exit_code}
      Stdout: #{inspect(record.stdout)}
      Stderr: #{inspect(record.stderr)}
      Context: #{format_context(get_context_from_record(record))}
    """
  end

  defp format_context(nil), do: "nil"

  defp format_context(context) do
    """
      CWD: #{context[:cwd]}
      Exit Code: #{context[:exit_code]}
      Env Vars: #{map_size(context[:env] || %{})}
    """
  end

  defp format_env(env) when is_map(env) do
    env
    |> Enum.map(fn {k, v} -> "  #{k} = #{inspect(v)}" end)
    |> Enum.join("\n")
  end

  defp format_env(_), do: "  (not a map)"

  defp extract_all_stdout(history) do
    Enum.flat_map(history, fn record -> record.stdout end)
  end

  defp get_node_type(%{execution_result: %{node_type: type}}), do: type
  defp get_node_type(_), do: "Unknown"

  defp get_context_from_record(%{context: context}), do: context
  defp get_context_from_record(_), do: nil
end
