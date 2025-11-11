defmodule RShell.Builtins do
  @moduledoc """
  Built-in shell commands implemented in Elixir.

  Each builtin follows the unified signature:
  ```
  shell_*(argv, stdin, context) -> {new_context, stdout, stderr, exit_code}
  ```

  ## Parameters
  - `argv`: POSIX-style argument vector (list of strings)
  - `stdin`: Input data - can be String, Stream, Enumerable, or IO.device
  - `context`: Current shell context (env vars, cwd, etc.)

  ## Return Value
  A tuple with:
  - `new_context`: Updated context (unchanged for pure builtins)
  - `stdout`: Output data (String, Stream, or Enumerable)
  - `stderr`: Error output (String)
  - `exit_code`: Integer exit code (0 for success)

  Builtins are discovered via reflection using `function_exported?/3`.
  Options are automatically parsed from docstrings at compile time.
  """

  use RShell.Builtins.Helpers

  @doc """
  Execute a builtin command by name.

  Uses reflection to invoke the appropriate `shell_*` function.

  ## Examples

      iex> RShell.Builtins.execute("echo", ["hello"], "", %{})
      {%{}, "hello\\n", "", 0}

      iex> RShell.Builtins.execute("unknown", [], "", %{})
      {:error, :not_a_builtin}
  """
  def execute(name, argv, stdin, context) do
    function_name = String.to_atom("shell_#{name}")

    if function_exported?(__MODULE__, function_name, 3) do
      apply(__MODULE__, function_name, [argv, stdin, context])
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
  echo - write arguments to standard output

  Write the STRING(s) to standard output separated by spaces and followed by a newline.

  Usage: echo [OPTION]... [STRING]...

  Options:
    -n, --no-newline
        type: boolean
        default: false
        desc: Do not output the trailing newline

    -e, --enable-escapes
        type: boolean
        default: false
        desc: Enable interpretation of backslash escapes

    -E, --disable-escapes
        type: boolean
        default: false
        desc: Disable interpretation of backslash escapes (default behavior)

  When -e is enabled, the following escape sequences are recognized:
    \\n  newline          \\t  horizontal tab    \\r  carriage return
    \\\\  backslash        \\a  alert (bell)      \\b  backspace
    \\e  escape character \\f  form feed         \\v  vertical tab

  ## Examples
      echo hello world
      echo -n test
      echo -e "line1\\nline2"
  """
  def shell_echo(argv, _stdin, context) do
    # Parse options manually to handle -e/-E mutual exclusion
    {opts, args} = parse_echo_options(argv)

    output =
      args
      |> Enum.join(" ")
      |> then(fn text ->
        if opts.enable_escapes do
          process_escapes(text)
        else
          text
        end
      end)
      |> then(fn text ->
        if opts.no_newline do
          text
        else
          text <> "\n"
        end
      end)

    {context, output, "", 0}
  end

  # Custom parser for echo that handles -e/-E mutual exclusion
  defp parse_echo_options(argv) do
    parse_echo_options(argv, %{no_newline: false, enable_escapes: false}, [])
  end

  defp parse_echo_options([], opts, args), do: {opts, Enum.reverse(args)}

  defp parse_echo_options([arg | rest], opts, args) do
    case arg do
      "-n" ->
        parse_echo_options(rest, %{opts | no_newline: true}, args)

      "-e" ->
        parse_echo_options(rest, %{opts | enable_escapes: true}, args)

      "-E" ->
        parse_echo_options(rest, %{opts | enable_escapes: false}, args)

      "--no-newline" ->
        parse_echo_options(rest, %{opts | no_newline: true}, args)

      "--enable-escapes" ->
        parse_echo_options(rest, %{opts | enable_escapes: true}, args)

      "--disable-escapes" ->
        parse_echo_options(rest, %{opts | enable_escapes: false}, args)

      # Non-option argument - stop parsing and collect remaining
      _ ->
        {opts, Enum.reverse(args) ++ [arg | rest]}
    end
  end

  @doc """
  true - do nothing, successfully

  Return a successful (zero) exit code.

  Usage: true

  ## Examples
      true
  """
  def shell_true(_argv, _stdin, context) do
    {context, "", "", 0}
  end

  @doc """
  false - do nothing, unsuccessfully

  Return an unsuccessful (non-zero) exit code.

  Usage: false

  ## Examples
      false
  """
  def shell_false(_argv, _stdin, context) do
    {context, "", "", 1}
  end

  @doc """
  pwd - print working directory

  Print the absolute pathname of the current working directory.

  Usage: pwd

  ## Examples
      pwd
  """
  def shell_pwd(_argv, _stdin, context) do
    {context, context.cwd <> "\n", "", 0}
  end

  @doc """
  cd - change the working directory

  Change the current working directory to DIR.

  Usage: cd [DIR]

  If no DIR is specified, changes to the home directory (if available in context).

  ## Examples
      cd /tmp
      cd ..
      cd
  """
  def shell_cd(argv, _stdin, context) do
    target_dir = case argv do
      [] ->
        # No argument - try to go to HOME
        Map.get(context.env || %{}, "HOME", context.cwd)
      [dir | _] ->
        resolve_path(dir, context.cwd)
    end

    # In simulate mode, we just update the context without checking if the directory exists
    # In real mode, we would validate with File.dir?/1
    case context.mode do
      :real ->
        if File.dir?(target_dir) do
          new_context = %{context | cwd: target_dir}
          {new_context, "", "", 0}
        else
          {context, "", "cd: #{target_dir}: No such file or directory\n", 1}
        end
      _ ->
        # Simulate mode - just update context
        new_context = %{context | cwd: target_dir}
        {new_context, "", "", 0}
    end
  end

  # Resolve a path relative to the current working directory
  defp resolve_path(path, cwd) do
    case path do
      "/" <> _ ->
        # Absolute path
        Path.expand(path)
      "~" <> rest ->
        # Home directory expansion (simplified)
        Path.expand("~" <> rest)
      _ ->
        # Relative path
        Path.expand(Path.join(cwd, path))
    end
  end

  @doc """
  export - set environment variables

  Set environment variable NAME to VALUE.

  Usage: export NAME=VALUE

  Options:
    -n, --unset
        type: boolean
        default: false
        desc: Remove the variable from the environment

  ## Examples
      export PATH=/usr/bin
      export DEBUG=true
      export -n DEBUG
  """
  def shell_export(argv, _stdin, context) do
    {opts, args} = parse_export_options(argv)

    cond do
      opts.unset && length(args) > 0 ->
        # Remove variables
        new_env = Enum.reduce(args, context.env || %{}, fn var_name, env ->
          Map.delete(env, var_name)
        end)
        new_context = %{context | env: new_env}
        {new_context, "", "", 0}

      length(args) == 0 ->
        # No arguments - print all environment variables
        env = context.env || %{}
        output = env
          |> Enum.map(fn {k, v} -> "#{k}=#{v}" end)
          |> Enum.sort()
          |> Enum.join("\n")
        output = if output == "", do: "", else: output <> "\n"
        {context, output, "", 0}

      true ->
        # Set variables
        new_env = Enum.reduce(args, context.env || %{}, fn assignment, env ->
          case String.split(assignment, "=", parts: 2) do
            [name, value] -> Map.put(env, name, value)
            [name] -> Map.put(env, name, "")
          end
        end)
        new_context = %{context | env: new_env}
        {new_context, "", "", 0}
    end
  end

  defp parse_export_options(argv) do
    parse_export_options(argv, %{unset: false}, [])
  end

  defp parse_export_options([], opts, args), do: {opts, Enum.reverse(args)}

  defp parse_export_options([arg | rest], opts, args) do
    case arg do
      "-n" -> parse_export_options(rest, %{opts | unset: true}, args)
      "--unset" -> parse_export_options(rest, %{opts | unset: true}, args)
      _ -> {opts, Enum.reverse(args) ++ [arg | rest]}
    end
  end

  @doc """
  printenv - print environment variables

  Print the values of environment variables.

  Usage: printenv [NAME]...

  If no NAME is specified, print all environment variables.

  ## Examples
      printenv
      printenv PATH
      printenv HOME USER
  """
  def shell_printenv(argv, _stdin, context) do
    env = context.env || %{}

    output = if length(argv) == 0 do
      # Print all variables
      env
      |> Enum.map(fn {k, v} -> "#{k}=#{v}" end)
      |> Enum.sort()
      |> Enum.join("\n")
    else
      # Print specific variables
      argv
      |> Enum.map(fn name -> Map.get(env, name, "") end)
      |> Enum.join("\n")
    end

    output = if output == "", do: "", else: output <> "\n"
    {context, output, "", 0}
  end

  @doc """
  man - display manual pages for builtin commands

  Display the help documentation for a builtin command.

  Usage: man [COMMAND]

  Options:
    -a, --all
        type: boolean
        default: false
        desc: List all available builtins

  ## Examples
      man echo
      man -a
  """
  def shell_man(argv, _stdin, context) do
    {opts, args} = parse_man_options(argv)

    cond do
      opts.all ->
        # List all builtins
        builtins = list_all_builtins()
        output = "Available builtins:\n" <> Enum.join(builtins, "\n") <> "\n"
        {context, output, "", 0}

      length(args) == 0 ->
        {context, "", "man: missing command name\nUsage: man [COMMAND]\n", 1}

      true ->
        [command_name | _] = args

        if is_builtin?(command_name) do
          help_text = get_builtin_help(command_name)
          {context, help_text <> "\n", "", 0}
        else
          {context, "", "man: no manual entry for #{command_name}\n", 1}
        end
    end
  end

  defp parse_man_options(argv) do
    parse_man_options(argv, %{all: false}, [])
  end

  defp parse_man_options([], opts, args), do: {opts, Enum.reverse(args)}

  defp parse_man_options([arg | rest], opts, args) do
    case arg do
      "-a" -> parse_man_options(rest, %{opts | all: true}, args)
      "--all" -> parse_man_options(rest, %{opts | all: true}, args)
      _ -> {opts, Enum.reverse(args) ++ [arg | rest]}
    end
  end

  defp list_all_builtins do
    __MODULE__.__info__(:functions)
    |> Enum.filter(fn {name, arity} ->
      String.starts_with?(Atom.to_string(name), "shell_") && arity == 3
    end)
    |> Enum.map(fn {name, _arity} ->
      name
      |> Atom.to_string()
      |> String.trim_leading("shell_")
    end)
    |> Enum.sort()
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
