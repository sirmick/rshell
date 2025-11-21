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
  alias BashParser.AST.RShellTypes, as: Types

  # Default variable attributes (reserved for future use)
  # @default_attributes %{
  #   readonly: false,
  #   exported: false
  # }

  # Client API

  @doc """
  Start the runtime GenServer.

  Options:
    - `:session_id` - Session identifier (required)
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

  @doc "Reset runtime context to initial state"
  @spec reset(GenServer.server()) :: :ok
  def reset(server) do
    GenServer.call(server, :reset)
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    session_id = Keyword.fetch!(opts, :session_id)
    env = Keyword.get(opts, :env, System.get_env())
    cwd = Keyword.get(opts, :cwd, System.get_env("PWD") || "/")

    # No longer subscribe to executable nodes - execution is synchronous via direct calls

    context = %{
      env: env,
      # Variable attributes metadata
      env_meta: %{},
      cwd: cwd,
      exit_code: 0,
      command_count: 0,
      # Only current command output (lists of native terms)
      last_output: %{stdout: [], stderr: []}
    }

    Logger.debug("Runtime started: session_id=#{session_id}")

    {:ok,
     %{
       session_id: session_id,
       context: context,
       # Store for reset
       initial_env: env,
       # Store for reset
       initial_cwd: cwd
     }}
  end

  @impl true
  def handle_call({:execute_node, node}, _from, state) do
    try do
      {result, new_context} = execute_node_internal(node, state.context, state.session_id)
      {:reply, result, %{state | context: new_context}}
    rescue
      e ->
        # Broadcast failure publicly (same as handle_info)
        broadcast_execution_failure(e, node, state.session_id)
        # Return error to caller
        {:reply, {:error, Exception.message(e)}, state}
    end
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
    PubSub.broadcast(
      state.session_id,
      :context,
      {:cwd_changed,
       %{
         old: old_cwd,
         new: path
       }}
    )

    {:reply, :ok, %{state | context: new_context}}
  end

  @impl true
  def handle_call(:reset, _from, state) do
    old_context = state.context

    # Create fresh context from initial values
    new_context = %{
      env: state.initial_env,
      env_meta: %{},
      cwd: state.initial_cwd,
      exit_code: 0,
      command_count: 0,
      last_output: %{stdout: [], stderr: []}
    }

    # Broadcast reset event
    PubSub.broadcast(
      state.session_id,
      :context,
      {:runtime_reset,
       %{
         old_context: old_context,
         new_context: new_context,
         timestamp: DateTime.utc_now()
       }}
    )

    {:reply, :ok, %{state | context: new_context}}
  end

  # No longer handle executable nodes asynchronously - execution is now synchronous via execute_node/2

  # Private Helpers

  defp execute_node_internal(node, context, session_id) do
    # Use ExecutionPipeline for clean execution and broadcasting
    new_context = RShell.Runtime.ExecutionPipeline.execute(node, context, session_id)
    {{:ok, new_context}, new_context}
  end

  # Execute AST nodes (exported for ExecutionPipeline)
  def do_execute_node(node, context, session_id) do
    case node do
      # RShell wraps commands in CmdLine nodes - extract the inner command/pipeline/list
      %Types.CmdLine{children: [inner_node | _]} ->
        # Transparent pass-through - don't increment command_count for wrapper
        do_execute_node(inner_node, context, session_id)

      # Increment command_count first, then execute and preserve result context
      %Types.Command{} = cmd ->
        context
        |> increment_command_count()
        |> then(&execute_command(cmd, &1, session_id))

      %Types.Pipeline{} = _pipeline ->
        # TODO: Implement pipeline execution
        raise "Pipeline execution not yet implemented"

      %Types.Assignment{} = assignment ->
        # Assignments don't increment command_count
        execute_rshell_assignment(assignment, context, session_id)

      %Types.IfStatement{} = _stmt ->
        # TODO: Implement RShell if statement execution
        raise "If statement execution not yet implemented for RShell"

      %Types.ForStatement{} = _stmt ->
        # TODO: Implement RShell for loop execution
        raise "For loop execution not yet implemented for RShell"

      %Types.WhileStatement{} = _stmt ->
        # TODO: Implement RShell while loop execution
        raise "While loop execution not yet implemented for RShell"

      other ->
        node_type = other.__struct__ |> Module.split() |> List.last()
        raise "Execution not implemented for #{node_type}"
    end
  end

  # Helper: Increment command count
  defp increment_command_count(context) do
    %{context | command_count: context.command_count + 1}
  end

  # Legacy name for internal use
  defp simple_execute(node, context, session_id) do
    do_execute_node(node, context, session_id)
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

      {:error, reason} ->
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
  defp execute_builtin(name, args, stdin, context, _session_id) do
    alias RShell.BuiltinResult

    case Builtins.execute(name, args, stdin, context) do
      {new_context, stdout, stderr, exit_code} ->
        # Wrap POSIX-style tuple in struct for easier transport
        result = BuiltinResult.new(new_context, stdout, stderr, exit_code)

        # Materialize and update context (ensures exit code propagates)
        BuiltinResult.materialize_and_update(result)

      {:error, :not_a_builtin} ->
        # Should not happen since we checked is_builtin?, but handle gracefully
        Logger.warning("Builtin '#{name}' not found despite passing is_builtin? check")
        raise "External command execution not yet implemented"
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

  # Execute RShell-style assignment: X = value
  defp execute_rshell_assignment(
         %Types.Assignment{name: name_node, value: value_node},
         context,
         _session_id
       ) do
    # Extract variable name from identifier
    var_name =
      case name_node do
        %Types.Identifier{source_info: %{text: text}} -> text
        %{source_info: %{text: text}} -> text
        _ -> ""
      end

    # Extract value - may be literal or expression
    value_result = extract_value_from_node(value_node, context)

    # Update environment
    new_env = Map.put(context.env, var_name, value_result)
    # Assignments produce NO output
    %{context | env: new_env, last_output: %{stdout: [], stderr: []}}
  end

  # Extract value from RShell value nodes (literals, expressions, etc.)
  defp extract_value_from_node(%Types.Number{source_info: %{text: text}}, _context) do
    case Integer.parse(text) do
      {int, ""} -> int
      _ ->
        case Float.parse(text) do
          {float, ""} -> float
          _ -> text
        end
    end
  end

  defp extract_value_from_node(%Types.String{source_info: %{text: text}}, _context) do
    # Remove quotes from string literals
    if String.starts_with?(text, "\"") and String.ends_with?(text, "\"") do
      String.slice(text, 1..-2//1)
    else
      text
    end
  end

  defp extract_value_from_node(%Types.Boolean{source_info: %{text: text}}, _context) do
    text == "true"
  end

  defp extract_value_from_node(%Types.Array{children: children}, context) when is_list(children) do
    Enum.map(children, &extract_value_from_node(&1, context))
  end

  defp extract_value_from_node(%Types.Object{children: children}, context) when is_list(children) do
    Enum.reduce(children, %{}, fn
      %Types.ObjectEntry{key: key_node, value: value_node}, acc ->
        key = extract_text_from_node(key_node, context)
        value = extract_value_from_node(value_node, context)
        Map.put(acc, key, value)
      _, acc -> acc
    end)
  end

  defp extract_value_from_node(node, context) do
    # Fallback to text extraction for other node types
    extract_text_from_node(node, context)
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

  # Extract text from any node - simplified for RShell
  # RShell nodes have simple source_info.text fields
  defp extract_text_from_node(%{source_info: %{text: text}}, _context) when is_binary(text),
    do: text

  defp extract_text_from_node(_, _context), do: ""

  # 1-arity fallback
  defp extract_text_from_node(%{source_info: %{text: text}}) when is_binary(text), do: text
  defp extract_text_from_node(_), do: ""

  # =============================================================================
  # Bracket Notation Support for Environment Variables (using Warpath JSONPath)
  # =============================================================================

  # Parse bracket notation for nested data access using JSONPath.
  #
  # Examples:
  #   - SERVER["port"] -> Access map key
  #   - SERVERS[0] -> Access list index
  #   - CONFIG["db"]["host"] -> Nested map access
  #   - APPS[0]["name"] -> List then map access
  defp parse_bracket_access(expr, context) do
    # Split variable name from bracket chain: SERVER["port"] -> ["SERVER", "["port"]"]
    case String.split(expr, "[", parts: 2) do
      [var_name, bracket_rest] ->
        # Get initial value from environment
        initial_value = Map.get(context.env || %{}, var_name)

        # Convert bracket notation to JSONPath and query
        path = bracket_to_jsonpath("[" <> bracket_rest)

        case Warpath.query(initial_value, path) do
          {:ok, [result]} -> result
          {:ok, []} -> nil
          _ -> nil
        end

      [var_name] ->
        # No brackets - simple variable
        Map.get(context.env || %{}, var_name)
    end
  end

  # Convert bracket notation to JSONPath query string.
  #
  # Examples:
  #   - ["port"] -> $.port
  #   - [0] -> $[0]
  #   - ["db"]["host"] -> $.db.host
  #   - [0]["name"] -> $[0].name
  defp bracket_to_jsonpath(bracket_str) do
    # Extract all keys from: ["port"] or ["db"]["host"] or [0] or [0]["name"]
    Regex.scan(~r/\[([^\]]+)\]/, bracket_str)
    |> Enum.map(fn [_, key] ->
      # Remove quotes if present: "port" -> port
      clean_key = String.trim(key, "\"")

      # Try parsing as integer for list/array access
      case Integer.parse(clean_key) do
        {int, ""} -> "[#{int}]"
        _ -> ".#{clean_key}"
      end
    end)
    |> Enum.join("")
    |> then(&"$#{&1}")
  end

  # broadcast_execution_success/5 removed - no longer needed with synchronous execution

  # Broadcast successful execution result with explicit output (for commands in loops)
  defp broadcast_execution_success_with_output(
         node,
         new_context,
         _old_context,
         duration_us,
         stdout,
         stderr,
         session_id
       ) do
    result = %{
      status: :success,
      node: node,
      node_type: get_node_type(node),
      node_text: get_node_text(node),
      node_line: get_node_line(node),
      exit_code: new_context.exit_code,
      stdout: stdout,
      stderr: stderr,
      context: %{
        env: new_context.env,
        cwd: new_context.cwd,
        exit_code: new_context.exit_code
      },
      duration_us: duration_us,
      timestamp: DateTime.utc_now()
    }

    PubSub.broadcast(session_id, :runtime, {:execution_result, result})
  end

  # Broadcast execution failure with rich context (for top-level commands)
  defp broadcast_execution_failure(exception, node, session_id) do
    node_type = get_node_type(node)

    error_reason =
      case exception do
        %RuntimeError{} -> "NotImplementedError"
        _ -> exception.__struct__ |> Module.split() |> List.last()
      end

    result = %{
      status: :error,
      node: node,
      node_type: node_type,
      node_text: get_node_text(node),
      node_line: get_node_line(node),
      error: Exception.message(exception),
      reason: error_reason,
      # Include empty output fields
      stdout: "",
      stderr: "",
      exit_code: nil,
      timestamp: DateTime.utc_now()
    }

    PubSub.broadcast(session_id, :runtime, {:execution_result, result})
    result
  end

  # Broadcast execution failure with explicit output (for commands in loops)
  defp broadcast_execution_failure_with_output(
         exception,
         node,
         stdout,
         stderr,
         exit_code,
         session_id
       ) do
    node_type = get_node_type(node)

    error_reason =
      case exception do
        %RuntimeError{} -> "NotImplementedError"
        _ -> exception.__struct__ |> Module.split() |> List.last()
      end

    result = %{
      status: :error,
      node: node,
      node_type: node_type,
      node_text: get_node_text(node),
      node_line: get_node_line(node),
      error: Exception.message(exception),
      reason: error_reason,
      # Include any output produced before error
      stdout: stdout,
      stderr: stderr,
      exit_code: exit_code,
      timestamp: DateTime.utc_now()
    }

    PubSub.broadcast(session_id, :runtime, {:execution_result, result})
    result
  end

  # Extract node type safely
  defp get_node_type(node) when is_struct(node) do
    node.__struct__ |> Module.split() |> List.last()
  end

  defp get_node_type(_), do: "Unknown"

  # Extract node text safely
  defp get_node_text(%{source_info: %{text: text}}) when is_binary(text), do: text
  defp get_node_text(_), do: nil

  # Extract node line safely
  defp get_node_line(%{source_info: %{start_line: line}}) when is_integer(line), do: line
  defp get_node_line(_), do: nil

  # Materialize output - convert Stream to list of native terms
  defp materialize_output(stream) when is_function(stream) do
    # Return list of native terms (NO string conversion!)
    stream |> Enum.to_list()
  end

  defp materialize_output(string) when is_binary(string) do
    # Single string becomes list with one element
    if string == "", do: [], else: [string]
  end

  defp materialize_output([]), do: []
  defp materialize_output(list) when is_list(list), do: list
  defp materialize_output(term), do: [term]

  # =============================================================================
  # Control Flow Helper Functions
  # =============================================================================

  # Execute a list of commands sequentially, threading context through each
  # Broadcasts execution results for each command
  defp execute_command_list(nodes, context, session_id) when is_list(nodes) do
    Enum.reduce(nodes, context, fn node, acc_context ->
      start_time = System.monotonic_time(:microsecond)

      # Execute the node
      try do
        new_context = simple_execute(node, acc_context, session_id)
        duration = System.monotonic_time(:microsecond) - start_time

        # Output is now in context.last_output (no process dictionary!)
        broadcast_execution_success_with_output(
          node,
          new_context,
          acc_context,
          duration,
          new_context.last_output.stdout,
          new_context.last_output.stderr,
          session_id
        )

        new_context
      rescue
        e ->
          _duration = System.monotonic_time(:microsecond) - start_time

          # Get any output that was produced before error (from context)
          stdout = acc_context.last_output.stdout
          stderr = acc_context.last_output.stderr

          broadcast_execution_failure_with_output(
            e,
            node,
            stdout,
            stderr,
            acc_context.exit_code,
            session_id
          )

          # Continue with unchanged context
          acc_context
      end
    end)
  end

  defp execute_command_list(_, context, _session_id), do: context

  # Execute body nodes - RShell uses lists of children directly
  defp execute_body_nodes(children, context, session_id) when is_list(children) do
    execute_command_list(children, context, session_id)
  end

  defp execute_body_nodes(_, context, _session_id), do: context

  # Extract iteration values from for statement value nodes with native type support
  defp extract_loop_values(nil, _context), do: []
  defp extract_loop_values([], _context), do: []

  defp extract_loop_values(value_nodes, context) when is_list(value_nodes) do
    value_nodes
    |> Enum.flat_map(fn node ->
      value = extract_text_from_node(node, context)

      # CRITICAL: Variable expansion preserves native types!
      # $A where A=[1,2,3] returns [1,2,3], NOT string "[1, 2, 3]"
      case value do
        # Native list - iterate over elements
        list when is_list(list) ->
          list

        # Native map - single value
        map when is_map(map) ->
          [map]

        # String - split on whitespace (traditional bash)
        string when is_binary(string) ->
          String.split(string, ~r/\s+/, trim: true)

        # Other native types (numbers, booleans, atoms)
        other ->
          [other]
      end
    end)
  end

  # =============================================================================
  # Control Flow Execution Functions
  # =============================================================================

  # TEMPORARILY DISABLED: Bash-specific control flow helpers
  # TODO: Reimplement for RShell's brace-based syntax
  # See RSHELL_HARD_CUTOVER_PLAN.md for details

  @doc false
  defp __bash_control_flow_disabled__ do
    """
    The following bash control flow functions have been temporarily disabled
    because they use bash-specific node structures (DoGroup, CompoundStatement, etc.)
    that don't exist in RShell's brace-based syntax.

    These need to be reimplemented to work with RShell's:
    - IfStatement (with body as direct children list)
    - ForStatement (with in-clause and brace body)
    - WhileStatement (with condition and brace body)
    - ElifClause and ElseClause (different structure)
    """
  end

  # Execute if statement with elif/else support
  if false do
  defp execute_if_statement(
         %Types.IfStatement{condition: condition_nodes, children: children},
         context,
         session_id
       ) do
    # Execute condition commands
    condition_context = execute_command_list(condition_nodes, context, session_id)

    if condition_context.exit_code == 0 do
      # Condition succeeded - execute then-body (first non-elif/else child)
      then_body =
        Enum.reject(children, fn child ->
          match?(%Types.ElifClause{}, child) or match?(%Types.ElseClause{}, child)
        end)

      execute_command_list(then_body, condition_context, session_id)
    else
      # Condition failed - try elif clauses, then else clause
      execute_elif_else_chain(children, condition_context, session_id)
    end
  end

  # Try elif clauses in order, then else clause
  defp execute_elif_else_chain(children, context, session_id) do
    # Get all elif clauses
    elif_clauses = Enum.filter(children, &match?(%Types.ElifClause{}, &1))

    # Try each elif clause
    case try_elif_clauses(elif_clauses, context, session_id) do
      {:executed, new_context} ->
        new_context

      :no_match ->
        # No elif matched, try else clause
        case Enum.find(children, &match?(%Types.ElseClause{}, &1)) do
          %Types.ElseClause{children: else_body} ->
            execute_command_list(else_body, context, session_id)

          nil ->
            # No else clause - return context from condition
            context
        end
    end
  end

  # Try elif clauses until one matches
  defp try_elif_clauses([], _context, _session_id), do: :no_match

  defp try_elif_clauses([%Types.ElifClause{children: elif_children} | rest], context, session_id) do
    # ElifClause.children contains both condition and body commands
    # Need to separate them (similar to IfStatement structure)
    # The condition commands come first, then the body commands

    # For now, execute all children as condition+body in sequence
    # TODO: Properly separate condition from body based on AST structure
    elif_context = execute_command_list(elif_children, context, session_id)

    if elif_context.exit_code == 0 do
      # This elif matched - return executed context
      {:executed, elif_context}
    else
      # Try next elif
      try_elif_clauses(rest, context, session_id)
    end
  end

  # Execute for statement with native type support
  defp execute_for_statement(
         %Types.ForStatement{variable: var_node, value: value_nodes, body: body},
         context,
         session_id
       ) do
    # Extract variable name
    var_name = extract_variable_name(var_node)

    # Extract values with native type preservation
    values = extract_loop_values(value_nodes, context)

    # Iterate over values
    Enum.reduce(values, context, fn value, acc_context ->
      # Store native value in environment
      new_env = Map.put(acc_context.env, var_name, value)
      loop_context = %{acc_context | env: new_env}
      execute_do_group_or_node(body, loop_context, session_id)
    end)
  end

  # Execute while statement
  defp execute_while_statement(
         %Types.WhileStatement{condition: condition_nodes, body: body},
         context,
         session_id
       ) do
    execute_while_loop(condition_nodes, body, context, session_id)
  end

  # Recursive while loop execution
  defp execute_while_loop(condition_nodes, body, context, session_id) do
    # Execute condition
    condition_context = execute_command_list(condition_nodes, context, session_id)

    if condition_context.exit_code == 0 do
      # Condition succeeded - execute body and continue
      body_context = execute_body_nodes(body, condition_context, session_id)
      execute_while_loop(condition_nodes, body, body_context, session_id)
    else
      # Condition failed - exit loop
      condition_context
    end
  end
  end  # End of if false block for disabled bash control flow
end
