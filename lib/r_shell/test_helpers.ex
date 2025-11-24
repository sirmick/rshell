defmodule RShell.TestHelpers do
  @moduledoc """
  Helper functions for working with stream-based output in tests.

  These helpers make it easy to materialize and assert on output streams
  without needing to manually call Enum.to_list/1 everywhere.

  ## Usage in Tests

      import RShell.TestHelpers

      output = materialize_output(stack)
      assert output.stdout == ["hello\\n"]

      # Or use assertion helpers
      assert_stdout(stack, ["hello\\n"])
      assert_stderr(result, "")
  """

  alias RShell.Runtime.{FrameStack, Frame}
  alias RShell.BuiltinResult

  @doc """
  Materialize output from a FrameStack, Frame, or BuiltinResult.

  Returns a map with materialized stdout and stderr lists.

  ## Examples

      iex> output = TestHelpers.materialize_output(stack)
      iex> output.stdout
      ["line1\\n", "line2\\n"]

      iex> output = TestHelpers.materialize_output(result)
      iex> output.stderr
      []
  """
  def materialize_output(%FrameStack{} = stack) do
    output = FrameStack.get_output(stack)
    %{
      stdout: Enum.to_list(output.stdout),
      stderr: Enum.to_list(output.stderr)
    }
  end

  def materialize_output(%Frame{} = frame) do
    %{
      stdout: Enum.to_list(frame.accumulated.stdout),
      stderr: Enum.to_list(frame.accumulated.stderr)
    }
  end

  def materialize_output(%BuiltinResult{} = result) do
    {_ctx, stdout, stderr} = BuiltinResult.materialize_and_update(result)
    %{stdout: stdout, stderr: stderr}
  end

  # Handle raw output maps (already materialized or from get_output)
  def materialize_output(%{stdout: stdout, stderr: stderr} = _output) do
    %{
      stdout: to_list(stdout),
      stderr: to_list(stderr)
    }
  end

  @doc """
  Get stdout as a single joined string.

  ## Examples

      iex> TestHelpers.stdout_string(stack)
      "line1\\nline2\\n"
  """
  def stdout_string(output_source) do
    materialize_output(output_source).stdout |> Enum.join("")
  end

  @doc """
  Get stderr as a single joined string.
  """
  def stderr_string(output_source) do
    materialize_output(output_source).stderr |> Enum.join("")
  end

  @doc """
  Get just the stdout list (convenience wrapper).
  """
  def stdout_list(output_source) do
    materialize_output(output_source).stdout
  end

  @doc """
  Get just the stderr list (convenience wrapper).
  """
  def stderr_list(output_source) do
    materialize_output(output_source).stderr
  end

  @doc """
  Assert that stdout matches expected output.

  ## Examples

      assert_stdout(stack, ["hello\\n", "world\\n"])
      assert_stdout(result, "hello\\nworld\\n")
  """
  def assert_stdout(output_source, expected) when is_list(expected) do
    actual = stdout_list(output_source)
    ExUnit.Assertions.assert actual == expected,
      "Expected stdout to be #{inspect(expected)}, got #{inspect(actual)}"
  end

  def assert_stdout(output_source, expected) when is_binary(expected) do
    actual = stdout_string(output_source)
    ExUnit.Assertions.assert actual == expected,
      "Expected stdout to be #{inspect(expected)}, got #{inspect(actual)}"
  end

  @doc """
  Assert that stderr matches expected output.
  """
  def assert_stderr(output_source, expected) when is_list(expected) do
    actual = stderr_list(output_source)
    ExUnit.Assertions.assert actual == expected,
      "Expected stderr to be #{inspect(expected)}, got #{inspect(actual)}"
  end

  def assert_stderr(output_source, expected) when is_binary(expected) do
    actual = stderr_string(output_source)
    ExUnit.Assertions.assert actual == expected,
      "Expected stderr to be #{inspect(expected)}, got #{inspect(actual)}"
  end

  # Private helpers

  defp to_list(stream) when is_function(stream), do: Enum.to_list(stream)
  defp to_list(%Stream{} = stream), do: Enum.to_list(stream)
  defp to_list(list) when is_list(list), do: list
  defp to_list(str) when is_binary(str), do: if str == "", do: [], else: [str]
  defp to_list(term), do: [term]
end
