defmodule RShell.Builtins.OptionParser do
  @moduledoc """
  Generic option parsing for builtin commands.

  Provides a declarative way to define command-line options with:
  - Short and long flag names
  - Boolean flags and flags with values
  - Automatic help text generation
  - POSIX-style option parsing (stops at first non-option)

  ## Example

      defmodule MyBuiltin do
        def options do
          [
            %{
              short: "-n",
              long: "--no-newline",
              type: :boolean,
              default: false,
              key: :no_newline,
              description: "Do not output trailing newline"
            },
            %{
              short: "-e",
              long: "--enable-escapes",
              type: :boolean,
              default: false,
              key: :interpret_escapes,
              description: "Enable interpretation of backslash escapes"
            }
          ]
        end

        def parse_args(args) do
          RShell.Builtins.OptionParser.parse(args, options())
        end
      end
  """

  @type option_spec :: %{
          optional(:short) => String.t(),
          optional(:long) => String.t(),
          type: :boolean | :string | :integer,
          default: any(),
          key: atom(),
          description: String.t()
        }

  @type parsed_result :: {:ok, %{atom() => any()}, [String.t()]} | {:error, String.t()}

  @doc """
  Parse command-line arguments according to option specifications.

  Returns `{:ok, options_map, remaining_args}` on success, or `{:error, reason}` on failure.

  ## Examples

      iex> specs = [
      ...>   %{short: "-n", type: :boolean, default: false, key: :no_newline, description: "No newline"}
      ...> ]
      iex> OptionParser.parse(["-n", "hello"], specs)
      {:ok, %{no_newline: true}, ["hello"]}

      iex> OptionParser.parse(["hello", "-n"], specs)
      {:ok, %{no_newline: false}, ["hello", "-n"]}
  """
  @spec parse([String.t()], [option_spec()]) :: parsed_result()
  def parse(args, option_specs) do
    # Build lookup maps for fast option matching
    short_map = build_short_map(option_specs)
    long_map = build_long_map(option_specs)

    # Initialize options with defaults
    initial_options = build_defaults(option_specs)

    # Parse arguments
    case parse_args(args, initial_options, short_map, long_map, []) do
      {:ok, options, remaining} -> {:ok, options, remaining}
      {:error, _reason} = error -> error
    end
  end

  @doc """
  Generate help text for a builtin command.

  ## Examples

      iex> specs = [
      ...>   %{short: "-n", long: "--no-newline", type: :boolean, default: false, key: :no_newline, description: "No newline"},
      ...>   %{short: "-e", type: :boolean, default: false, key: :interpret_escapes, description: "Enable escapes"}
      ...> ]
      iex> OptionParser.format_help("echo", "Output text to stdout", specs, "echo [OPTIONS] [STRING]...")
      "echo - Output text to stdout\\n\\nUsage: echo [OPTIONS] [STRING]...\\n\\nOptions:\\n  -n, --no-newline    No newline\\n  -e                  Enable escapes\\n"
  """
  @spec format_help(String.t(), String.t(), [option_spec()], String.t()) :: String.t()
  def format_help(command_name, description, option_specs, usage) do
    lines = [
      "#{command_name} - #{description}",
      "",
      "Usage: #{usage}",
      ""
    ]

    if length(option_specs) > 0 do
      option_lines = ["Options:"] ++ format_options(option_specs)
      Enum.join(lines ++ option_lines, "\n") <> "\n"
    else
      Enum.join(lines, "\n") <> "\n"
    end
  end

  # Private helper functions

  defp build_short_map(specs) do
    specs
    |> Enum.filter(&Map.has_key?(&1, :short))
    |> Map.new(fn spec -> {spec.short, spec} end)
  end

  defp build_long_map(specs) do
    specs
    |> Enum.filter(&Map.has_key?(&1, :long))
    |> Map.new(fn spec -> {spec.long, spec} end)
  end

  defp build_defaults(specs) do
    Map.new(specs, fn spec -> {spec.key, spec.default} end)
  end

  defp parse_args([], options, _short_map, _long_map, remaining) do
    {:ok, options, Enum.reverse(remaining)}
  end

  defp parse_args([arg | rest], options, short_map, long_map, remaining) do
    cond do
      # Stop parsing options after "--"
      arg == "--" ->
        {:ok, options, Enum.reverse(remaining) ++ rest}

      # Long option
      String.starts_with?(arg, "--") ->
        handle_long_option(arg, rest, options, short_map, long_map, remaining)

      # Short option
      String.starts_with?(arg, "-") && String.length(arg) > 1 ->
        handle_short_option(arg, rest, options, short_map, long_map, remaining)

      # Not an option - stop parsing and collect remaining args
      true ->
        {:ok, options, Enum.reverse(remaining) ++ [arg | rest]}
    end
  end

  defp handle_short_option(arg, rest, options, short_map, long_map, remaining) do
    case Map.get(short_map, arg) do
      nil ->
        # Unknown option - treat as regular argument (stop parsing)
        {:ok, options, Enum.reverse(remaining) ++ [arg | rest]}

      spec ->
        case spec.type do
          :boolean ->
            new_options = Map.put(options, spec.key, true)
            parse_args(rest, new_options, short_map, long_map, remaining)

          :string ->
            case rest do
              [value | rest_args] ->
                new_options = Map.put(options, spec.key, value)
                parse_args(rest_args, new_options, short_map, long_map, remaining)

              [] ->
                {:error, "Option #{arg} requires a value"}
            end

          :integer ->
            case rest do
              [value | rest_args] ->
                case Integer.parse(value) do
                  {int_value, ""} ->
                    new_options = Map.put(options, spec.key, int_value)
                    parse_args(rest_args, new_options, short_map, long_map, remaining)

                  _ ->
                    {:error, "Option #{arg} requires an integer value"}
                end

              [] ->
                {:error, "Option #{arg} requires a value"}
            end
        end
    end
  end

  defp handle_long_option(arg, rest, options, short_map, long_map, remaining) do
    # Handle --option=value format
    case String.split(arg, "=", parts: 2) do
      [option_name, value] ->
        case Map.get(long_map, option_name) do
          nil ->
            {:ok, options, Enum.reverse(remaining) ++ [arg | rest]}

          spec ->
            new_options = Map.put(options, spec.key, parse_value(value, spec.type))
            parse_args(rest, new_options, short_map, long_map, remaining)
        end

      [option_name] ->
        case Map.get(long_map, option_name) do
          nil ->
            {:ok, options, Enum.reverse(remaining) ++ [arg | rest]}

          spec ->
            case spec.type do
              :boolean ->
                new_options = Map.put(options, spec.key, true)
                parse_args(rest, new_options, short_map, long_map, remaining)

              _ ->
                case rest do
                  [value | rest_args] ->
                    new_options = Map.put(options, spec.key, parse_value(value, spec.type))
                    parse_args(rest_args, new_options, short_map, long_map, remaining)

                  [] ->
                    {:error, "Option #{arg} requires a value"}
                end
            end
        end
    end
  end

  defp parse_value(value, :string), do: value

  defp parse_value(value, :integer) do
    case Integer.parse(value) do
      {int_value, ""} -> int_value
      # Fallback to string if not a valid integer
      _ -> value
    end
  end

  defp parse_value(value, :boolean), do: value in ["true", "1", "yes"]

  defp format_options(specs) do
    # Calculate max width for alignment
    max_width =
      specs
      |> Enum.map(&option_flags/1)
      |> Enum.map(&String.length/1)
      |> Enum.max(fn -> 0 end)

    Enum.map(specs, fn spec ->
      flags = option_flags(spec)
      padding = String.duplicate(" ", max(0, max_width - String.length(flags)))
      "  #{flags}#{padding}    #{spec.description}"
    end)
  end

  defp option_flags(spec) do
    case {Map.get(spec, :short), Map.get(spec, :long)} do
      {nil, nil} -> ""
      {short, nil} -> short
      {nil, long} -> long
      {short, long} -> "#{short}, #{long}"
    end
  end
end
