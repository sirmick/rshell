defmodule RShell.Builtins.Utils do
  @moduledoc """
  Shared utility functions for builtin commands.

  Provides common helpers for:
  - Stream creation
  - Type conversion (to_number, to_integer, to_string)
  - Output formatting
  """

  @doc """
  Convert text to Stream.

  Wraps text in a single-element list so Stream yields the text as one chunk.
  Empty strings become empty streams (not streams with one empty string).
  """
  def stream(""), do: Stream.concat([[]])
  def stream(text) when is_binary(text), do: Stream.concat([[text]])

  @doc """
  Convert a value to a number (integer or float).

  ## Examples

      iex> RShell.Builtins.Utils.to_number(42)
      42

      iex> RShell.Builtins.Utils.to_number("3.14")
      3.14

      iex> RShell.Builtins.Utils.to_number(true)
      1
  """
  def to_number(value) when is_integer(value), do: value
  def to_number(value) when is_float(value), do: value

  def to_number(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} ->
        int

      _ ->
        case Float.parse(value) do
          {float, ""} -> float
          _ -> 0
        end
    end
  end

  def to_number(true), do: 1
  def to_number(false), do: 0
  def to_number(_), do: 0

  @doc """
  Convert a value to an integer.

  Floats are truncated, strings are parsed.
  """
  def to_integer(value) when is_integer(value), do: value
  def to_integer(value) when is_float(value), do: trunc(value)

  def to_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} ->
        int

      _ ->
        case Float.parse(value) do
          {float, ""} -> trunc(float)
          _ -> 0
        end
    end
  end

  def to_integer(true), do: 1
  def to_integer(false), do: 0
  def to_integer(_), do: 0

  @doc """
  Convert a value to a string for display.

  Handles rich types (maps, lists, etc.) using EnvJSON formatting.
  """
  def to_string(arg) when is_binary(arg), do: arg
  def to_string(arg) when is_map(arg), do: RShell.EnvJSON.format(arg)

  def to_string(arg) when is_list(arg) do
    # Check if charlist
    if Enum.all?(arg, &(is_integer(&1) and &1 >= 32 and &1 <= 126)) do
      List.to_string(arg)
    else
      RShell.EnvJSON.format(arg)
    end
  end

  def to_string(arg) when is_integer(arg), do: Integer.to_string(arg)
  def to_string(arg) when is_float(arg), do: Float.to_string(arg)
  def to_string(true), do: "true"
  def to_string(false), do: "false"
  def to_string(nil), do: ""
  def to_string(atom) when is_atom(atom), do: Atom.to_string(atom)

  @doc """
  Format output for display - convert native term lists to strings.
  Handles streams by materializing them first, including nested streams.
  """
  def format_output([]), do: ""

  def format_output(%Stream{} = stream) do
    # Materialize stream and format recursively
    stream
    |> Enum.to_list()
    |> Enum.flat_map(&materialize_item/1)
    |> format_output()
  end

  def format_output(output) when is_list(output) do
    output
    |> Enum.flat_map(&materialize_item/1)  # Materialize nested streams/functions
    |> Enum.map(&term_to_string/1)
    |> Enum.join("")
  end

  def format_output(output) when is_binary(output), do: output
  def format_output(output), do: term_to_string(output)

  # Recursively materialize nested streams/functions
  defp materialize_item(%Stream{} = s), do: Enum.to_list(s) |> Enum.flat_map(&materialize_item/1)
  defp materialize_item(f) when is_function(f), do: []  # Skip raw stream functions
  defp materialize_item(item), do: [item]

  @doc """
  Convert a single term to string for display.
  """
  def term_to_string(term) when is_binary(term), do: term
  def term_to_string(term) when is_map(term), do: Jason.encode!(term)

  def term_to_string(term) when is_list(term) do
    # Check if it's a charlist
    if Enum.all?(term, &(is_integer(&1) and &1 >= 32 and &1 <= 126)) do
      List.to_string(term)
    else
      Jason.encode!(term)
    end
  end

  def term_to_string(term) when is_integer(term), do: Integer.to_string(term)
  def term_to_string(term) when is_float(term), do: Float.to_string(term)
  def term_to_string(true), do: "true"
  def term_to_string(false), do: "false"
  def term_to_string(nil), do: ""
  def term_to_string(atom) when is_atom(atom), do: Atom.to_string(atom)

  # Catch-all for unexpected types (like raw stream functions)
  # This should not happen in normal operation, but provides safety
  def term_to_string(term) when is_function(term), do: ""
  def term_to_string(%Stream{} = s), do: s |> Enum.to_list() |> Enum.map(&term_to_string/1) |> Enum.join("")
  def term_to_string(_unknown), do: ""
end
