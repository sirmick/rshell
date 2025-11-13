defmodule RShell.Builtins do
  @moduledoc """
  Built-in shell commands implemented in Elixir.

  Each builtin must declare its invocation mode using the `@shell_*_opts` attribute:
  - `@shell_name_opts :parsed` - Parse options from docstring, receive ParsedOptions or ParseError struct
  - `@shell_name_opts :argv` - Receive raw argv list for custom parsing

  ## Invocation Modes

  ### :parsed Mode
  Builtin receives either ParsedOptions (success) or ParseError (failure):
  ```elixir
  @shell_echo_opts :parsed
  def shell_echo(%ParsedOptions{} = opts, stdin, context) do
    # opts.options = %{no_newline: true, ...}
    # opts.arguments = ["hello", "world"]
    # opts.argv = ["-n", "hello", "world"]
  end

  def shell_echo(%ParseError{} = error, stdin, context) do
    # error.reason = "Unknown option: -z"
    # error.argv = ["-z", "hello"]
  end
  ```

  ### :argv Mode
  Builtin receives raw argv list:
  ```elixir
  @shell_source_opts :argv
  def shell_source(argv, stdin, context) when is_list(argv) do
    # Custom parsing logic
  end
  ```

  ## Return Value
  A tuple with:
  - `new_context`: Updated context (unchanged for pure builtins)
  - `stdout`: Output stream (always Stream.t())
  - `stderr`: Error stream (always Stream.t())
  - `exit_code`: Integer exit code (0 for success)
  """

  use RShell.Builtins.Helpers

  defmodule ParsedOptions do
    @moduledoc "Represents successfully parsed builtin options"
    defstruct [:options, :arguments, :argv]
  end

  defmodule ParseError do
    @moduledoc "Represents a parse error for builtin options"
    defstruct [:reason, :argv]
  end

  @doc """
  Execute a builtin command by name.

  Uses reflection to invoke the appropriate `shell_*` function.
  Returns `{context, stdout_stream, stderr_stream, exit_code}`.
  Stdout and stderr are `Stream.t()` that must be materialized.

  ## Examples

      iex> {ctx, stdout, stderr, exit_code} = RShell.Builtins.execute("echo", ["hello"], "", %{})
      iex> ctx
      %{}
      iex> Enum.join(stdout, "")
      "hello\\n"
      iex> Enum.join(stderr, "")
      ""
      iex> exit_code
      0

      iex> RShell.Builtins.execute("unknown", [], "", %{})
      {:error, :not_a_builtin}
  """
  def execute(name, argv, stdin, context) do
    function_name = String.to_atom("shell_#{name}")

    if function_exported?(__MODULE__, function_name, 3) do
      # Check mode using compile-time generated function
      mode = __builtin_mode__(String.to_atom(name))

      case mode do
        :argv ->
          # Raw argv mode - pass list directly
          apply(__MODULE__, function_name, [argv, stdin, context])

        :parsed ->
          # Parsed mode - parse options from docstring
          option_specs = __builtin_options__(String.to_atom(name))
          case RShell.Builtins.OptionParser.parse(argv, option_specs) do
            {:ok, opts, args} ->
              parsed = %ParsedOptions{options: opts, arguments: args, argv: argv}
              apply(__MODULE__, function_name, [parsed, stdin, context])

            {:error, reason} ->
              error = %ParseError{reason: reason, argv: argv}
              apply(__MODULE__, function_name, [error, stdin, context])
          end

        nil ->
          # No mode specified - error!
          {:error, :missing_opts_attribute}
      end
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
  @shell_echo_opts :parsed
  def shell_echo(%ParseError{reason: reason}, _stdin, context) do
    help_text = get_builtin_help("echo")
    stderr = "echo: #{reason}\n\n#{help_text}"
    {context, stream(""), stream(stderr), 1}
  end

  def shell_echo(%ParsedOptions{} = opts, _stdin, context) do
    args = opts.arguments

    # Handle -e/-E mutual exclusion: -E overrides -e
    should_escape = opts.options.enable_escapes && !opts.options.disable_escapes

    output =
      args
      |> Enum.map(&convert_arg_to_string/1)
      |> Enum.join(" ")
      |> then(fn text ->
        if should_escape do
          process_escapes(text)
        else
          text
        end
      end)
      |> then(fn text ->
        if opts.options.no_newline do
          text
        else
          text <> "\n"
        end
      end)

    {context, stream(output), stream(""), 0}
  end

  # Convert rich types to strings for echo output
  defp convert_arg_to_string(arg) when is_binary(arg), do: arg
  defp convert_arg_to_string(arg) when is_map(arg), do: RShell.EnvJSON.format(arg)
  defp convert_arg_to_string(arg) when is_list(arg) do
    # Check if charlist
    if Enum.all?(arg, &(is_integer(&1) and &1 >= 32 and &1 <= 126)) do
      List.to_string(arg)
    else
      RShell.EnvJSON.format(arg)
    end
  end
  defp convert_arg_to_string(arg) when is_integer(arg), do: Integer.to_string(arg)
  defp convert_arg_to_string(arg) when is_float(arg), do: Float.to_string(arg)
  defp convert_arg_to_string(true), do: "true"
  defp convert_arg_to_string(false), do: "false"
  defp convert_arg_to_string(nil), do: ""
  defp convert_arg_to_string(atom) when is_atom(atom), do: Atom.to_string(atom)


  @doc """
  true - do nothing, successfully

  Return a successful (zero) exit code.

  Usage: true

  ## Examples
      true
  """
  @shell_true_opts :argv
  def shell_true(_argv, _stdin, context) do
    {context, stream(""), stream(""), 0}
  end

  @doc """
  false - do nothing, unsuccessfully

  Return an unsuccessful (non-zero) exit code.

  Usage: false

  ## Examples
      false
  """
  @shell_false_opts :argv
  def shell_false(_argv, _stdin, context) do
    {context, stream(""), stream(""), 1}
  end

  @doc """
  pwd - print working directory

  Print the absolute pathname of the current working directory.

  Usage: pwd

  ## Examples
      pwd
  """
  @shell_pwd_opts :argv
  def shell_pwd(_argv, _stdin, context) do
    {context, stream(context.cwd <> "\n"), stream(""), 0}
  end

  @doc """
  cd - change the working directory

  Change the current working directory to DIR.

  Usage: cd [OPTIONS] [DIR]

  If no DIR is specified, changes to the home directory (if available in context).

  Options:
    -L, --logical
        type: boolean
        default: true
        desc: Follow symbolic links (default behavior)

    -P, --physical
        type: boolean
        default: false
        desc: Use physical directory structure without following symbolic links

  ## Examples
      cd /tmp
      cd ..
      cd
      cd -P /path/with/symlink
  """
  @shell_cd_opts :parsed
  def shell_cd(%ParseError{reason: reason}, _stdin, context) do
    help_text = get_builtin_help("cd")
    stderr = "cd: #{reason}\n\n#{help_text}"
    {context, stream(""), stream(stderr), 1}
  end

  def shell_cd(%ParsedOptions{} = opts, _stdin, context) do
    args = opts.arguments

    target_dir = case args do
      [] ->
        # No argument - try to go to HOME
        Map.get(context.env || %{}, "HOME", context.cwd)
      [dir | _] ->
        # Physical mode is a hint for future implementation
        # Currently we always use Path.expand which resolves symlinks
        _physical = opts.options.physical
        resolve_path(dir, context.cwd)
    end

    # Always update context (no mode check - just execute)
    new_context = %{context | cwd: target_dir}
    {new_context, stream(""), stream(""), 0}
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
  @shell_export_opts :parsed
  def shell_export(%ParseError{reason: reason}, _stdin, context) do
    help_text = get_builtin_help("export")
    stderr = "export: #{reason}\n\n#{help_text}"
    {context, stream(""), stream(stderr), 1}
  end

  def shell_export(%ParsedOptions{} = opts, _stdin, context) do
    args = opts.arguments

    cond do
      opts.options.unset && length(args) > 0 ->
        # Remove variables
        new_env = Enum.reduce(args, context.env || %{}, fn var_name, env ->
          Map.delete(env, var_name)
        end)
        new_context = %{context | env: new_env}
        {new_context, stream(""), stream(""), 0}

      length(args) == 0 ->
        # No arguments - print all environment variables
        env = context.env || %{}
        output = env
          |> Enum.map(fn {k, v} -> "#{k}=#{v}" end)
          |> Enum.sort()
          |> Enum.join("\n")
        output = if output == "", do: "", else: output <> "\n"
        {context, stream(output), stream(""), 0}

      true ->
        # Set variables
        new_env = Enum.reduce(args, context.env || %{}, fn assignment, env ->
          case String.split(assignment, "=", parts: 2) do
            [name, value] -> Map.put(env, name, value)
            [name] -> Map.put(env, name, "")
          end
        end)
        new_context = %{context | env: new_env}
        {new_context, stream(""), stream(""), 0}
    end
  end

  @doc """
  printenv - print environment variables

  Print the values of environment variables.

  Usage: printenv [OPTIONS] [NAME]...

  If no NAME is specified, print all environment variables.

  Options:
    -0, --null
        type: boolean
        default: false
        desc: End each output line with null byte instead of newline

  ## Examples
      printenv
      printenv PATH
      printenv HOME USER
      printenv -0 PATH
  """
  @shell_printenv_opts :parsed
  def shell_printenv(%ParseError{reason: reason}, _stdin, context) do
    help_text = get_builtin_help("printenv")
    stderr = "printenv: #{reason}\n\n#{help_text}"
    {context, stream(""), stream(stderr), 1}
  end

  def shell_printenv(%ParsedOptions{} = opts, _stdin, context) do
    args = opts.arguments
    env = context.env || %{}
    use_null = opts.options.null
    separator = if use_null, do: <<0>>, else: "\n"

    output = if length(args) == 0 do
      # Print all variables
      env
      |> Enum.map(fn {k, v} -> "#{k}=#{v}" end)
      |> Enum.sort()
      |> Enum.join(separator)
    else
      # Print specific variables
      args
      |> Enum.map(fn name -> Map.get(env, name, "") end)
      |> Enum.join(separator)
    end

    output = if output == "", do: "", else: output <> separator
    {context, stream(output), stream(""), 0}
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
  @shell_man_opts :parsed
  def shell_man(%ParseError{reason: reason}, _stdin, context) do
    help_text = get_builtin_help("man")
    stderr = "man: #{reason}\n\n#{help_text}"
    {context, stream(""), stream(stderr), 1}
  end

  def shell_man(%ParsedOptions{} = opts, _stdin, context) do
    args = opts.arguments

    cond do
      opts.options.all ->
        # List all builtins
        builtins = list_all_builtins()
        output = "Available builtins:\n" <> Enum.join(builtins, "\n") <> "\n"
        {context, stream(output), stream(""), 0}

      length(args) == 0 ->
        {context, stream(""), stream("man: missing command name\nUsage: man [COMMAND]\n"), 1}

      true ->
        [command_name | _] = args

        if is_builtin?(command_name) do
          help_text = get_builtin_help(command_name)
          {context, stream(help_text <> "\n"), stream(""), 0}
        else
          {context, stream(""), stream("man: no manual entry for #{command_name}\n"), 1}
        end
    end
  end

  @doc """
  env - get or set environment variables

  Unified environment variable management with rich data type support.

  Usage: env [NAME=VALUE]... [NAME]...

  With no arguments, list all environment variables.
  With NAME=VALUE pairs, set environment variables (supports JSON values).
  With NAME arguments, print the values of the specified variables.

  Values are parsed as JSON to support rich data types:
    - Maps: {"host":"localhost","port":5432}
    - Lists: ["web1","web2","db1"]
    - Numbers: 42, 3.14
    - Booleans: true, false
    - Strings: "hello" (must be quoted!)

  ## Examples
      env                              # List all variables
      env PATH                         # Show PATH value
      env A={"x":1} B=12 C="hello"    # Set multiple variables
      env CONFIG                       # Show CONFIG (pretty-printed if JSON)
  """
  @shell_env_opts :argv
  def shell_env(argv, _stdin, context) do
    cond do
      # No arguments - list all
      length(argv) == 0 ->
        env = context.env || %{}
        output = env
          |> Enum.map(fn {k, v} ->
            formatted_value = RShell.EnvJSON.format(v)
            "#{k}=#{formatted_value}"
          end)
          |> Enum.sort()
          |> Enum.join("\n")
        output = if output == "", do: "", else: output <> "\n"
        {context, stream(output), stream(""), 0}

      # Has arguments - check if they're assignments or lookups
      true ->
        {assignments, lookups} = split_assignments_and_lookups(argv)

        # Process assignments first
        new_context = if length(assignments) > 0 do
          new_env = Enum.reduce(assignments, context.env || %{}, fn {name, value_str}, env ->
            case RShell.EnvJSON.parse(value_str) do
              {:ok, parsed_value} ->
                # Successfully parsed as JSON
                Map.put(env, name, parsed_value)
              {:error, _reason} ->
                # If parse fails, treat as plain string (common case)
                # No warning - plain strings are expected
                Map.put(env, name, value_str)
            end
          end)
          %{context | env: new_env}
        else
          context
        end

        # Process lookups
        if length(lookups) > 0 do
          env = new_context.env || %{}
          values = lookups
            |> Enum.map(fn name ->
              case Map.get(env, name) do
                nil -> nil
                value -> RShell.EnvJSON.format(value)
              end
            end)
            |> Enum.reject(&is_nil/1)

          output = if length(values) > 0 do
            Enum.join(values, "\n") <> "\n"
          else
            ""
          end

          {new_context, stream(output), stream(""), 0}
        else
          # Only assignments, no output
          {new_context, stream(""), stream(""), 0}
        end
    end
  end

  # Split argv into assignments (NAME=VALUE) and lookups (NAME)
  defp split_assignments_and_lookups(argv) do
    Enum.reduce(argv, {[], []}, fn arg, {assignments, lookups} ->
      case String.split(arg, "=", parts: 2) do
        [name, value] ->
          {[{name, value} | assignments], lookups}
        [name] ->
          {assignments, [name | lookups]}
      end
    end)
    |> then(fn {assignments, lookups} ->
      {Enum.reverse(assignments), Enum.reverse(lookups)}
    end)
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

  # Helper: Convert text to Stream
  # Wraps text in a single-element list so Stream yields the text as one chunk
  defp stream(text) when is_binary(text), do: Stream.concat([[text]])

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
