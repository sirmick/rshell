defmodule RShell.IncrementalParser do
  @moduledoc """
  GenServer that manages incremental parsing state using Rust NIF.

  This server maintains a single parser resource and allows:
  - Appending fragments incrementally
  - Resetting state between parses
  - Broadcasting AST updates and executable nodes via PubSub
  - Efficient reuse across multiple parse sessions

  ## PubSub Events

  Each call to `append_fragment/2` broadcasts one of the following:
  - `{:ast_incremental, metadata}` - Success, with incremental changes
    - `metadata.full_ast` - Complete accumulated AST
    - `metadata.changed_nodes` - Only the nodes that changed
    - `metadata.changed_ranges` - Byte ranges that changed
  - `{:parsing_failed, error}` - Parser returned an error
  - `{:parsing_crashed, error}` - Parser crashed (exception caught)

  Additionally, if the tree is error-free and contains executable nodes:
  - `{:executable_node, typed_node, count}` - Node ready for execution

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
    # Wrap entire parsing in try/catch to ensure we ALWAYS send a response
    try do
      case BashParser.parse_incremental(state.resource, fragment) do
        {:ok, ast_map} ->
          # Convert to typed struct
          typed_ast = Types.from_map(ast_map)

          # Extract changed nodes and ranges from NIF response
          changed_nodes_maps = Map.get(ast_map, "changed_nodes", [])
          changed_ranges = Map.get(ast_map, "changed_ranges", [])

          # Convert changed nodes to typed structs
          changed_nodes_typed = Enum.map(changed_nodes_maps, &Types.from_map/1)

          # Broadcast incremental AST update with metadata
          if state.broadcast && state.session_id do
            broadcast_incremental_ast_update(state.session_id, typed_ast, changed_nodes_typed, changed_ranges)
          end

          # Check for executable nodes and broadcast
          new_state = if state.broadcast && state.session_id do
            check_and_broadcast_executable_nodes(typed_ast, ast_map, state)
          else
            state
          end

          {:reply, {:ok, typed_ast}, new_state}

        {:error, _reason} = error ->
          # Parser returned error - broadcast failure
          if state.broadcast && state.session_id do
            PubSub.broadcast(state.session_id, :ast, {:parsing_failed, error})
          end
          {:reply, error, state}
      end
    rescue
      exception ->
        # Parser crashed - ALWAYS broadcast the error so clients don't timeout
        error_msg = %{
          reason: "parser_crash",
          exception: Exception.format(:error, exception, __STACKTRACE__),
          fragment_preview: String.slice(fragment, 0, 100)
        }

        Logger.error("Parser crashed: #{inspect(exception)}")

        if state.broadcast && state.session_id do
          PubSub.broadcast(state.session_id, :ast, {:parsing_crashed, error_msg})
        end

        {:reply, {:error, error_msg}, state}
    end
  end

  @impl true
  def handle_call(:reset, _from, state) do
    :ok = BashParser.reset_parser(state.resource)
    Logger.debug("Parser state reset for session=#{inspect(state.session_id)}")
    # Reset command count and last executable row
    {:reply, :ok, %{state | command_count: 0, last_executable_row: -1}}
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

  defp broadcast_incremental_ast_update(session_id, full_ast, changed_nodes, changed_ranges) do
    metadata = %{
      full_ast: full_ast,
      changed_nodes: changed_nodes,
      changed_ranges: changed_ranges
    }
    PubSub.broadcast(session_id, :ast, {:ast_incremental, metadata})
  end

  defp check_and_broadcast_executable_nodes(typed_ast, ast_map, state) do
    # Check if tree has errors - if so, nothing is executable yet
    has_errors = BashParser.has_errors(state.resource)

    Logger.debug("check_and_broadcast_executable_nodes: has_errors=#{has_errors}")

    if has_errors do
      # Tree has errors (incomplete structures, syntax errors, etc.)
      # Don't broadcast anything as executable
      Logger.debug("Tree has errors, skipping executable broadcast")
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
      # 2. Ends with newline (complete line)
      # 3. No ERROR nodes in subtree
      # 4. NEW: end_row > last_executable_row (not already broadcast)
      executable_pairs =
        children_pairs
        |> Enum.filter(fn {_map, typed} -> is_executable_node?(typed) end)
        |> Enum.filter(fn {map, _typed} ->
          is_node_complete?(map, accumulated_input)
        end)
        |> Enum.filter(fn {map, _typed} ->
          # Only broadcast nodes after the last executable row
          Map.get(map, "end_row", -1) > state.last_executable_row
        end)
        |> Enum.sort_by(fn {map, _typed} -> Map.get(map, "end_row", 0) end)

      # Broadcast each new executable node (typed struct) with incremented count
      {new_command_count, new_last_row} = Enum.reduce(executable_pairs, {state.command_count, state.last_executable_row}, fn {map, typed}, {count, _last_row} ->
        new_count = count + 1
        end_row = Map.get(map, "end_row", -1)
        PubSub.broadcast(state.session_id, :executable, {:executable_node, typed, new_count})
        {new_count, end_row}
      end)

      %{state | command_count: new_command_count, last_executable_row: new_last_row}
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
      %Types.VariableAssignment{} -> true  # Simple variable assignments like X=12
      %Types.UnsetCommand{} -> true
      %Types.TestCommand{} -> true
      %Types.CStyleForStatement{} -> true
      _ -> false
    end
  end
end
