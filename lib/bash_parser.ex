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
        nif_file = 'priv/native/librshell_bash_parser'
        cond do
          File.exists?(nif_file <> ".so") -> :erlang.load_nif(nif_file, 0)
          File.exists?(nif_file <> ".dylib") -> :erlang.load_nif(nif_file, 0)
          File.exists?(nif_file <> ".dll") -> :erlang.load_nif(nif_file, 0)
          true -> :ok
        end
    end
  end

  # When your NIF is loaded, it will override this function.
  @doc """
  Parse a Bash script string into an AST represented as a map.

  Returns `{:ok, ast_map}` on success or `{:error, reason}` on failure.
  """
  def parse_bash(_content) do
    :erlang.nif_error(:nif_not_loaded)
  end
end
