defmodule BashParser.Executor.Context do
  @moduledoc """
  Execution context for Bash script execution.

  Maintains:
  - Environment variables
  - Function definitions
  - Exit codes
  - Output/error streams
  - Execution mode
  - Variable scopes (for subshells)
  """

  @enforce_keys [:mode, :env, :exit_code]
  defstruct [
    :mode,           # :simulate | :capture | :real
    :env,            # Current environment variables
    :functions,      # Function definitions
    :exit_code,      # Last exit code
    :output,         # Output buffer
    :errors,         # Error buffer
    :strict,         # Stop on first error
    :scopes          # Stack of variable scopes
  ]

  @type t :: %__MODULE__{
    mode: :simulate | :capture | :real,
    env: %{String.t() => String.t()},
    functions: %{String.t() => any()},
    exit_code: non_neg_integer(),
    output: [String.t()],
    errors: [String.t()],
    strict: boolean(),
    scopes: [%{String.t() => String.t()}]
  }

  @doc """
  Create a new execution context.

  Options:
  - `:mode` - Execution mode (:simulate, :capture, :real)
  - `:env` - Initial environment variables
  - `:strict` - Stop on first error
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    mode = Keyword.get(opts, :mode, :simulate)
    env = Keyword.get(opts, :env, %{})
    strict = Keyword.get(opts, :strict, false)

    %__MODULE__{
      mode: mode,
      env: env,
      functions: %{},
      exit_code: 0,
      output: [],
      errors: [],
      strict: strict,
      scopes: []
    }
  end

  @doc """
  Set a variable in the current environment.
  """
  @spec set_variable(t(), String.t(), String.t()) :: t()
  def set_variable(%__MODULE__{} = context, name, value) when is_binary(name) do
    %{context | env: Map.put(context.env, name, to_string(value))}
  end

  @doc """
  Get a variable from the environment.
  Returns the default value if not found.
  """
  @spec get_variable(t(), String.t(), String.t()) :: String.t()
  def get_variable(%__MODULE__{} = context, name, default \\ "") do
    Map.get(context.env, name, default)
  end

  @doc """
  Check if a variable exists.
  """
  @spec has_variable?(t(), String.t()) :: boolean()
  def has_variable?(%__MODULE__{} = context, name) do
    Map.has_key?(context.env, name)
  end

  @doc """
  Delete a variable from the environment.
  """
  @spec unset_variable(t(), String.t()) :: t()
  def unset_variable(%__MODULE__{} = context, name) do
    %{context | env: Map.delete(context.env, name)}
  end

  @doc """
  Define a function.
  """
  @spec define_function(t(), String.t(), any()) :: t()
  def define_function(%__MODULE__{} = context, name, body) do
    %{context | functions: Map.put(context.functions, name, body)}
  end

  @doc """
  Get a function definition.
  """
  @spec get_function(t(), String.t()) :: any() | nil
  def get_function(%__MODULE__{} = context, name) do
    Map.get(context.functions, name)
  end

  @doc """
  Check if a function is defined.
  """
  @spec has_function?(t(), String.t()) :: boolean()
  def has_function?(%__MODULE__{} = context, name) do
    Map.has_key?(context.functions, name)
  end

  @doc """
  Set the exit code.
  """
  @spec set_exit_code(t(), non_neg_integer()) :: t()
  def set_exit_code(%__MODULE__{} = context, code) when is_integer(code) do
    %{context | exit_code: code}
  end

  @doc """
  Add output to the output buffer.
  """
  @spec add_output(t(), String.t()) :: t()
  def add_output(%__MODULE__{} = context, output) when is_binary(output) do
    %{context | output: [output | context.output]}
  end

  @doc """
  Add an error to the error buffer.
  """
  @spec add_error(t(), String.t()) :: t()
  def add_error(%__MODULE__{} = context, error) when is_binary(error) do
    %{context | errors: [error | context.errors], exit_code: 1}
  end

  @doc """
  Push a new variable scope (for subshells).
  """
  @spec push_scope(t()) :: t()
  def push_scope(%__MODULE__{} = context) do
    %{context | scopes: [context.env | context.scopes]}
  end

  @doc """
  Pop the current variable scope and restore the previous one.
  """
  @spec pop_scope(t()) :: t()
  def pop_scope(%__MODULE__{scopes: [parent_env | rest_scopes]} = context) do
    %{context | env: parent_env, scopes: rest_scopes}
  end

  def pop_scope(%__MODULE__{scopes: []} = context) do
    # No scope to pop, return unchanged
    context
  end

  @doc """
  Merge environment variables from another context.
  """
  @spec merge_env(t(), t()) :: t()
  def merge_env(%__MODULE__{} = context, %__MODULE__{} = other) do
    %{context | env: Map.merge(context.env, other.env)}
  end

  @doc """
  Get all environment variables as a map.
  """
  @spec get_all_variables(t()) :: %{String.t() => String.t()}
  def get_all_variables(%__MODULE__{} = context) do
    context.env
  end

  @doc """
  Get all function definitions.
  """
  @spec get_all_functions(t()) :: %{String.t() => any()}
  def get_all_functions(%__MODULE__{} = context) do
    context.functions
  end

  @doc """
  Clear all output.
  """
  @spec clear_output(t()) :: t()
  def clear_output(%__MODULE__{} = context) do
    %{context | output: []}
  end

  @doc """
  Clear all errors.
  """
  @spec clear_errors(t()) :: t()
  def clear_errors(%__MODULE__{} = context) do
    %{context | errors: []}
  end

  @doc """
  Reset the exit code to 0.
  """
  @spec reset_exit_code(t()) :: t()
  def reset_exit_code(%__MODULE__{} = context) do
    %{context | exit_code: 0}
  end

  @doc """
  Create a snapshot of the current context.
  """
  @spec snapshot(t()) :: map()
  def snapshot(%__MODULE__{} = context) do
    %{
      mode: context.mode,
      variables: context.env,
      functions: Map.keys(context.functions),
      exit_code: context.exit_code,
      output: Enum.reverse(context.output),
      errors: Enum.reverse(context.errors)
    }
  end
end
