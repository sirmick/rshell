defmodule RShell.EnvJSON do
  @moduledoc """
  JSON encoding/decoding for environment variable values.

  Uses JSON wrapping technique for universal type detection:
  - Wrap value in {"json": value}
  - Parse as JSON
  - Extract ["json"] key

  This allows automatic detection of maps, lists, numbers, booleans, strings.
  Requires strings to be quoted like JSON.

  ## Examples

      iex> RShell.EnvJSON.parse(~s({"x":1}))
      {:ok, %{"x" => 1}}

      iex> RShell.EnvJSON.parse("[1,2,3]")
      {:ok, [1, 2, 3]}

      iex> RShell.EnvJSON.parse("42")
      {:ok, 42}

      iex> RShell.EnvJSON.parse(~s("hello"))
      {:ok, "hello"}

      iex> RShell.EnvJSON.parse("true")
      {:ok, true}

      iex> match?({:error, _}, RShell.EnvJSON.parse("hello"))
      true
  """

  @doc """
  Parse value using JSON wrapping technique.

  Wraps the value in {"json": value} and parses, then extracts the ["json"] key.
  This allows automatic type detection for all JSON-compatible types.

  Returns `{:ok, parsed_value}` on success or `{:error, reason}` on failure.
  """
  @spec parse(String.t() | term()) :: {:ok, term()} | {:error, String.t()}
  def parse(value) when is_binary(value) do
    # Wrap in {"json": value} and parse
    wrapped = "{\"json\":#{value}}"

    case Jason.decode(wrapped) do
      {:ok, %{"json" => parsed_value}} ->
        {:ok, parsed_value}

      {:error, %Jason.DecodeError{} = error} ->
        {:error, Exception.message(error)}
    end
  end

  # Already native - return as-is wrapped in :ok
  def parse(value), do: {:ok, value}

  @doc """
  Encode native Elixir structure to JSON string.
  Used when passing env vars to external commands.

  ## Examples

      iex> RShell.EnvJSON.encode(%{"host" => "localhost"})
      ~s({"host":"localhost"})

      iex> RShell.EnvJSON.encode([1, 2, 3])
      "[1,2,3]"

      iex> RShell.EnvJSON.encode("hello")
      "hello"

      iex> RShell.EnvJSON.encode(42)
      "42"
  """
  @spec encode(term()) :: String.t()
  def encode(value) when is_binary(value), do: value
  def encode(value) when is_map(value), do: Jason.encode!(value)
  def encode(value) when is_list(value) do
    # Check if charlist
    if is_charlist?(value) do
      List.to_string(value)
    else
      Jason.encode!(value)
    end
  end
  def encode(value) when is_integer(value), do: Integer.to_string(value)
  def encode(value) when is_float(value), do: Float.to_string(value)
  def encode(true), do: "true"
  def encode(false), do: "false"
  def encode(nil), do: ""
  def encode(atom) when is_atom(atom), do: Atom.to_string(atom)

  @doc """
  Pretty-print for terminal display.

  ## Examples

      iex> result = RShell.EnvJSON.format(%{"host" => "localhost"})
      iex> String.contains?(result, "host")
      true

      iex> RShell.EnvJSON.format("hello")
      "hello"
  """
  @spec format(term()) :: String.t()
  def format(value) when is_binary(value), do: value
  def format(value) when is_map(value), do: Jason.encode!(value, pretty: true)
  def format(value) when is_list(value) do
    if is_charlist?(value) do
      List.to_string(value)
    else
      Jason.encode!(value, pretty: true)
    end
  end
  def format(value), do: encode(value)

  # Check if list is a charlist (all integers in valid codepoint range)
  # Must be non-empty and all elements integers in valid range
  defp is_charlist?([]), do: false
  defp is_charlist?(list) when is_list(list) do
    # Only treat as charlist if it looks like printable ASCII or valid UTF-8
    # This prevents [1,2,3] from being treated as charlist
    case list do
      [c | _] when is_integer(c) and c >= 32 and c <= 126 ->
        # Starts with printable ASCII, check all
        Enum.all?(list, &(is_integer(&1) and &1 >= 0 and &1 <= 1114111))
      _ ->
        false
    end
  end
  defp is_charlist?(_), do: false
end
