defmodule RShell.Grammar do
  @moduledoc """
  RShell parser using tree-sitter-rshell grammar.

  This module provides NIF functions for parsing RShell scripts incrementally.
  It replaces the old BashParser module with RShell-specific functionality.
  """

  use Rustler,
    otp_app: :rshell,
    crate: "rshell_grammar",
    path: "native/RShell.Grammar"

  # NIF functions - will be replaced by Rust implementations
  def new_parser(), do: :erlang.nif_error(:nif_not_loaded)
  def new_parser_with_size(_size), do: :erlang.nif_error(:nif_not_loaded)
  def parse_incremental(_resource, _fragment), do: :erlang.nif_error(:nif_not_loaded)
  def reset_parser(_resource), do: :erlang.nif_error(:nif_not_loaded)
  def get_current_ast(_resource), do: :erlang.nif_error(:nif_not_loaded)
  def has_errors(_resource), do: :erlang.nif_error(:nif_not_loaded)
  def get_buffer_size(_resource), do: :erlang.nif_error(:nif_not_loaded)
  def get_accumulated_input(_resource), do: :erlang.nif_error(:nif_not_loaded)
end
