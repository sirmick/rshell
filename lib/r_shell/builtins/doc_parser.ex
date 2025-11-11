defmodule RShell.Builtins.DocParser do
  @moduledoc """
  Parses builtin command docstrings to extract option specifications and help text.

  Scans for structured documentation in the format:

      Options:
        -n, --no-newline
            type: boolean
            default: false
            desc: Do not output the trailing newline

  And generates OptionParser specs and formatted help text.
  """

  @doc """
  Parse a docstring and extract option specifications.

  Returns a list of option specs compatible with RShell.Builtins.OptionParser.

  ## Example

      iex> doc = \"\"\"
      ...> echo - output text
      ...>
      ...> Options:
      ...>   -n, --no-newline
      ...>       type: boolean
      ...>       default: false
      ...>       desc: Do not output trailing newline
      ...> \"\"\"
      iex> DocParser.parse_options(doc)
      [%{short: "-n", long: "--no-newline", type: :boolean,
         key: :no_newline, default: false,
         description: "Do not output trailing newline"}]
  """
  def parse_options(nil), do: []
  def parse_options(docstring) when is_binary(docstring) do
    case extract_options_section(docstring) do
      nil -> []
      options_text -> parse_option_entries(options_text)
    end
  end

  @doc """
  Extract just the options section from a docstring.

  Returns the text between "Options:" and the next section or end of options.
  """
  def extract_options_section(docstring) do
    case String.split(docstring, ~r/^Options:\s*$/m, parts: 2) do
      [_before, after_options] ->
        # Take until next markdown section (## or end of indented block)
        after_options
        |> String.split(~r/^##/m, parts: 2)
        |> hd()
        |> String.trim()

      _ ->
        nil
    end
  end

  @doc """
  Parse individual option entries from the options section text.

  Each option is formatted as:
    -n, --no-newline
        type: boolean
        default: false
        desc: Description text
  """
  def parse_option_entries(text) do
    text
    |> String.split(~r/\n(?=\s{2}-)/m)  # Split on lines starting with "  -"
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(&parse_single_option/1)
    |> Enum.reject(&is_nil/1)
  end

  defp parse_single_option(entry_text) do
    lines = String.split(entry_text, "\n") |> Enum.map(&String.trim/1)

    case lines do
      [flags_line | metadata_lines] ->
        flags = parse_flags(flags_line)
        metadata = parse_metadata(metadata_lines)

        if flags && metadata do
          Map.merge(flags, metadata)
        else
          nil
        end

      _ ->
        nil
    end
  end

  defp parse_flags(flags_line) do
    # Parse "-n, --no-newline" or just "-n" or just "--no-newline"
    parts = String.split(flags_line, ",") |> Enum.map(&String.trim/1)

    {short, long} =
      Enum.reduce(parts, {nil, nil}, fn part, {s, l} ->
        cond do
          String.starts_with?(part, "--") -> {s, part}
          String.starts_with?(part, "-") -> {part, l}
          true -> {s, l}
        end
      end)

    # Generate key from long flag or short flag
    key = cond do
      long != nil ->
        long
        |> String.trim_leading("--")
        |> String.replace("-", "_")
        |> String.to_atom()

      short != nil ->
        short
        |> String.trim_leading("-")
        |> String.to_atom()

      true ->
        nil
    end

    if key do
      flags = %{key: key}
      flags = if short, do: Map.put(flags, :short, short), else: flags
      flags = if long, do: Map.put(flags, :long, long), else: flags
      flags
    else
      nil
    end
  end

  defp parse_metadata(lines) do
    metadata =
      lines
      |> Enum.map(&parse_metadata_line/1)
      |> Enum.reject(&is_nil/1)
      |> Map.new()

    # Convert type string to atom
    metadata = if metadata[:type] do
      %{metadata | type: String.to_atom(metadata.type)}
    else
      metadata
    end

    # Convert default string to appropriate type
    metadata = if Map.has_key?(metadata, :default) do
      %{metadata | default: parse_default_value(metadata.default, metadata[:type])}
    else
      metadata
    end

    # Ensure required fields are present
    if Map.has_key?(metadata, :type) && Map.has_key?(metadata, :default) do
      metadata
    else
      nil
    end
  end

  defp parse_metadata_line(line) do
    case String.split(line, ":", parts: 2) do
      [key, value] ->
        key = key |> String.trim() |> String.to_atom()
        value = String.trim(value)
        {key, value}

      _ ->
        nil
    end
  end

  defp parse_default_value(value, type) do
    case type do
      :boolean ->
        value in ["true", "yes", "1"]

      :integer ->
        case Integer.parse(value) do
          {int, _} -> int
          :error -> 0
        end

      :string ->
        # Strip surrounding quotes from string defaults
        value
        |> String.trim()
        |> String.trim_leading("\"")
        |> String.trim_trailing("\"")

      _ ->
        value
    end
  end

  @doc """
  Extract the full help text from a docstring.

  Returns the docstring formatted for display in help output.
  """
  def extract_help_text(nil), do: ""
  def extract_help_text(docstring) when is_binary(docstring) do
    docstring
    |> String.trim()
  end

  @doc """
  Extract just the summary line (first line) from a docstring.

  ## Example

      iex> doc = "echo - output text\\n\\nLonger description..."
      iex> DocParser.extract_summary(doc)
      "echo - output text"
  """
  def extract_summary(nil), do: ""
  def extract_summary(docstring) when is_binary(docstring) do
    docstring
    |> String.split("\n", parts: 2)
    |> hd()
    |> String.trim()
  end
end
