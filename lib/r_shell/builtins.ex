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
  def shell_echo(%ParsedOptions{} = opts, stdin, state) do
    # opts.options = %{no_newline: true, ...}
    # opts.arguments = ["hello", "world"]
    # opts.argv = ["-n", "hello", "world"]
  end

  def shell_echo(%ParseError{} = error, stdin, state) do
    # error.reason = "Unknown option: -z"
    # error.argv = ["-z", "hello"]
  end
  ```

  ### :argv Mode
  Builtin receives raw argv list:
  ```elixir
  @shell_source_opts :argv
  def shell_source(argv, stdin, state) when is_list(argv) do
    # Custom parsing logic
  end
  ```

  ## Return Value
  A tuple with:
  - `new_state`: Updated ExecutionState (or just context for backward compat)
  - `stdout`: Output stream (always Stream.t())
  - `stderr`: Error stream (always Stream.t())
  - `exit_code`: Integer exit code (0 for success)
  """

  use RShell.Builtins.Helpers
  alias RShell.Builtins.Utils
  alias RShell.Runtime.ExecutionState

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
  def execute(name, argv, stdin, context_or_state) do
    # Normalize to state (backward compatible)
    state = case context_or_state do
      %ExecutionState{} = s -> s
      context when is_map(context) ->
        # Create minimal state from context
        %ExecutionState{
          context: context,
          frame_stack: RShell.Runtime.FrameStack.new(output_mode: :isolate, context: context),
          session_id: Map.get(context, :session_id, "unknown")
        }
    end

    # Check if this is a namespaced command (e.g., "math:add")
    result = case String.split(name, ":", parts: 2) do
      [namespace, command] ->
        # Namespaced command - route to appropriate module
        execute_namespaced(namespace, command, argv, stdin, state)

      [_single_name] ->
        # Non-namespaced command - execute from this module
        execute_local(name, argv, stdin, state)
    end

    # Extract context for backward compatibility
    case result do
      {%ExecutionState{} = new_state, stdout, stderr, exit_code} ->
        {new_state.context, stdout, stderr, exit_code}
      other -> other
    end
  end

  # Execute a command from this module (non-namespaced)
  defp execute_local(name, argv, stdin, state) do
    function_name = String.to_atom("shell_#{name}")

    if function_exported?(__MODULE__, function_name, 3) do
      # Check mode using compile-time generated function
      mode = __builtin_mode__(String.to_atom(name))

      case mode do
        :argv ->
          # Raw argv mode - pass list directly
          apply(__MODULE__, function_name, [argv, stdin, state])

        :parsed ->
          # Parsed mode - parse options from docstring
          option_specs = __builtin_options__(String.to_atom(name))

          case RShell.Builtins.OptionParser.parse(argv, option_specs) do
            {:ok, opts, args} ->
              parsed = %ParsedOptions{options: opts, arguments: args, argv: argv}
              apply(__MODULE__, function_name, [parsed, stdin, state])

            {:error, reason} ->
              error = %ParseError{reason: reason, argv: argv}
              apply(__MODULE__, function_name, [error, stdin, state])
          end

        nil ->
          # No mode specified - error!
          {:error, :missing_opts_attribute}
      end
    else
      {:error, :not_a_builtin}
    end
  end

  # Execute a namespaced command (e.g., "math:add" -> RShell.Builtins.Math.shell_add/3)
  defp execute_namespaced(namespace, command, argv, stdin, state) do
    # Convert namespace to module name: "math" -> RShell.Builtins.Math
    module_name = namespace_to_module(namespace)

    if Code.ensure_loaded?(module_name) do
      function_name = String.to_atom("shell_#{command}")

      if function_exported?(module_name, function_name, 3) do
        # Check mode from the namespace module
        mode = apply(module_name, :__builtin_mode__, [String.to_atom(command)])

        case mode do
          :argv ->
            apply(module_name, function_name, [argv, stdin, state])

          :parsed ->
            option_specs = apply(module_name, :__builtin_options__, [String.to_atom(command)])

            case RShell.Builtins.OptionParser.parse(argv, option_specs) do
              {:ok, opts, args} ->
                parsed = %ParsedOptions{options: opts, arguments: args, argv: argv}
                apply(module_name, function_name, [parsed, stdin, state])

              {:error, reason} ->
                error = %ParseError{reason: reason, argv: argv}
                apply(module_name, function_name, [error, stdin, state])
            end

          nil ->
            {:error, :missing_opts_attribute}
        end
      else
        {:error, :not_a_builtin}
      end
    else
      {:error, :not_a_builtin}
    end
  end

  # Convert namespace to module atom
  # "math" -> RShell.Builtins.Math
  # "str" -> RShell.Builtins.Str
  defp namespace_to_module(namespace) do
    capitalized = String.capitalize(namespace)
    Module.concat(RShell.Builtins, capitalized)
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
    case String.split(name, ":", parts: 2) do
      [namespace, command] ->
        # Namespaced command - check namespace module
        module_name = namespace_to_module(namespace)
        function_name = String.to_atom("shell_#{command}")

        Code.ensure_loaded?(module_name) &&
          function_exported?(module_name, function_name, 3)

      [_single_name] ->
        # Non-namespaced - check this module
        function_name = String.to_atom("shell_#{name}")
        function_exported?(__MODULE__, function_name, 3)
    end
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
  def shell_echo(%ParseError{reason: reason}, _stdin, state) do
    help_text = get_builtin_help("echo")
    stderr = "echo: #{reason}\n\n#{help_text}"
    {state, Utils.stream(""), Utils.stream(stderr), 1}
  end

  def shell_echo(%ParsedOptions{} = opts, _stdin, state) do
    args = opts.arguments

    # Handle -e/-E mutual exclusion: -E overrides -e
    should_escape = opts.options.enable_escapes && !opts.options.disable_escapes

    output =
      args
      |> Enum.map(&Utils.to_string/1)
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

    {state, Utils.stream(output), Utils.stream(""), 0}
  end

  @doc """
  true - do nothing, successfully

  Return a successful (zero) exit code.

  Usage: true

  ## Examples
      true
  """
  @shell_true_opts :argv
  def shell_true(_argv, _stdin, state) do
    {state, Utils.stream(""), Utils.stream(""), 0}
  end

  @doc """
  false - do nothing, unsuccessfully

  Return an unsuccessful (non-zero) exit code.

  Usage: false

  ## Examples
      false
  """
  @shell_false_opts :argv
  def shell_false(_argv, _stdin, state) do
    {state, Utils.stream(""), Utils.stream(""), 1}
  end

  @doc """
  pwd - print working directory

  Print the absolute pathname of the current working directory.

  Usage: pwd

  ## Examples
      pwd
  """
  @shell_pwd_opts :argv
  def shell_pwd(_argv, _stdin, state) do
    {state, Utils.stream(state.context.cwd <> "\n"), Utils.stream(""), 0}
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
  def shell_cd(%ParseError{reason: reason}, _stdin, state) do
    help_text = get_builtin_help("cd")
    stderr = "cd: #{reason}\n\n#{help_text}"
    {state, Utils.stream(""), Utils.stream(stderr), 1}
  end

  def shell_cd(%ParsedOptions{} = opts, _stdin, state) do
    args = opts.arguments

    target_dir =
      case args do
        [] ->
          # No argument - try to go to HOME
          Map.get(state.context.env || %{}, "HOME", state.context.cwd)

        [dir | _] ->
          # Physical mode is a hint for future implementation
          # Currently we always use Path.expand which resolves symlinks
          _physical = opts.options.physical
          resolve_path(dir, state.context.cwd)
      end

    # Always update context (no mode check - just execute)
    new_context = %{state.context | cwd: target_dir}
    new_state = %{state | context: new_context}
    {new_state, Utils.stream(""), Utils.stream(""), 0}
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
  man - display manual pages for builtin commands

  Display the help documentation for a builtin command.

  Usage: man [COMMAND]

  With no arguments, lists all available builtins organized by namespace.
  With COMMAND, displays the manual page for that builtin.

  Options:
    -a, --all
        type: boolean
        default: false
        desc: List all available builtins (same as no arguments)

  ## Examples
      man                  # List all builtins by namespace
      man echo             # Show help for echo
      man math:add         # Show help for math:add
  """
  @shell_man_opts :parsed
  def shell_man(%ParseError{reason: reason}, _stdin, state) do
    help_text = get_builtin_help("man")
    stderr = "man: #{reason}\n\n#{help_text}"
    {state, Utils.stream(""), Utils.stream(stderr), 1}
  end

  def shell_man(%ParsedOptions{} = opts, _stdin, state) do
    args = opts.arguments

    cond do
      opts.options.all || length(args) == 0 ->
        # List all builtins organized by namespace
        output = format_builtin_list()
        {state, Utils.stream(output), Utils.stream(""), 0}

      true ->
        [command_name | _] = args

        if is_builtin?(command_name) do
          help_text = get_builtin_help(command_name)
          {state, Utils.stream(help_text <> "\n"), Utils.stream(""), 0}
        else
          {state, Utils.stream(""), Utils.stream("man: no manual entry for #{command_name}\n"), 1}
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
  def shell_env(argv, _stdin, state) do
    context = state.context

    cond do
      # No arguments - list all
      length(argv) == 0 ->
        env = context.env || %{}

        output =
          env
          |> Enum.map(fn {k, v} ->
            formatted_value = RShell.EnvJSON.format(v)
            "#{k}=#{formatted_value}"
          end)
          |> Enum.sort()
          |> Enum.join("\n")

        output = if output == "", do: "", else: output <> "\n"
        {state, Utils.stream(output), Utils.stream(""), 0}

      # Has arguments - check if they're assignments or lookups
      true ->
        {assignments, lookups} = split_assignments_and_lookups(argv)

        # Process assignments first
        new_context =
          if length(assignments) > 0 do
            new_env =
              Enum.reduce(assignments, context.env || %{}, fn {name, value_str}, env ->
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

        new_state = %{state | context: new_context}

        # Process lookups
        if length(lookups) > 0 do
          env = new_context.env || %{}

          values =
            lookups
            |> Enum.map(fn name ->
              case Map.get(env, name) do
                nil -> nil
                value -> RShell.EnvJSON.format(value)
              end
            end)
            |> Enum.reject(&is_nil/1)

          output =
            if length(values) > 0 do
              Enum.join(values, "\n") <> "\n"
            else
              ""
            end

          {new_state, Utils.stream(output), Utils.stream(""), 0}
        else
          # Only assignments, no output
          {new_state, Utils.stream(""), Utils.stream(""), 0}
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

  @doc """
  inspect - inspect variable type and value

  Display the Elixir type and IO.inspect representation of a variable.
  Useful for debugging and verifying type preservation through control structures.

  Usage: inspect [NAME]...

  If no NAME is specified, returns an error.
  For each variable, displays:
    - Variable name
    - Elixir type (e.g., :binary, :integer, :map, :list)
    - IO.inspect output (pretty-printed Elixir representation)

  ## Examples
      inspect X                    # Show type and value of X
      inspect CONFIG SERVERS       # Show multiple variables
      env DATA='{"x":1,"y":2}'    # Set a JSON map
      inspect DATA                 # Shows: :map, %{"x" => 1, "y" => 2}
  """
  @shell_inspect_opts :argv
  def shell_inspect([], _stdin, state) do
    stderr = "inspect: missing variable name\nUsage: inspect [NAME]...\n"
    {state, Utils.stream(""), Utils.stream(stderr), 1}
  end

  def shell_inspect(argv, _stdin, state) do
    env = state.context.env || %{}

    output =
      argv
      |> Enum.map(fn arg ->
        # Handle both direct variable names (inspect X) and dereferenced values (inspect $X)
        # If arg is a string, treat it as a variable name lookup
        # If arg is a native value (list, map, etc.), inspect it directly
        {display_name, value} =
          if is_binary(arg) do
            # String argument - treat as variable name
            {arg, Map.get(env, arg)}
          else
            # Native value from $X expansion - inspect directly
            {inspect(arg, pretty: false, width: :infinity), arg}
          end

        case value do
          nil ->
            "#{display_name}: <not set>\n"

          val ->
            # Determine Elixir type
            type =
              cond do
                is_binary(val) -> :binary
                is_integer(val) -> :integer
                is_float(val) -> :float
                is_boolean(val) -> :boolean
                is_atom(val) -> :atom
                is_list(val) -> :list
                is_map(val) -> :map
                is_tuple(val) -> :tuple
                true -> :unknown
              end

            # Format value using IO.inspect with nice formatting
            inspected = inspect(val, pretty: true, width: 80)

            # For dereferenced values, don't show the variable name, just type and value
            if is_binary(arg) do
              "#{display_name}:\n  Type: #{type}\n  Value: #{inspected}\n"
            else
              "Type: #{type}\nValue: #{inspected}\n"
            end
        end
      end)
      |> Enum.join("\n")

    {state, Utils.stream(output), Utils.stream(""), 0}
  end

  @doc """
  test - evaluate conditional expressions

  Enhanced test builtin with native type support for RShell.

  Usage: test EXPRESSION
     or: test ARG1 OP ARG2

  String Comparison:
    =             Equal (strings)
    !=            Not equal (strings)

  Numeric Comparison:
    -eq           Equal (numbers)
    -ne           Not equal (numbers)
    -gt           Greater than
    -ge           Greater than or equal
    -lt           Less than
    -le           Less than or equal

  Type Checking:
    -n STRING     STRING has nonzero length
    -z STRING     STRING has zero length

  Rich Type Support:
    - Map access: $CONFIG["key"]
    - List access: $ARRAY[0]
    - Nested access: $DATA["user"]["age"]
    - Native type preservation

  ## Examples
      test 5 -gt 3
      test $NAME = "alice"
      test $USER["age"] -gt 25
      test $SERVERS[0] = "web1"
      test $CONFIG["db"]["port"] -eq 5432
  """
  @shell_test_opts :argv
  def shell_test([], _stdin, state) do
    # No arguments - return false
    {state, Utils.stream(""), Utils.stream(""), 1}
  end

  def shell_test([arg], _stdin, state) do
    # Single argument - check if truthy
    result = is_truthy?(arg)
    exit_code = if result, do: 0, else: 1
    {state, Utils.stream(""), Utils.stream(""), exit_code}
  end

  def shell_test([left, op, right], _stdin, state) do
    # Three arguments - binary comparison
    result = evaluate_comparison(left, op, right, state.context)
    exit_code = if result, do: 0, else: 1
    {state, Utils.stream(""), Utils.stream(""), exit_code}
  end

  def shell_test(_argv, _stdin, state) do
    # Other arities - not supported yet
    {state, Utils.stream(""), Utils.stream("test: unsupported expression\n"), 1}
  end

  defp is_truthy?(nil), do: false
  defp is_truthy?(""), do: false
  defp is_truthy?(false), do: false
  defp is_truthy?(0), do: false
  defp is_truthy?([]), do: false
  defp is_truthy?(%{} = map) when map_size(map) == 0, do: false
  defp is_truthy?(_), do: true

  defp evaluate_comparison(left_expr, op, right_expr, _context) do
    # For now, simple string/number comparison
    # Note: Variable expansion already happened in runtime
    left = left_expr
    right = right_expr

    case op do
      # String equality
      "=" -> Kernel.to_string(left) == Kernel.to_string(right)
      "!=" -> Kernel.to_string(left) != Kernel.to_string(right)
      # Numeric comparisons
      "-eq" -> Utils.to_number(left) == Utils.to_number(right)
      "-ne" -> Utils.to_number(left) != Utils.to_number(right)
      "-gt" -> Utils.to_number(left) > Utils.to_number(right)
      "-ge" -> Utils.to_number(left) >= Utils.to_number(right)
      "-lt" -> Utils.to_number(left) < Utils.to_number(right)
      "-le" -> Utils.to_number(left) <= Utils.to_number(right)
      # Length checks
      "-n" -> is_truthy?(left) && String.length(Kernel.to_string(left)) > 0
      "-z" -> !is_truthy?(left) || String.length(Kernel.to_string(left)) == 0
      _ -> false
    end
  end

  # Get all builtins organized by namespace
  defp list_all_builtins do
    # Get core builtins (no namespace)
    core_builtins =
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

    # Get namespaced builtins (currently just math)
    math_builtins =
      if Code.ensure_loaded?(RShell.Builtins.Math) do
        RShell.Builtins.Math.__info__(:functions)
        |> Enum.filter(fn {name, arity} ->
          String.starts_with?(Atom.to_string(name), "shell_") && arity == 3
        end)
        |> Enum.map(fn {name, _arity} ->
          command =
            name
            |> Atom.to_string()
            |> String.trim_leading("shell_")

          "math:#{command}"
        end)
        |> Enum.sort()
      else
        []
      end

    %{
      core: core_builtins,
      math: math_builtins
    }
  end

  # Format the builtin list organized by namespace
  defp format_builtin_list do
    builtins = list_all_builtins()

    sections = [
      {"Core Builtins:", builtins.core},
      {"Math Builtins:", builtins.math}
    ]

    sections
    |> Enum.reject(fn {_title, commands} -> Enum.empty?(commands) end)
    |> Enum.map(fn {title, commands} ->
      commands_str =
        commands
        |> Enum.map(fn cmd -> "  #{cmd}" end)
        |> Enum.join("\n")

      "#{title}\n#{commands_str}"
    end)
    |> Enum.join("\n\n")
    |> Kernel.<>("\n")
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
