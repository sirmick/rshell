defmodule BashParser do
  @moduledoc """
  BashParser provides Elixir bindings for parsing Bash scripts using tree-sitter.

  This module provides low-level functions to parse Bash scripts and convert them
  to Elixir data structures.
  """

  @on_load :load_nif
  def load_nif do
    nif_file = Application.app_dir(:rshell, ["priv", "native", "librshell_bash_parser"])

    cond do
      File.exists?(nif_file <> ".so") ->
        :erlang.load_nif(String.to_charlist(nif_file), 0)

      File.exists?(nif_file <> ".dylib") ->
        :erlang.load_nif(String.to_charlist(nif_file), 0)

      File.exists?(nif_file <> ".dll") ->
        :erlang.load_nif(String.to_charlist(nif_file), 0)

      true ->
        # For development, try relative path
        nif_file = ~c"priv/native/librshell_bash_parser"

        cond do
          File.exists?(to_string(nif_file) <> ".so") -> :erlang.load_nif(nif_file, 0)
          File.exists?(to_string(nif_file) <> ".dylib") -> :erlang.load_nif(nif_file, 0)
          File.exists?(to_string(nif_file) <> ".dll") -> :erlang.load_nif(nif_file, 0)
          true -> :ok
        end
    end
  end

  # When your NIF is loaded, it will override these functions.

  @doc """
  Parse a Bash script string into an AST represented as a map.

  Returns `{:ok, ast_map}` on success or `{:error, reason}` on failure.
  """
  def parse_bash(_content) do
    :erlang.nif_error(:nif_not_loaded)
  end

  @doc """
  Create a new parser resource for incremental parsing.

  Returns `{:ok, resource}` on success.
  """
  def new_parser do
    :erlang.nif_error(:nif_not_loaded)
  end

  @doc """
  Create a new parser resource with custom buffer size.

  Returns `{:ok, resource}` on success.
  """
  def new_parser_with_size(_max_buffer_size) do
    :erlang.nif_error(:nif_not_loaded)
  end

  @doc """
  Parse incrementally by appending a fragment.

  Returns `{:ok, ast}` or `{:error, reason}`.
  """
  def parse_incremental(_resource, _fragment) do
    :erlang.nif_error(:nif_not_loaded)
  end

  @doc """
  Reset the parser state (clear accumulated input and old tree).

  Returns `:ok`.
  """
  def reset_parser(_resource) do
    :erlang.nif_error(:nif_not_loaded)
  end

  @doc """
  Get the current AST without parsing.

  Returns `{:ok, ast}` or `{:error, reason}`.
  """
  def get_current_ast(_resource) do
    :erlang.nif_error(:nif_not_loaded)
  end

  @doc """
  Check if current tree has errors.

  Returns `true` or `false`.
  """
  def has_errors(_resource) do
    :erlang.nif_error(:nif_not_loaded)
  end

  @doc """
  Get accumulated input size.

  Returns the size in bytes.
  """
  def get_buffer_size(_resource) do
    :erlang.nif_error(:nif_not_loaded)
  end

  @doc """
  Get accumulated input content.

  Returns the accumulated string.
  """
  def get_accumulated_input(_resource) do
    :erlang.nif_error(:nif_not_loaded)
  end
end
