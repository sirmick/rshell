defmodule RShell.StreamParser do
  @moduledoc """
  **TEST-ONLY MODULE** - Synchronous wrapper around IncrementalParser GenServer.

  ⚠️ **WARNING**: This module is designed exclusively for test environments.
  Do NOT use in production code. Use `RShell.IncrementalParser` directly instead.

  This module provides a simple interface that automatically:
  - Starts a named GenServer on first use (or reuses existing)
  - Resets the parser before each parse
  - Waits for results with timeout

  Perfect for unit tests that need fast, reliable parsing without
  managing GenServer lifecycle.

  ## Usage

      # Single fragment parse (auto-resets before parsing)
      {:ok, ast} = RShell.StreamParser.parse("echo 'hello'\\n")

      # Multi-fragment parse
      {:ok, ast} = RShell.StreamParser.parse_fragments([
        "echo 'hello'\\n",
        "echo 'world'\\n"
      ])

      # Custom timeout
      {:ok, ast} = RShell.StreamParser.parse("complex script", timeout: 10_000)
  """

  alias RShell.IncrementalParser

  @default_timeout 5_000
  @parser_name __MODULE__.Parser

  @doc """
  Parse a single fragment, automatically resetting the parser first.

  This ensures each parse starts fresh, making tests independent.

  ## Options

  - `:timeout` - Max time to wait for parse (default: 5000ms)
  - `:reset` - Whether to reset before parsing (default: true)
  """
  @spec parse(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def parse(fragment, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    should_reset = Keyword.get(opts, :reset, true)

    with {:ok, pid} <- ensure_parser_started(),
         :ok <- maybe_reset(pid, should_reset),
         {:ok, ast} <- IncrementalParser.append_fragment(pid, fragment) do
      {:ok, ast}
    end
  rescue
    e ->
      {:error, {:exception, e}}
  catch
    :exit, reason ->
      {:error, {:exit, reason}}
  end

  @doc """
  Parse multiple fragments in sequence.

  Automatically resets before the first fragment, then accumulates
  all fragments incrementally.

  Returns the final AST after all fragments are processed.

  ## Options

  - `:timeout` - Max time to wait for parse (default: 5000ms)
  """
  @spec parse_fragments([String.t()], keyword()) :: {:ok, map()} | {:error, term()}
  def parse_fragments(fragments, opts \\ []) when is_list(fragments) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)

    with {:ok, pid} <- ensure_parser_started(),
         :ok <- IncrementalParser.reset(pid),
         {:ok, ast} <- accumulate_fragments(pid, fragments) do
      {:ok, ast}
    end
  rescue
    e ->
      {:error, {:exception, e}}
  catch
    :exit, reason ->
      {:error, {:exit, reason}}
  end

  @doc """
  Get the named parser PID, or nil if not started.
  """
  @spec parser_pid() :: pid() | nil
  def parser_pid do
    Process.whereis(@parser_name)
  end

  @doc """
  Explicitly reset the parser state.

  Usually not needed since parse/1 auto-resets, but useful
  for manual control in some test scenarios.
  """
  @spec reset() :: :ok | {:error, term()}
  def reset do
    case parser_pid() do
      nil -> {:error, :not_started}
      pid -> IncrementalParser.reset(pid)
    end
  end

  @doc """
  Stop the parser GenServer.

  Usually not needed - the parser will be automatically stopped
  when the test process exits.
  """
  @spec stop() :: :ok
  def stop do
    case parser_pid() do
      nil -> :ok
      pid -> GenServer.stop(pid, :normal)
    end
  end

  ## Private Helpers

  # Ensure parser is started, or start it
  defp ensure_parser_started do
    case parser_pid() do
      nil ->
        # Start under calling process (not supervised)
        IncrementalParser.start_link(name: @parser_name)

      pid ->
        {:ok, pid}
    end
  end

  # Reset parser if requested
  defp maybe_reset(_pid, false), do: :ok
  defp maybe_reset(pid, true), do: IncrementalParser.reset(pid)

  # Accumulate fragments, returning final AST
  defp accumulate_fragments(_pid, []), do: {:error, :no_fragments}

  defp accumulate_fragments(pid, fragments) do
    Enum.reduce_while(fragments, {:ok, nil}, fn fragment, _acc ->
      case IncrementalParser.append_fragment(pid, fragment) do
        {:ok, ast} -> {:cont, {:ok, ast}}
        error -> {:halt, error}
      end
    end)
  end
end
