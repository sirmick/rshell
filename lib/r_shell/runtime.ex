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
    - `:mode` - Execution mode (:simulate | :capture | :real)
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

  @doc "Set execution mode"
  @spec set_mode(GenServer.server(), :simulate | :capture | :real) :: :ok
  def set_mode(server, mode) when mode in [:simulate, :capture, :real] do
    GenServer.call(server, {:set_mode, mode})
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    session_id = Keyword.fetch!(opts, :session_id)
    mode = Keyword.get(opts, :mode, :simulate)
    auto_execute = Keyword.get(opts, :auto_execute, true)
    env = Keyword.get(opts, :env, System.get_env())
    cwd = Keyword.get(opts, :cwd, System.get_env("PWD") || "/")

    # Subscribe to executable nodes from parser
    PubSub.subscribe(session_id, [:executable])

    context = %{
      mode: mode,
      env: env,
      cwd: cwd,
      exit_code: 0,
      command_count: 0,
      output: [],
      errors: []
    }

    Logger.debug("Runtime started: session_id=#{session_id}, mode=#{mode}")

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

  @impl true
  def handle_call({:set_mode, mode}, _from, state) do
    new_context = %{state.context | mode: mode}
    {:reply, :ok, %{state | context: new_context}}
  end

  # Handle executable nodes from parser
  @impl true
  def handle_info({:executable_node, node, _command_count}, state) do
    if state.auto_execute do
      {_result, new_context} = execute_node_internal(node, state.context, state.session_id)
      {:noreply, %{state | context: new_context}}
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

  # Simple execution logic (can be enhanced later)
  # Pattern match on typed structs instead of string types
  defp simple_execute(node, context, session_id) do
    new_context = %{context | command_count: context.command_count + 1}

    case node do
      %Types.Command{} = cmd ->
        execute_command(cmd, new_context, session_id)

      %Types.DeclarationCommand{} = decl ->
        execute_declaration(decl, new_context, session_id)

      %Types.Pipeline{} = pipe ->
        execute_pipeline(pipe, new_context, session_id)

      %Types.List{} = list ->
        execute_list(list, new_context, session_id)

      %Types.IfStatement{} = if_stmt ->
        execute_if_statement(if_stmt, new_context, session_id)

      %Types.ForStatement{} = for_stmt ->
        execute_for_statement(for_stmt, new_context, session_id)

      %Types.WhileStatement{} = while_stmt ->
        execute_while_statement(while_stmt, new_context, session_id)

      %Types.CaseStatement{} = case_stmt ->
        execute_case_statement(case_stmt, new_context, session_id)

      %Types.FunctionDefinition{} = func_def ->
        execute_function_definition(func_def, new_context, session_id)

      other ->
        # For other node types, just log and return
        node_type = other.__struct__ |> Module.split() |> List.last()
        text = Map.get(other.source_info, :text, "")
        Logger.debug("Executing #{node_type}: #{inspect(text)}")
        new_context
    end
  end

  defp execute_command(%Types.Command{source_info: source_info} = cmd, context, session_id) do
    text = source_info.text || ""

    # Extract command name and arguments
    case extract_command_parts(cmd) do
      {:ok, command_name, args} ->
        # Check if it's a builtin command
        if Builtins.is_builtin?(command_name) do
          execute_builtin(command_name, args, "", context, session_id)
        else
          # Execute as external command
          execute_external_command(text, context, session_id)
        end

      {:error, _reason} ->
        # Couldn't parse command, fall back to text-based execution
        execute_external_command(text, context, session_id)
    end
  end

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
  defp execute_external_command(text, context, session_id) do
    # Simple command execution
    case context.mode do
      :simulate ->
        # Just simulate - broadcast what would happen
        output = "[SIMULATED] #{text}"
        PubSub.broadcast(session_id, :output, {:stdout, output <> "\n"})
        %{context | output: [output | context.output], exit_code: 0}

      :capture ->
        # Capture output without actually running
        output = "[CAPTURED] #{text}"
        PubSub.broadcast(session_id, :output, {:stdout, output <> "\n"})
        %{context | output: [output | context.output], exit_code: 0}

      :real ->
        # Actually execute (TODO: implement real execution)
        output = "[WOULD EXECUTE] #{text}"
        PubSub.broadcast(session_id, :output, {:stdout, output <> "\n"})
        %{context | output: [output | context.output], exit_code: 0}
    end
  end

  # Extract command name and arguments from Command AST node
  defp extract_command_parts(%Types.Command{name: name_node, argument: args_nodes}) do
    with {:ok, command_name} <- extract_command_name(name_node),
         {:ok, args} <- extract_arguments(args_nodes) do
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

  # Extract arguments from argument nodes
  defp extract_arguments(nil), do: {:ok, []}
  defp extract_arguments([]), do: {:ok, []}
  
  defp extract_arguments(args_nodes) when is_list(args_nodes) do
    args =
      args_nodes
      |> Enum.map(&extract_text_from_node/1)
      |> Enum.reject(&(&1 == ""))
    
    {:ok, args}
  end

  # Extract text from any node by traversing the typed structure
  defp extract_text_from_node(%Types.String{children: children}) when is_list(children) do
    # String nodes contain StringContent or expansions
    children
    |> Enum.map(&extract_text_from_node/1)
    |> Enum.join("")
  end

  defp extract_text_from_node(%Types.StringContent{source_info: %{text: text}}), do: text

  defp extract_text_from_node(%Types.SimpleExpansion{children: children}) when is_list(children) do
    # For now, return the expansion text as-is (e.g., "$VAR")
    # Later we can expand variables from context
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

  # Materialize output - convert streams/enumerables to strings
  defp materialize_output(output) when is_binary(output), do: output
  
  defp materialize_output(output) when is_list(output) do
    output
    |> Enum.map(&to_string/1)
    |> Enum.join("")
  end

  defp materialize_output(%Stream{} = stream) do
    stream
    |> Enum.map(&to_string/1)
    |> Enum.join("")
  end

  defp materialize_output(output) do
    # Try to enumerate it
    try do
      output
      |> Enum.map(&to_string/1)
      |> Enum.join("")
    rescue
      Protocol.UndefinedError ->
        # Not enumerable, convert to string
        to_string(output)
    end
  end

  defp execute_declaration(%Types.DeclarationCommand{source_info: source_info}, context, session_id) do
    text = source_info.text || ""

    # Try to parse variable assignment (export FOO=bar)
    case Regex.run(~r/export\s+([A-Za-z_][A-Za-z0-9_]*)=(.+)/, text) do
      [_, name, value] ->
        # Remove quotes if present
        clean_value = String.trim(value, "\"'")

        new_env = Map.put(context.env, name, clean_value)

        # Broadcast variable set
        PubSub.broadcast(session_id, :context, {:variable_set, %{
          name: name,
          value: clean_value
        }})

        %{context | env: new_env, exit_code: 0}

      nil ->
        Logger.debug("Could not parse declaration: #{text}")
        context
    end
  end

  defp execute_pipeline(%Types.Pipeline{source_info: source_info}, context, session_id) do
    text = source_info.text || ""

    output = "[PIPELINE] #{text}"
    PubSub.broadcast(session_id, :output, {:stdout, output <> "\n"})

    %{context | output: [output | context.output], exit_code: 0}
  end

  defp execute_list(%Types.List{source_info: source_info}, context, session_id) do
    text = source_info.text || ""
    output = "[LIST] #{text}"
    PubSub.broadcast(session_id, :output, {:stdout, output <> "\n"})
    %{context | output: [output | context.output], exit_code: 0}
  end

  defp execute_if_statement(%Types.IfStatement{source_info: source_info}, context, session_id) do
    text = source_info.text || ""
    output = "[IF_STATEMENT] #{text}"
    PubSub.broadcast(session_id, :output, {:stdout, output <> "\n"})
    %{context | output: [output | context.output], exit_code: 0}
  end

  defp execute_for_statement(%Types.ForStatement{source_info: source_info}, context, session_id) do
    text = source_info.text || ""
    output = "[FOR_STATEMENT] #{text}"
    PubSub.broadcast(session_id, :output, {:stdout, output <> "\n"})
    %{context | output: [output | context.output], exit_code: 0}
  end

  defp execute_while_statement(%Types.WhileStatement{source_info: source_info}, context, session_id) do
    text = source_info.text || ""
    output = "[WHILE_STATEMENT] #{text}"
    PubSub.broadcast(session_id, :output, {:stdout, output <> "\n"})
    %{context | output: [output | context.output], exit_code: 0}
  end

  defp execute_case_statement(%Types.CaseStatement{source_info: source_info}, context, session_id) do
    text = source_info.text || ""
    output = "[CASE_STATEMENT] #{text}"
    PubSub.broadcast(session_id, :output, {:stdout, output <> "\n"})
    %{context | output: [output | context.output], exit_code: 0}
  end

  defp execute_function_definition(%Types.FunctionDefinition{source_info: source_info}, context, session_id) do
    text = source_info.text || ""
    output = "[FUNCTION_DEFINITION] #{text}"
    PubSub.broadcast(session_id, :output, {:stdout, output <> "\n"})
    %{context | output: [output | context.output], exit_code: 0}
  end
end
