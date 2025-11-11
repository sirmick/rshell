defmodule RShell.Builtins do
  @moduledoc """
  Built-in shell commands implemented in Elixir.

  Each builtin follows the unified signature:
  ```
  shell_*(args, stdin, context) -> {new_context, stdout, stderr, exit_code}
  ```

  ## Parameters
  - `args`: List of string arguments (already expanded/quoted)
  - `stdin`: Input data - can be String, Stream, Enumerable, or IO.device
  - `context`: Current shell context (env vars, cwd, etc.)

  ## Return Value
  A tuple with:
  - `new_context`: Updated context (unchanged for pure builtins)
  - `stdout`: Output data (String, Stream, or Enumerable)
  - `stderr`: Error output (String)
  - `exit_code`: Integer exit code (0 for success)

  Builtins are discovered via reflection using `function_exported?/3`.
  """

  @doc """
  Execute a builtin command by name.

  Uses reflection to invoke the appropriate `shell_*` function.

  ## Examples

      iex> RShell.Builtins.execute("echo", ["hello"], "", %{})
      {%{}, "hello\\n", "", 0}

      iex> RShell.Builtins.execute("unknown", [], "", %{})
      {:error, :not_a_builtin}
  """
  def execute(name, args, stdin, context) do
    function_name = String.to_atom("shell_#{name}")

    if function_exported?(__MODULE__, function_name, 3) do
      apply(__MODULE__, function_name, [args, stdin, context])
    else
      {:error, :not_a_builtin}
    end
  end

  @doc """
  Check if a command name is a builtin.

  ## Examples

      iex> RShell.Builtins.is_builtin?("echo")
      true

      iex> RShell.Builtins.is_builtin?("ls")
      false
  """
  def is_builtin?(name) do
    function_name = String.to_atom("shell_#{name}")
    function_exported?(__MODULE__, function_name, 3)
  end

  @doc """
  Echo builtin - writes arguments to stdout.

  ## Flags
  - `-n`: Do not output trailing newline
  - `-e`: Enable interpretation of backslash escapes
  - `-E`: Disable interpretation of backslash escapes (default)

  ## Examples

      iex> RShell.Builtins.shell_echo([], "", %{})
      {%{}, "\\n", "", 0}

      iex> RShell.Builtins.shell_echo(["hello", "world"], "", %{})
      {%{}, "hello world\\n", "", 0}

      iex> RShell.Builtins.shell_echo(["-n", "hello"], "", %{})
      {%{}, "hello", "", 0}

      iex> RShell.Builtins.shell_echo(["-e", "hello\\\\nworld"], "", %{})
      {%{}, "hello\\nworld\\n", "", 0}
  """
  def shell_echo(args, _stdin, context) do
    {flags, text_args} = parse_echo_flags(args)

    output =
      text_args
      |> Enum.join(" ")
      |> then(fn text ->
        if flags.interpret_escapes do
          process_escapes(text)
        else
          text
        end
      end)
      |> then(fn text ->
        if flags.no_newline do
          text
        else
          text <> "\n"
        end
      end)

    {context, output, "", 0}
  end

  # Parse echo flags and return {flags_map, remaining_args}
  defp parse_echo_flags(args) do
    parse_echo_flags(args, %{no_newline: false, interpret_escapes: false})
  end

  defp parse_echo_flags([], flags), do: {flags, []}

  defp parse_echo_flags([arg | rest], flags) do
    case arg do
      "-n" ->
        parse_echo_flags(rest, %{flags | no_newline: true})

      "-e" ->
        parse_echo_flags(rest, %{flags | interpret_escapes: true})

      "-E" ->
        parse_echo_flags(rest, %{flags | interpret_escapes: false})

      # Stop parsing flags when we hit a non-flag argument
      _ ->
        {flags, [arg | rest]}
    end
  end

  # Process backslash escape sequences
  defp process_escapes(text) do
    text
    |> String.replace("\\\\", <<0>>)
    |> String.replace("\\n", "\n")
    |> String.replace("\\t", "\t")
    |> String.replace("\\r", "\r")
    |> String.replace("\\a", "\a")
    |> String.replace("\\b", "\b")
    |> String.replace("\\e", <<27>>)
    |> String.replace("\\f", "\f")
    |> String.replace("\\v", "\v")
    |> String.replace(<<0>>, "\\")
  end
end