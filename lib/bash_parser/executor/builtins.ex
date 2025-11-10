defmodule BashParser.Executor.Builtins do
  @moduledoc """
  Extensible builtin command system for the bash executor.

  Provides a registry of builtin commands that can be easily extended.
  Each builtin is a module that implements the execute/3 callback.

  ## Usage

      # Register a new builtin
      Builtins.register("mycommand", MyCommand)

      # Execute a builtin
      Builtins.execute("echo", ["hello"], context)

      # Check if a command is a builtin
      Builtins.builtin?("echo")  # => true
  """

  alias BashParser.Executor.Context

  @type builtin_fn :: (args :: [String.t()], context :: Context.t() -> Context.t())

  # Default builtins registry
  @default_builtins %{
    "echo" => __MODULE__.Echo,
    "export" => __MODULE__.Export,
    "return" => __MODULE__.Return,
    "exit" => __MODULE__.Exit,
    "cd" => __MODULE__.Cd,
    "pwd" => __MODULE__.Pwd,
    "test" => __MODULE__.Test,
    "[" => __MODULE__.Test,
    "true" => __MODULE__.True,
    "false" => __MODULE__.False
  }

  @doc """
  Execute a builtin command if it exists, otherwise execute as external command.
  """
  @spec execute(String.t(), [String.t()], Context.t()) :: Context.t()
  def execute(command, args, context) do
    builtins = get_builtins(context)

    case Map.get(builtins, command) do
      nil ->
        # Not a builtin, execute as external command
        execute_external(command, args, context)
      builtin_module ->
        # Execute the builtin
        builtin_module.execute(args, context)
    end
  end

  @doc """
  Check if a command is a registered builtin.
  """
  @spec builtin?(String.t(), Context.t()) :: boolean()
  def builtin?(command, context \\ %Context{mode: :simulate, env: %{}, exit_code: 0}) do
    builtins = get_builtins(context)
    Map.has_key?(builtins, command)
  end

  @doc """
  Register a new builtin command.
  """
  @spec register(Context.t(), String.t(), module()) :: Context.t()
  def register(context, name, module) do
    builtins = get_builtins(context)
    new_builtins = Map.put(builtins, name, module)
    Context.set_variable(context, "__BUILTINS__", new_builtins)
  end

  @doc """
  Get all registered builtins.
  """
  @spec list(Context.t()) :: [String.t()]
  def list(context) do
    get_builtins(context)
    |> Map.keys()
    |> Enum.sort()
  end

  # Private helpers

  defp get_builtins(%Context{env: env}) do
    case Map.get(env, "__BUILTINS__") do
      nil -> @default_builtins
      builtins when is_map(builtins) -> builtins
      _ -> @default_builtins
    end
  end

  defp execute_external(cmd, args, context) do
    case context.mode do
      :simulate ->
        output = "Simulated: #{cmd} #{Enum.join(args, " ")}"
        Context.add_output(context, output)
        |> Context.set_exit_code(0)

      :capture ->
        output = "Captured: #{cmd} #{Enum.join(args, " ")}"
        Context.add_output(context, output)
        |> Context.set_exit_code(0)

      :real ->
        # TODO: Actually execute the command using System.cmd/3
        output = "Would execute: #{cmd} #{Enum.join(args, " ")}"
        Context.add_output(context, output)
        |> Context.set_exit_code(0)
    end
  end

  # Builtin command implementations

  defmodule Echo do
    @moduledoc "Echo builtin - prints arguments"

    def execute(args, context) do
      output = Enum.join(args, " ")
      BashParser.Executor.Context.add_output(context, output)
      |> BashParser.Executor.Context.set_exit_code(0)
    end
  end

  defmodule Export do
    @moduledoc "Export builtin - sets environment variables"

    def execute(args, context) do
      Enum.reduce(args, context, fn arg, ctx ->
        case String.split(arg, "=", parts: 2) do
          [var, value] -> BashParser.Executor.Context.set_variable(ctx, var, value)
          _ -> ctx
        end
      end)
      |> BashParser.Executor.Context.set_exit_code(0)
    end
  end

  defmodule Return do
    @moduledoc "Return builtin - returns from function with exit code"

    def execute([code | _], context) do
      exit_code = String.to_integer(code)
      BashParser.Executor.Context.set_exit_code(context, exit_code)
    end

    def execute([], context) do
      BashParser.Executor.Context.set_exit_code(context, 0)
    end
  end

  defmodule Exit do
    @moduledoc "Exit builtin - exits with code"

    def execute([code_str | _], context) do
      code = String.to_integer(code_str)
      BashParser.Executor.Context.set_exit_code(context, code)
    end

    def execute([], context) do
      BashParser.Executor.Context.set_exit_code(context, 0)
    end
  end

  defmodule Cd do
    @moduledoc "Cd builtin - changes directory"

    def execute([dir | _], context) do
      BashParser.Executor.Context.set_variable(context, "PWD", dir)
      |> BashParser.Executor.Context.set_exit_code(0)
    end

    def execute([], context) do
      home = BashParser.Executor.Context.get_variable(context, "HOME", "/home/user")
      BashParser.Executor.Context.set_variable(context, "PWD", home)
      |> BashParser.Executor.Context.set_exit_code(0)
    end
  end

  defmodule Pwd do
    @moduledoc "Pwd builtin - prints working directory"

    def execute(_args, context) do
      pwd = BashParser.Executor.Context.get_variable(context, "PWD", "/")
      BashParser.Executor.Context.add_output(context, pwd)
      |> BashParser.Executor.Context.set_exit_code(0)
    end
  end

  defmodule Test do
    @moduledoc "Test builtin - evaluates conditions"

    def execute(args, context) do
      # Simplified test - just check if arguments exist
      exit_code = if length(args) > 0, do: 0, else: 1
      BashParser.Executor.Context.set_exit_code(context, exit_code)
    end
  end

  defmodule True do
    @moduledoc "True builtin - always succeeds"

    def execute(_args, context) do
      BashParser.Executor.Context.set_exit_code(context, 0)
    end
  end

  defmodule False do
    @moduledoc "False builtin - always fails"

    def execute(_args, context) do
      BashParser.Executor.Context.set_exit_code(context, 1)
    end
  end
end
