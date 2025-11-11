defmodule RShell.IncrementalParser do
  @moduledoc """
  GenServer that manages incremental parsing state using Rust NIF.

  This server maintains a single parser resource and allows:
  - Appending fragments incrementally
  - Resetting state between parses
  - Broadcasting completed nodes via PubSub
  - Efficient reuse across multiple parse sessions

  ## Usage

      # Start the parser
      {:ok, pid} = RShell.IncrementalParser.start_link()

      # Parse incrementally
      {:ok, ast} = RShell.IncrementalParser.append_fragment(pid, "echo 'hello'\n")
      {:ok, ast} = RShell.IncrementalParser.append_fragment(pid, "echo 'world'\n")

      # Reset for new parse
      :ok = RShell.IncrementalParser.reset(pid)

      # Get current state
      {:ok, ast} = RShell.IncrementalParser.get_current_ast(pid)
  """

  use GenServer
  require Logger

  @default_buffer_size 10 * 1024 * 1024  # 10MB

  ## Client API

  @doc """
  Starts the incremental parser GenServer.

  ## Options

  - `:buffer_size` - Maximum buffer size in bytes (default: 10MB)
  - `:name` - Name to register the GenServer under
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    buffer_size = Keyword.get(opts, :buffer_size, @default_buffer_size)
    name = Keyword.get(opts, :name)

    if name do
      GenServer.start_link(__MODULE__, buffer_size, name: name)
    else
      GenServer.start_link(__MODULE__, buffer_size)
    end
  end

  @doc """
  Append a fragment to the accumulated input and parse incrementally.

  Returns `{:ok, ast}` with the parsed AST, or `{:error, reason}` on failure.
  """
  @spec append_fragment(GenServer.server(), String.t()) ::
    {:ok, map()} | {:error, map()}
  def append_fragment(server, fragment) do
    GenServer.call(server, {:append_fragment, fragment})
  end

  @doc """
  Reset the parser state, clearing accumulated input and parse tree.

  This is useful between parse sessions or in test setups.
  """
  @spec reset(GenServer.server()) :: :ok
  def reset(server) do
    GenServer.call(server, :reset)
  end

  @doc """
  Signal that streaming input is complete.

  This is a semantic marker - it doesn't change parsing behavior but
  may trigger final processing or notifications.
  """
  @spec stream_end(GenServer.server()) :: :ok
  def stream_end(server) do
    GenServer.call(server, :stream_end)
  end

  @doc """
  Get the current AST without reparsing.

  Returns the last parsed AST, or `{:error, reason}` if no parse has occurred.
  """
  @spec get_current_ast(GenServer.server()) :: {:ok, map()} | {:error, map()}
  def get_current_ast(server) do
    GenServer.call(server, :get_current_ast)
  end

  @doc """
  Check if the current parse tree has errors.
  """
  @spec has_errors?(GenServer.server()) :: boolean()
  def has_errors?(server) do
    GenServer.call(server, :has_errors)
  end

  @doc """
  Get the size of accumulated input in bytes.
  """
  @spec get_buffer_size(GenServer.server()) :: non_neg_integer()
  def get_buffer_size(server) do
    GenServer.call(server, :get_buffer_size)
  end

  @doc """
  Get the accumulated input content.
  """
  @spec get_accumulated_input(GenServer.server()) :: String.t()
  def get_accumulated_input(server) do
    GenServer.call(server, :get_accumulated_input)
  end

  ## Server Callbacks

  @impl true
  def init(buffer_size) do
    case BashParser.new_parser_with_size(buffer_size) do
      {:ok, resource} ->
        Logger.debug("IncrementalParser started with buffer_size=#{buffer_size}")
        {:ok, %{resource: resource, buffer_size: buffer_size}}

      error ->
        Logger.error("Failed to create parser resource: #{inspect(error)}")
        {:stop, :parser_init_failed}
    end
  end

  @impl true
  def handle_call({:append_fragment, fragment}, _from, state) do
    case BashParser.parse_incremental(state.resource, fragment) do
      {:ok, ast} = result ->
        # TODO: Broadcast via PubSub when implemented
        # broadcast_nodes(ast)
        {:reply, result, state}

      {:error, _reason} = error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call(:reset, _from, state) do
    :ok = BashParser.reset_parser(state.resource)
    Logger.debug("Parser state reset")
    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:stream_end, _from, state) do
    Logger.debug("Stream end signaled")
    # TODO: Trigger final processing or notifications
    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:get_current_ast, _from, state) do
    result = BashParser.get_current_ast(state.resource)
    {:reply, result, state}
  end

  @impl true
  def handle_call(:has_errors, _from, state) do
    result = BashParser.has_errors(state.resource)
    {:reply, result, state}
  end

  @impl true
  def handle_call(:get_buffer_size, _from, state) do
    result = BashParser.get_buffer_size(state.resource)
    {:reply, result, state}
  end

  @impl true
  def handle_call(:get_accumulated_input, _from, state) do
    result = BashParser.get_accumulated_input(state.resource)
    {:reply, result, state}
  end

  ## Private Helpers

  # TODO: Implement PubSub broadcasting
  # defp broadcast_nodes(ast) do
  #   # Extract completed nodes and broadcast
  #   # Phoenix.PubSub.broadcast(RShell.PubSub, "parser:nodes", {:node_completed, node})
  # end
end
