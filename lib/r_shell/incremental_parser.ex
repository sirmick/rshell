defmodule RShell.IncrementalParser do
  @moduledoc """
  GenServer that manages incremental parsing state using Rust NIF.

  This server maintains a single parser resource and allows:
  - Appending fragments incrementally
  - Resetting state between parses
  - Broadcasting AST updates and executable nodes via PubSub
  - Efficient reuse across multiple parse sessions

  ## Usage

      # Start the parser with a session ID
      {:ok, pid} = RShell.IncrementalParser.start_link(session_id: "my_session")

      # Parse incrementally (automatically broadcasts to PubSub)
      {:ok, ast} = RShell.IncrementalParser.append_fragment(pid, "echo 'hello'\n")
      {:ok, ast} = RShell.IncrementalParser.append_fragment(pid, "echo 'world'\n")

      # Reset for new parse
      :ok = RShell.IncrementalParser.reset(pid)

      # Get current state
      {:ok, ast} = RShell.IncrementalParser.get_current_ast(pid)
  """

  use GenServer
  require Logger

  alias RShell.PubSub
  alias BashParser.AST.Types

  @default_buffer_size 10 * 1024 * 1024  # 10MB

  ## Client API

  @doc """
  Starts the incremental parser GenServer.

  ## Options

  - `:session_id` - Session ID for PubSub topic isolation (required)
  - `:buffer_size` - Maximum buffer size in bytes (default: 10MB)
  - `:name` - Name to register the GenServer under
  - `:broadcast` - Enable/disable PubSub broadcasting (default: true)
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    session_id = Keyword.get(opts, :session_id)
    buffer_size = Keyword.get(opts, :buffer_size, @default_buffer_size)
    broadcast = Keyword.get(opts, :broadcast, true)
    name = Keyword.get(opts, :name)

    init_arg = %{
      session_id: session_id,
      buffer_size: buffer_size,
      broadcast: broadcast
    }

    if name do
      GenServer.start_link(__MODULE__, init_arg, name: name)
    else
      GenServer.start_link(__MODULE__, init_arg)
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

  @doc """
  Get the parser resource (for use with ErrorClassifier).
  """
  @spec get_parser_resource(GenServer.server()) :: reference()
  def get_parser_resource(server) do
    GenServer.call(server, :get_parser_resource)
  end

  ## Server Callbacks

  @impl true
  def init(%{session_id: session_id, buffer_size: buffer_size, broadcast: broadcast}) do
    case BashParser.new_parser_with_size(buffer_size) do
      {:ok, resource} ->
        Logger.debug("IncrementalParser started for session=#{inspect(session_id)} buffer_size=#{buffer_size}")
        {:ok, %{
          resource: resource,
          buffer_size: buffer_size,
          session_id: session_id,
          broadcast: broadcast,
          command_count: 0,
          last_executable_row: -1
        }}

      error ->
        Logger.error("Failed to create parser resource: #{inspect(error)}")
        {:stop, :parser_init_failed}
    end
  end

  @impl true
  def handle_call({:append_fragment, fragment}, _from, state) do
    case BashParser.parse_incremental(state.resource, fragment) do
      {:ok, ast_map} ->
        # Convert to typed struct
        typed_ast = Types.from_map(ast_map)

        # Broadcast typed AST update
        if state.broadcast && state.session_id do
          broadcast_ast_update(state.session_id, typed_ast)
        end

        # Check for executable nodes and broadcast
        new_state = if state.broadcast && state.session_id do
          check_and_broadcast_executable_nodes(typed_ast, ast_map, state)
        else
          state
        end

        {:reply, {:ok, typed_ast}, new_state}

      {:error, _reason} = error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call(:reset, _from, state) do
    :ok = BashParser.reset_parser(state.resource)
    Logger.debug("Parser state reset for session=#{inspect(state.session_id)}")
    # Reset command tracking
    new_state = %{state | command_count: 0, last_executable_row: -1}
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:stream_end, _from, state) do
    Logger.debug("Stream end signaled")
    # TODO: Trigger final processing or notifications
    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:get_current_ast, _from, state) do
    case BashParser.get_current_ast(state.resource) do
      {:ok, ast_map} ->
        typed_ast = Types.from_map(ast_map)
        {:reply, {:ok, typed_ast}, state}
      error ->
        {:reply, error, state}
    end
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

  @impl true
  def handle_call(:get_parser_resource, _from, state) do
    {:reply, state.resource, state}
  end

  ## Private Helpers

  defp broadcast_ast_update(session_id, typed_ast) do
    PubSub.broadcast(session_id, :ast, {:ast_updated, typed_ast})
  end

  defp check_and_broadcast_executable_nodes(typed_ast, ast_map, state) do
    # Check if tree has errors - if so, nothing is executable yet
    has_errors = BashParser.has_errors(state.resource)

    if has_errors do
      # Tree has errors (incomplete structures, syntax errors, etc.)
      # Don't broadcast anything as executable
      state
    else
      # Tree is error-free, check for new executable nodes
      # Use ast_map for position info, typed structs for type checking
      children_maps = Map.get(ast_map, "children", [])
      children_typed = case typed_ast do
        %{children: children} when is_list(children) -> children
        _ -> []
      end

      accumulated_input = BashParser.get_accumulated_input(state.resource)

      # Zip together maps and typed structs for processing
      children_pairs = Enum.zip(children_maps, children_typed)

      # Find executable nodes that are:
      # 1. Valid node type
      # 2. After the last executable row we've seen
      # 3. Ends with newline (complete line)
      # 4. No ERROR nodes in subtree
      executable_pairs =
        children_pairs
        |> Enum.filter(fn {_map, typed} -> is_executable_node?(typed) end)
        |> Enum.filter(fn {map, _typed} ->
          end_row = Map.get(map, "end_row", -1)
          end_row > state.last_executable_row
        end)
        |> Enum.filter(fn {map, _typed} ->
          is_node_complete?(map, accumulated_input)
        end)
        |> Enum.sort_by(fn {map, _typed} -> Map.get(map, "end_row", 0) end)

      # Broadcast each new executable node (typed struct)
      new_state = Enum.reduce(executable_pairs, state, fn {map, typed}, acc_state ->
        command_count = acc_state.command_count + 1
        end_row = Map.get(map, "end_row", -1)

        Logger.debug("Broadcasting executable node #{command_count} at row #{end_row}")
        PubSub.broadcast(acc_state.session_id, :executable, {:executable_node, typed, command_count})

        %{acc_state |
          command_count: command_count,
          last_executable_row: end_row
        }
      end)

      new_state
    end
  end

  defp is_node_complete?(node, accumulated_input) do
    # Get the node's position in the input
    end_row = Map.get(node, "end_row", -1)
    end_col = Map.get(node, "end_col", -1)

    # Split input into lines
    lines = String.split(accumulated_input, "\n", parts: :infinity)

    # Check if there's content after the node on the same line or next line
    cond do
      end_row < 0 || end_col < 0 ->
        false

      end_row >= length(lines) ->
        false

      # Check if the line after the node's end is present (newline exists)
      end_row + 1 < length(lines) ->
        true

      # If we're on the last line, check if input ends with newline
      end_row + 1 == length(lines) ->
        String.ends_with?(accumulated_input, "\n")

      true ->
        false
    end
  end

  defp is_executable_node?(typed_node) do
    # A node is executable if it's one of the executable types
    # Pattern match on struct types instead of string comparison
    case typed_node do
      %Types.Command{} -> true
      %Types.Pipeline{} -> true
      %Types.List{} -> true
      %Types.Subshell{} -> true
      %Types.CompoundStatement{} -> true
      %Types.ForStatement{} -> true
      %Types.WhileStatement{} -> true
      %Types.IfStatement{} -> true
      %Types.CaseStatement{} -> true
      %Types.FunctionDefinition{} -> true
      %Types.DeclarationCommand{} -> true
      %Types.UnsetCommand{} -> true
      %Types.TestCommand{} -> true
      %Types.CStyleForStatement{} -> true
      _ -> false
    end
  end
end
