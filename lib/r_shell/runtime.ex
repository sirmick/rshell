defmodule RShell.Runtime do
  @moduledoc """
  Runtime execution engine for bash scripts.

  Subscribes to parser's executable_node events and executes them
  while maintaining execution context (variables, cwd, functions).

  ## Usage

      # Start runtime with auto-execution
      {:ok, runtime} = Runtime.start_link(
        session_id: "my_session",
        mode: :simulate,
        auto_execute: true
      )

      # Manual execution
      Runtime.execute_node(runtime, node)

      # Query context
      Runtime.get_variable(runtime, "FOO")
  """

  use GenServer
  require Logger

  alias RShell.PubSub
  alias RShell.Builtins
  alias BashParser.AST.Types

  # Client API

  @doc """
  Start the runtime GenServer.

  Options:
    - `:session_id` - Session identifier (required)
    - `:auto_execute` - Execute nodes as they arrive (default: true)
    - `:env` - Initial environment variables
    - `:cwd` - Initial working directory
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    _session_id = Keyword.fetch!(opts, :session_id)
    name = Keyword.get(opts, :name)

    if name do
      GenServer.start_link(__MODULE__, opts, name: name)
    else
      GenServer.start_link(__MODULE__, opts)
    end
  end

  @doc "Execute a single AST node"
  @spec execute_node(GenServer.server(), Types.t()) :: {:ok, map()} | {:error, term()}
  def execute_node(server, node) do
    GenServer.call(server, {:execute_node, node})
  end

  @doc "Get current execution context"
  @spec get_context(GenServer.server()) :: map()
  def get_context(server) do
    GenServer.call(server, :get_context)
  end

  @doc "Get variable value"
  @spec get_variable(GenServer.server(), String.t()) :: String.t() | nil
  def get_variable(server, name) do
    GenServer.call(server, {:get_variable, name})
  end

  @doc "Get current working directory"
  @spec get_cwd(GenServer.server()) :: String.t()
  def get_cwd(server) do
    GenServer.call(server, :get_cwd)
  end

  @doc "Set current working directory"
  @spec set_cwd(GenServer.server(), String.t()) :: :ok
  def set_cwd(server, path) do
    GenServer.call(server, {:set_cwd, path})
  end


  # Server Callbacks

  @impl true
  def init(opts) do
    session_id = Keyword.fetch!(opts, :session_id)
    auto_execute = Keyword.get(opts, :auto_execute, true)
    env = Keyword.get(opts, :env, System.get_env())
    cwd = Keyword.get(opts, :cwd, System.get_env("PWD") || "/")

    # Subscribe to executable nodes from parser
    PubSub.subscribe(session_id, [:executable])

    context = %{
      env: env,
      cwd: cwd,
      exit_code: 0,
      command_count: 0,
      output: [],
      errors: []
    }

    Logger.debug("Runtime started: session_id=#{session_id}")

    {:ok, %{
      session_id: session_id,
      context: context,
      auto_execute: auto_execute
    }}
  end

  @impl true
  def handle_call({:execute_node, node}, _from, state) do
    {result, new_context} = execute_node_internal(node, state.context, state.session_id)
    {:reply, result, %{state | context: new_context}}
  end

  @impl true
  def handle_call(:get_context, _from, state) do
    {:reply, state.context, state}
  end

  @impl true
  def handle_call({:get_variable, name}, _from, state) do
    value = Map.get(state.context.env, name)
    {:reply, value, state}
  end

  @impl true
  def handle_call(:get_cwd, _from, state) do
    {:reply, state.context.cwd, state}
  end

  @impl true
  def handle_call({:set_cwd, path}, _from, state) do
    old_cwd = state.context.cwd
    new_context = %{state.context | cwd: path}

    # Broadcast context change
    PubSub.broadcast(state.session_id, :context, {:cwd_changed, %{
      old: old_cwd,
      new: path
    }})

    {:reply, :ok, %{state | context: new_context}}
  end


  # Handle executable nodes from parser (with command count)
  @impl true
  def handle_info({:executable_node, node, _count}, state) do
    if state.auto_execute do
      try do
        {_result, new_context} = execute_node_internal(node, state.context, state.session_id)
        {:noreply, %{state | context: new_context}}
      rescue
        e in RuntimeError ->
          # Broadcast execution failure
          PubSub.broadcast(state.session_id, :runtime, {:execution_failed, %{
            reason: "NotImplementedError",
            message: Exception.message(e),
            node_type: node.__struct__ |> Module.split() |> List.last()
          }})
          {:noreply, state}

        e ->
          # Other errors
          PubSub.broadcast(state.session_id, :runtime, {:execution_failed, %{
            reason: e.__struct__ |> Module.split() |> List.last(),
            message: Exception.message(e)
          }})
          {:noreply, state}
      end
    else
      {:noreply, state}
    end
  end

  # Private Helpers

  defp execute_node_internal(node, context, session_id) do
    # Broadcast execution start
    PubSub.broadcast(session_id, :runtime, {:execution_started, %{
      node: node,
      timestamp: DateTime.utc_now()
    }})

    start_time = System.monotonic_time(:microsecond)

    # Execute node (simple simulation for now)
    new_context = simple_execute(node, context, session_id)

    duration = System.monotonic_time(:microsecond) - start_time

    # Broadcast execution complete
    PubSub.broadcast(session_id, :runtime, {:execution_completed, %{
      node: node,
      exit_code: new_context.exit_code,
      duration_us: duration,
      timestamp: DateTime.utc_now()
    }})

    {{:ok, new_context}, new_context}
  end

  # Execute AST nodes
  defp simple_execute(node, context, session_id) do
    new_context = %{context | command_count: context.command_count + 1}

    case node do
      %Types.Command{} = cmd ->
        execute_command(cmd, new_context, session_id)

      # Unimplemented node types
      %Types.DeclarationCommand{} ->
        raise "DeclarationCommand execution not yet implemented"

      %Types.Pipeline{} ->
        raise "Pipeline execution not yet implemented"

      %Types.List{} ->
        raise "List execution not yet implemented"

      %Types.IfStatement{} ->
        raise "IfStatement execution not yet implemented"

      %Types.ForStatement{} ->
        raise "ForStatement execution not yet implemented"

      %Types.WhileStatement{} ->
        raise "WhileStatement execution not yet implemented"

      %Types.CaseStatement{} ->
        raise "CaseStatement execution not yet implemented"

      %Types.FunctionDefinition{} ->
        raise "FunctionDefinition execution not yet implemented"

      other ->
        node_type = other.__struct__ |> Module.split() |> List.last()
        raise "Execution not implemented for #{node_type}"
    end
  end

  defp execute_command(%Types.Command{source_info: source_info} = cmd, context, session_id) do
    text = source_info.text || ""

    # Extract command name and arguments with context for variable expansion
    case extract_command_parts(cmd, context) do
      {:ok, command_name, args} ->
        # Check if it's a builtin command
        if Builtins.is_builtin?(command_name) do
          # Pass native args directly to builtins
          execute_builtin(command_name, args, "", context, session_id)
        else
          # For external commands, convert native values to JSON
          _json_args = Enum.map(args, &convert_to_string/1)
          # TODO: Use json_args when implementing external command execution
          # Execute as external command
          execute_external_command(text, context, session_id)
        end

      {:error, _reason} ->
        # Couldn't parse command, fall back to text-based execution
        execute_external_command(text, context, session_id)
    end
  end

  # Convert native values to strings for external commands
  defp convert_to_string(value) when is_binary(value), do: value
  defp convert_to_string(value) when is_map(value), do: Jason.encode!(value)
  defp convert_to_string(value) when is_list(value) do
    # Check if charlist
    if Enum.all?(value, &(is_integer(&1) and &1 >= 32 and &1 <= 126)) do
      List.to_string(value)
    else
      Jason.encode!(value)
    end
  end
  defp convert_to_string(value) when is_integer(value), do: Integer.to_string(value)
  defp convert_to_string(value) when is_float(value), do: Float.to_string(value)
  defp convert_to_string(true), do: "true"
  defp convert_to_string(false), do: "false"
  defp convert_to_string(nil), do: ""
  defp convert_to_string(atom) when is_atom(atom), do: Atom.to_string(atom)

  # Execute a builtin command
  defp execute_builtin(name, args, stdin, context, session_id) do
    case Builtins.execute(name, args, stdin, context) do
      {new_context, stdout, stderr, exit_code} ->
        # Materialize output if it's a stream
        stdout_text = materialize_output(stdout)
        stderr_text = materialize_output(stderr)

        # Broadcast output
        if stdout_text != "" do
          PubSub.broadcast(session_id, :output, {:stdout, stdout_text})
        end

        if stderr_text != "" do
          PubSub.broadcast(session_id, :output, {:stderr, stderr_text})
        end

        # Update context with execution results
        %{new_context |
          output: [stdout_text | context.output],
          errors: if(stderr_text != "", do: [stderr_text | context.errors], else: context.errors),
          exit_code: exit_code
        }

      {:error, :not_a_builtin} ->
        # Should not happen since we checked is_builtin?, but handle gracefully
        Logger.warning("Builtin '#{name}' not found despite passing is_builtin? check")
        execute_external_command("#{name} #{Enum.join(args, " ")}", context, session_id)
    end
  end

  # Execute an external command (non-builtin)
  defp execute_external_command(_text, _context, _session_id) do
    raise "External command execution not yet implemented"
  end

  # Extract command name and arguments from Command AST node with context
  defp extract_command_parts(%Types.Command{name: name_node, argument: args_nodes}, context) do
    with {:ok, command_name} <- extract_command_name(name_node),
         {:ok, args} <- extract_arguments(args_nodes, context) do
      {:ok, command_name, args}
    else
      error -> error
    end
  end

  # Extract command name from CommandName node by traversing children
  defp extract_command_name(%Types.CommandName{children: children}) when is_list(children) do
    # CommandName contains Word children
    name =
      children
      |> Enum.map(&extract_text_from_node/1)
      |> Enum.join("")

    {:ok, name}
  end

  defp extract_command_name(%Types.Word{source_info: %{text: text}}) when is_binary(text) do
    {:ok, text}
  end

  defp extract_command_name(%{source_info: %{text: text}}) when is_binary(text) do
    {:ok, text}
  end

  defp extract_command_name(_), do: {:error, :unknown_name_type}

  # Extract arguments from argument nodes with context for variable expansion
  defp extract_arguments(nil, _context), do: {:ok, []}
  defp extract_arguments([], _context), do: {:ok, []}

  defp extract_arguments(args_nodes, context) when is_list(args_nodes) do
    args =
      args_nodes
      |> Enum.map(&extract_text_from_node(&1, context))
      |> Enum.reject(&(&1 == ""))

    {:ok, args}
  end

  # Extract text from any node by traversing the typed structure
  # All 2-arity versions (with context) grouped together
  defp extract_text_from_node(%Types.String{children: children}, context) when is_list(children) do
    # For String nodes, extract the content inside the quotes
    # This allows JSON values like '{"x":1}' to be parsed correctly
    children
    |> Enum.map(&extract_text_from_node(&1, context))
    |> Enum.map(&convert_to_string/1)
    |> Enum.join("")
  end

  defp extract_text_from_node(%Types.RawString{source_info: %{text: text}}, _context) when is_binary(text) do
    # RawString nodes (single quotes in bash) preserve everything literally
    # Strip the outer single quotes for JSON parsing: 'value' -> value
    if String.starts_with?(text, "'") and String.ends_with?(text, "'") and String.length(text) >= 2 do
      String.slice(text, 1..-2)
    else
      text
    end
  end

  defp extract_text_from_node(%Types.StringContent{source_info: %{text: text}}, _context), do: text

  defp extract_text_from_node(%Types.SimpleExpansion{children: children}, context) when is_list(children) do
    # Extract variable name
    var_name = children
      |> Enum.map(&extract_variable_name/1)
      |> Enum.join("")

    # Look up in context.env
    case Map.get(context.env || %{}, var_name) do
      nil ->
        # Undefined variable - return empty string (bash behavior)
        ""

      value ->
        # Return the native value (for builtins) or will be converted to JSON (for external)
        value
    end
  end

  defp extract_text_from_node(%Types.VariableName{source_info: %{text: text}}, _context), do: text

  defp extract_text_from_node(%Types.Word{source_info: %{text: text}}, _context), do: text

  defp extract_text_from_node(%Types.Concatenation{children: children}, context) when is_list(children) do
    children
    |> Enum.map(&extract_text_from_node(&1, context))
    |> Enum.map(&convert_to_string/1)  # Convert native values to strings for concatenation
    |> Enum.join("")
  end

  defp extract_text_from_node(%{source_info: %{text: text}}, _context) when is_binary(text), do: text

  defp extract_text_from_node(_, _context), do: ""

  # All 1-arity versions (without context) grouped together - fallbacks
  defp extract_text_from_node(%Types.String{children: children}) when is_list(children) do
    # For String nodes, extract the content inside the quotes
    children
    |> Enum.map(&extract_text_from_node/1)
    |> Enum.join("")
  end

  defp extract_text_from_node(%Types.RawString{source_info: %{text: text}}) when is_binary(text) do
    # RawString nodes (single quotes in bash) - strip outer quotes
    if String.starts_with?(text, "'") and String.ends_with?(text, "'") and String.length(text) >= 2 do
      String.slice(text, 1..-2)
    else
      text
    end
  end

  defp extract_text_from_node(%Types.StringContent{source_info: %{text: text}}), do: text

  defp extract_text_from_node(%Types.SimpleExpansion{children: children}) when is_list(children) do
    # Return the expansion text as-is (e.g., "$VAR")
    children
    |> Enum.map(&extract_text_from_node/1)
    |> Enum.join("")
    |> then(&"$#{&1}")
  end

  defp extract_text_from_node(%Types.VariableName{source_info: %{text: text}}), do: text

  defp extract_text_from_node(%Types.Word{source_info: %{text: text}}), do: text

  defp extract_text_from_node(%Types.Concatenation{children: children}) when is_list(children) do
    children
    |> Enum.map(&extract_text_from_node/1)
    |> Enum.join("")
  end

  defp extract_text_from_node(%{source_info: %{text: text}}) when is_binary(text), do: text

  defp extract_text_from_node(_), do: ""

  # Extract variable name from VariableName node (helper for variable expansion)
  defp extract_variable_name(%Types.VariableName{source_info: %{text: text}}), do: text
  defp extract_variable_name(_), do: ""

  # Materialize output - convert Stream to string
  defp materialize_output(stream) when is_function(stream) do
    stream
    |> Enum.map(&to_string/1)
    |> Enum.join("")
  end
end
