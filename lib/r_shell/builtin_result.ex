defmodule RShell.BuiltinResult do
  @moduledoc """
  Wraps the result of a builtin command execution.

  Builtins return POSIX-style tuples: {context, stdout, stderr, exit_code}
  This struct wraps that result for easier transport through the execution pipeline.

  ## Example

      # Builtin returns POSIX tuple
      {context, stdout, stderr, 1} = Builtins.execute("false", [], "", context)

      # Immediately wrap in struct
      result = BuiltinResult.new(context, stdout, stderr, 1)

      # Access fields
      result.exit_code  # => 1
      result.context    # => %{...}
  """

  defstruct [:context, :stdout, :stderr, :exit_code]

  @type t :: %__MODULE__{
    context: map(),
    stdout: Enumerable.t(),
    stderr: Enumerable.t(),
    exit_code: integer()
  }

  @doc """
  Create a BuiltinResult from a POSIX-style tuple.

  ## Examples

      iex> {ctx, out, err, code} = Builtins.execute("true", [], "", %{})
      iex> result = BuiltinResult.from_tuple({ctx, out, err, code})
      iex> result.exit_code
      0
  """
  def from_tuple({context, stdout, stderr, exit_code}) do
    %__MODULE__{
      context: context,
      stdout: stdout,
      stderr: stderr,
      exit_code: exit_code
    }
  end

  @doc """
  Create a BuiltinResult from individual values.
  """
  def new(context, stdout, stderr, exit_code) do
    %__MODULE__{
      context: context,
      stdout: stdout,
      stderr: stderr,
      exit_code: exit_code
    }
  end

  @doc """
  Materialize streams and update context with output and exit code.

  This is the key function that ensures exit codes propagate correctly.
  """
  def materialize_and_update(%__MODULE__{} = result) do
    stdout_list = materialize_output(result.stdout)
    stderr_list = materialize_output(result.stderr)

    # CRITICAL: Update context with BOTH output AND exit code from result
    new_context = %{
      result.context
      | exit_code: result.exit_code,
        last_output: %{stdout: stdout_list, stderr: stderr_list}
    }

    new_context
  end

  # Materialize output - convert Stream to list of native terms
  defp materialize_output(stream) when is_function(stream) do
    stream |> Enum.to_list()
  end

  defp materialize_output(string) when is_binary(string) do
    if string == "", do: [], else: [string]
  end

  defp materialize_output([]), do: []
  defp materialize_output(list) when is_list(list), do: list
  defp materialize_output(term), do: [term]
end
