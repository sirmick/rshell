defmodule RShell.TestHelpers.ExecutionHelper do
  @moduledoc """
  Helper functions for testing with the simplified :execution_result event model.

  Provides synchronous wrappers around async execution to make tests easier.
  """

  @doc """
  Convert native term list to string for comparison.

  Handles the new format where stdout/stderr are lists of native terms.
  """
  def output_to_string([]), do: ""
  def output_to_string(output) when is_list(output) do
    output
    |> Enum.map(&term_to_string/1)
    |> Enum.join("")
  end
  def output_to_string(output) when is_binary(output), do: output
  def output_to_string(output), do: term_to_string(output)

  defp term_to_string(term) when is_binary(term), do: term
  defp term_to_string(term) when is_map(term), do: Jason.encode!(term)
  defp term_to_string(term) when is_list(term) do
    if Enum.all?(term, &(is_integer(&1) and &1 >= 32 and &1 <= 126)) do
      List.to_string(term)
    else
      Jason.encode!(term)
    end
  end
  defp term_to_string(term) when is_integer(term), do: Integer.to_string(term)
  defp term_to_string(term) when is_float(term), do: Float.to_string(term)
  defp term_to_string(true), do: "true"
  defp term_to_string(false), do: "false"
  defp term_to_string(nil), do: ""
  defp term_to_string(atom) when is_atom(atom), do: Atom.to_string(atom)

  @doc """
  Execute a script fragment and wait for all execution results.

  Returns a list of execution results in order.

  ## Example

      results = execute_and_collect(parser, "echo hello\\necho world")
      assert length(results) == 2
      assert hd(results).stdout =~ "hello"
  """
  def execute_and_collect(parser, script, timeout \\ 5000) do
    # Parse the script
    {:ok, _ast} = RShell.IncrementalParser.append_fragment(parser, script)

    # Collect all execution results
    collect_results([], timeout)
  end

  @doc """
  Execute script and return the last execution result.

  Useful when you only care about the final result.

  ## Example

      result = execute_and_get_last(parser, "echo test")
      assert result.status == :success
      assert result.stdout =~ "test"
  """
  def execute_and_get_last(parser, script, timeout \\ 5000) do
    results = execute_and_collect(parser, script, timeout)
    List.last(results)
  end

  @doc """
  Assert that execution succeeded with expected stdout.

  ## Example

      result = execute_and_get_last(parser, "echo hello")
      assert_execution_success(result, stdout: "hello\\n")
  """
  def assert_execution_success(result, opts \\ []) do
    import ExUnit.Assertions

    assert result.status == :success, "Expected success but got #{result.status}"

    if stdout = opts[:stdout] do
      # Convert native term list to string for comparison
      stdout_str = output_to_string(result.stdout)
      assert stdout_str == stdout,
        "Expected stdout #{inspect(stdout)} but got #{inspect(stdout_str)}"
    end

    if stderr = opts[:stderr] do
      # Convert native term list to string for comparison
      stderr_str = output_to_string(result.stderr)
      assert stderr_str == stderr,
        "Expected stderr #{inspect(stderr)} but got #{inspect(stderr_str)}"
    end

    if exit_code = opts[:exit_code] do
      assert result.exit_code == exit_code,
        "Expected exit code #{exit_code} but got #{result.exit_code}"
    end

    result
  end

  @doc """
  Assert that execution failed with expected error.

  ## Example

      result = execute_and_get_last(parser, "invalid_command")
      assert_execution_error(result, reason: "NotImplementedError")
  """
  def assert_execution_error(result, opts \\ []) do
    import ExUnit.Assertions

    assert result.status == :error, "Expected error but got #{result.status}"

    if reason = opts[:reason] do
      assert result.reason == reason,
        "Expected reason #{reason} but got #{result.reason}"
    end

    if error = opts[:error] do
      assert result.error =~ error,
        "Expected error to contain #{inspect(error)} but got #{inspect(result.error)}"
    end

    result
  end

  # Private helpers

  defp collect_results(acc, timeout) do
    receive do
      {:execution_result, result} ->
        # Collect this result and continue
        collect_results([result | acc], timeout)
    after
      timeout ->
        # Return results in chronological order
        Enum.reverse(acc)
    end
  end
end
