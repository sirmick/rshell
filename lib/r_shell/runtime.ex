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
  alias RShell.ExprEvaluator
  alias RShell.Runtime.FrameStack
  alias RShell.Runtime.ExecutionState
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
      command_count: 0
    }

    # NEW: Initialize frame stack alongside existing context
    frame_stack = FrameStack.new(
      output_mode: :isolate,
      context: context
    )

    Logger.debug("Runtime started: session_id=#{session_id}")

    {:ok,
     %{
       session_id: session_id,
       context: context,
       # NEW: Frame stack for future frame-based execution
       frame_stack: frame_stack,
       # Feature flag: false = use old context-based code (safe)
       use_frames: false,
       # Store for reset
       initial_env: env,
       # Store for reset
       initial_cwd: cwd
     }}
  end

  @impl true
  def handle_call({:execute_node, node}, _from, state) do
    try do
      # Create ExecutionState from runtime state
      exec_state = ExecutionState.from_runtime_state(state)

      # Execute with new state
      new_exec_state = execute_node_internal(node, exec_state)

      # Extract updates and apply to runtime state
      updates = ExecutionState.to_runtime_updates(new_exec_state)
      new_state = Map.merge(state, updates)

      {:reply, {:ok, new_exec_state.context}, new_state}
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
      command_count: 0
    }

    # NEW: Reinitialize frame stack on reset
    new_frame_stack = FrameStack.new(
      output_mode: :isolate,
      context: new_context
    )

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

    {:reply, :ok, %{state | context: new_context, frame_stack: new_frame_stack}}
  end

  # No longer handle executable nodes asynchronously - execution is now synchronous via execute_node/2

  # Private Helpers

  defp execute_node_internal(node, exec_state) do
    # Execute directly with state instead of going through ExecutionPipeline
    # ExecutionPipeline was designed for context-only flow and doesn't preserve frame_stack
    new_state = do_execute_node_with_state(node, exec_state)

    # Return updated execution state
    new_state
  end

  # Execute AST nodes (exported for ExecutionPipeline)
  # Legacy version for ExecutionPipeline compatibility
  def do_execute_node(node, context, session_id) do
    exec_state = %ExecutionState{
      context: context,
      frame_stack: FrameStack.new(output_mode: :isolate, context: context),
      session_id: session_id
    }
    new_state = do_execute_node_with_state(node, exec_state)
    new_state.context
  end

  # New version: Execute AST nodes with ExecutionState
  defp do_execute_node_with_state(node, state) do
    case node do
      # RShell wraps commands in CmdLine nodes - extract the inner command/pipeline/list
      %Types.CmdLine{children: [inner_node | _]} ->
        # Transparent pass-through - don't increment command_count for wrapper
        do_execute_node_with_state(inner_node, state)

      # RShell wraps expressions in ExprLine nodes - extract the inner assignment/expression
      %Types.ExprLine{children: children} = expr_line ->
        require Logger
        Logger.debug("ExprLine unwrapping: #{length(children)} children")
        if children == [] do
          Logger.debug("  ExprLine has EMPTY children!")
          Logger.debug("  ExprLine source_info: #{inspect(expr_line.source_info)}")
        end
        Enum.each(children, fn child ->
          Logger.debug("  child: #{inspect(child.__struct__)}")
        end)
        # Find the actual executable node (skip newlines and other wrappers)
        inner_node = Enum.find(children, fn child ->
          case child do
            %Types.Newline{} -> false
            %Types.CmdLine{} -> true
            %Types.Command{} -> true
            %Types.Assignment{} -> true
            %Types.IfStatement{} -> true
            %Types.ForStatement{} -> true
            %Types.WhileStatement{} -> true
            _ -> true  # Default to trying to execute
          end
        end)

        case inner_node do
          nil ->
            Logger.debug("ExprLine: no executable child found, returning state unchanged")
            state
          node ->
            Logger.debug("ExprLine: executing #{inspect(node.__struct__)}")
            do_execute_node_with_state(node, state)
        end

      # RShell wraps control flow in ControlFlow nodes - extract the inner statement
      %Types.ControlFlow{children: [inner_node | _]} ->
        # Transparent pass-through - don't increment command_count for wrapper
        do_execute_node_with_state(inner_node, state)

      # Increment command_count first, then execute and preserve result state
      %Types.Command{} = cmd ->
        incremented_context = increment_command_count(state.context)
        incremented_state = %{state | context: incremented_context}
        execute_command(cmd, incremented_state)

      %Types.Pipeline{} = _pipeline ->
        # TODO: Implement pipeline execution
        raise "Pipeline execution not yet implemented"

      %Types.Assignment{} = assignment ->
        # Assignments don't increment command_count
        new_context = execute_rshell_assignment(assignment, state.context, state.session_id)
        %{state | context: new_context}

      %Types.IfStatement{} = stmt ->
        # RShell if statement execution
        execute_if_statement(stmt, state)

      %Types.ForStatement{} = stmt ->
        # RShell for loop execution
        execute_for_statement(stmt, state)

      %Types.WhileStatement{} = stmt ->
        # RShell while loop execution
        execute_while_statement(stmt, state)

      %Types.Newline{} ->
        # Newlines are not executable - just return state unchanged
        state

      other ->
        node_type = other.__struct__ |> Module.split() |> List.last()
        raise "Execution not implemented for #{node_type}"
    end
  end

  # Helper: Increment command count
  defp increment_command_count(context) do
    %{context | command_count: context.command_count + 1}
  end

  # State-based execution helper
  # ALL execution functions follow this pattern: take ExecutionState, return ExecutionState
  @spec simple_execute_with_state(Types.t(), ExecutionState.t()) :: ExecutionState.t()
  defp simple_execute_with_state(node, state) do
    do_execute_node_with_state(node, state)
  end

  @spec execute_command(Types.Command.t(), ExecutionState.t()) :: ExecutionState.t()
  defp execute_command(%Types.Command{source_info: source_info} = cmd, state) do
    text = source_info.text || ""

    # Extract command name and arguments with context for variable expansion
    case extract_command_parts(cmd, state.context) do
      {:ok, command_name, args} ->
        # Check if it's a builtin command
        if Builtins.is_builtin?(command_name) do
          # Pass native args directly to builtins (returns updated state)
          execute_builtin(command_name, args, "", state)
        else
          # For external commands, show error message
          # TODO: Implement external command execution
          raise "Command not found: #{command_name}"
        end

      {:error, _reason} ->
        # Couldn't parse command, show error
        raise "Invalid command syntax: #{text}"
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

  # Execute a builtin command - now returns ExecutionState with frame_stack updated
  defp execute_builtin(name, args, stdin, state) do
    alias RShell.BuiltinResult

    case Builtins.execute(name, args, stdin, state) do
      {new_context, stdout, stderr, exit_code} when is_map(new_context) and not is_struct(new_context) ->
        # Backward compat: context returned
        result = BuiltinResult.new(new_context, stdout, stderr, exit_code)
        {updated_context, stdout_list, stderr_list} = BuiltinResult.materialize_and_update(result)

        # Add output to FrameStack
        updated_stack = FrameStack.add_output(state.frame_stack, stdout_list, stderr_list)

        # Return updated state
        %{state | context: updated_context, frame_stack: updated_stack}

      {%ExecutionState{} = new_state, stdout, stderr, exit_code} ->
        # New: ExecutionState returned
        result = BuiltinResult.new(new_state.context, stdout, stderr, exit_code)
        {updated_context, stdout_list, stderr_list} = BuiltinResult.materialize_and_update(result)

        # Add output to FrameStack from new_state
        updated_stack = FrameStack.add_output(new_state.frame_stack, stdout_list, stderr_list)

        # Return updated state with both context and frame_stack
        %{new_state | context: updated_context, frame_stack: updated_stack}

      {:error, :not_a_builtin} ->
        # Should not happen since we checked is_builtin?, but handle gracefully
        Logger.warning("Builtin '#{name}' not found despite passing is_builtin? check")
        raise "External command execution not yet implemented"
    end
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

  # Execute RShell-style assignment: X = value or X += value
  # Uses ExprEvaluator to convert AST directly to native Elixir types (NO JSON!)
  defp execute_rshell_assignment(
         %Types.Assignment{name: name_node, operator: operator_node, value: value_node, source_info: source_info},
         context,
         session_id
       ) do
    # Extract variable name from identifier
    var_name =
      case name_node do
        %Types.Identifier{source_info: %{text: text}} -> text
        %{source_info: %{text: text}} -> text
        _ -> ""
      end

    # Extract operator from AST node - can be a struct with source_info or plain token
    # If operator_node is nil, extract from the source text
    operator = case operator_node do
      %{source_info: %{text: text}} -> text
      text when is_binary(text) -> text
      nil ->
        # Operator not in field - extract from source text
        source_text = source_info.text || ""
        # Extract operator between variable name and value (e.g., "X += 5" -> "+=")
        cond do
          String.contains?(source_text, " += ") -> "+="
          String.contains?(source_text, " -= ") -> "-="
          String.contains?(source_text, " *= ") -> "*="
          String.contains?(source_text, " /= ") -> "/="
          String.contains?(source_text, " %= ") -> "%="
          String.contains?(source_text, " = ") -> "="
          true -> "="
        end
      _ ->
        Logger.error("Unknown operator format in assignment: #{inspect(operator_node)}")
        "="
    end

    # Evaluate the right-hand side value
    rhs_value = ExprEvaluator.evaluate(value_node, context)

    # Compute the new value based on operator
    new_value =
      case operator do
        "=" ->
          # Simple assignment
          rhs_value

        "+=" ->
          # Add to existing value (treat undefined as 0)
          lhs_value = Map.get(context.env, var_name, 0)
          apply_compound_operator("+", lhs_value, rhs_value)

        "-=" ->
          # Subtract from existing value
          lhs_value = Map.get(context.env, var_name, 0)
          apply_compound_operator("-", lhs_value, rhs_value)

        "*=" ->
          # Multiply existing value
          lhs_value = Map.get(context.env, var_name, 0)
          apply_compound_operator("*", lhs_value, rhs_value)

        "/=" ->
          # Divide existing value
          lhs_value = Map.get(context.env, var_name, 0)
          apply_compound_operator("/", lhs_value, rhs_value)

        "%=" ->
          # Modulo existing value
          lhs_value = Map.get(context.env, var_name, 0)
          apply_compound_operator("%", lhs_value, rhs_value)

        _ ->
          raise "Unsupported assignment operator: #{operator}"
      end

    # Update environment with computed value
    new_env = Map.put(context.env, var_name, new_value)

    # Broadcast variable_set event
    PubSub.broadcast(session_id, :context, {:variable_set, %{
      name: var_name,
      value: new_value
    }})

    # Assignments produce NO output (update env only)
    %{context | env: new_env}
  end


  # Apply compound assignment operators
  defp apply_compound_operator("+", left, right) when is_number(left) and is_number(right), do: left + right
  defp apply_compound_operator("-", left, right) when is_number(left) and is_number(right), do: left - right
  defp apply_compound_operator("*", left, right) when is_number(left) and is_number(right), do: left * right
  defp apply_compound_operator("/", left, right) when is_number(left) and is_number(right), do: left / right
  defp apply_compound_operator("%", left, right) when is_integer(left) and is_integer(right), do: rem(left, right)
  defp apply_compound_operator("+", left, right) when is_binary(left) and is_binary(right), do: left <> right
  defp apply_compound_operator(op, left, right) do
    raise "Unsupported compound operator '#{op}' for types #{type_name(left)} and #{type_name(right)}"
  end

  # Type name helper for error messages
  defp type_name(val) when is_integer(val), do: "integer"
  defp type_name(val) when is_float(val), do: "float"
  defp type_name(val) when is_binary(val), do: "string"
  defp type_name(val) when is_boolean(val), do: "boolean"
  defp type_name(val) when is_list(val), do: "list"
  defp type_name(val) when is_map(val), do: "map"
  defp type_name(nil), do: "nil"
  defp type_name(_), do: "unknown"

  # Extract command name from CommandName node by traversing children
  defp extract_command_name(%Types.CommandName{children: children}) when is_list(children) do
    # CommandName contains Word children - extract text from each
    name =
      children
      |> Enum.map(fn
        %{source_info: %{text: text}} when is_binary(text) -> text
        _ -> ""
      end)
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

  # Extract arguments from argument nodes with context for variable/expression expansion
  # Returns NATIVE values (not strings!) to preserve types
  defp extract_arguments(nil, _context), do: {:ok, []}
  defp extract_arguments([], _context), do: {:ok, []}

  defp extract_arguments(args_nodes, context) when is_list(args_nodes) do
    args =
      args_nodes
      |> Enum.map(&extract_argument_value(&1, context))
      |> Enum.reject(&is_nil/1)

    {:ok, args}
  end

  # Extract argument value - returns NATIVE type (not string!)
  defp extract_argument_value(%Types.CommandArgument{children: children}, context) when is_list(children) do
    # CommandArgument can contain multiple parts - collect and join/convert
    parts = Enum.map(children, &extract_argument_value(&1, context))

    # Filter out nils and convert to strings for joining
    non_nil_parts = Enum.reject(parts, &is_nil/1)

    case non_nil_parts do
      [] -> ""
      [single] -> convert_to_string(single)
      multiple ->
        # Convert all parts to strings and join
        multiple
        |> Enum.map(&convert_to_string/1)
        |> Enum.join("")
    end
  end

  # Variable reference: Look up native value in context and convert to string
  defp extract_argument_value(%Types.VariableReference{children: [identifier | _]}, context) do
    var_name = case identifier do
      %Types.Identifier{source_info: %{text: text}} -> text
      %{source_info: %{text: text}} -> text
      _ -> ""
    end

    # Look up value and convert to string (echo needs strings)
    value = Map.get(context.env, var_name, "")
    convert_to_string(value)
  end

  # Expression interpolation: Evaluate expression and convert to string
  defp extract_argument_value(%Types.ExprInterpolation{children: [expr | _]}, context) do
    # Use ExprEvaluator to get native value, then convert to string
    value = ExprEvaluator.evaluate(expr, context)
    convert_to_string(value)
  end

  # Raw argument with children (can contain variables/interpolations)
  defp extract_argument_value(%Types.RawArgument{children: children}, context) when is_list(children) do
    parts = Enum.map(children, &extract_argument_value(&1, context))

    # Join all parts (already converted to strings)
    parts
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&convert_to_string/1)
    |> Enum.join("")
  end

  # String literal - handle variable expansion within double-quoted strings
  defp extract_argument_value(%Types.String{source_info: %{text: text}}, context) when is_binary(text) do
    # Remove surrounding quotes
    content = String.trim(text, "\"")

    # Perform variable expansion: replace $VAR with context value
    # Use regex to find $IDENTIFIER patterns
    Regex.replace(~r/\$([A-Za-z_][A-Za-z0-9_]*)/, content, fn _, var_name ->
      value = Map.get(context.env, var_name, "")
      convert_to_string(value)
    end)
  end

  # Simple text nodes - return as string
  defp extract_argument_value(%{source_info: %{text: text}}, _context) when is_binary(text), do: text
  defp extract_argument_value(_, _context), do: ""


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

  # =============================================================================
  # Control Flow Helper Functions
  # =============================================================================

  # Execute a list of commands sequentially - ExecutionState version with FrameStack
  # Broadcasts execution results for each command
  defp execute_command_list(nodes, state, accumulate) when is_list(nodes) do
    if accumulate do
      # Accumulate output in FrameStack (for loops)
      Enum.reduce(nodes, state, fn node, acc_state ->
        start_time = System.monotonic_time(:microsecond)

        # Execute the node
        try do
          new_state = simple_execute_with_state(node, acc_state)
          duration = System.monotonic_time(:microsecond) - start_time

          # Get output from FrameStack (already added by execute_builtin)
          frame_output = FrameStack.get_output(new_state.frame_stack)

          # Broadcast with the command's own output
          broadcast_execution_success_with_output(
            node,
            new_state.context,
            acc_state.context,
            duration,
            frame_output.stdout,
            frame_output.stderr,
            new_state.session_id
          )

          new_state
        rescue
          e ->
            _duration = System.monotonic_time(:microsecond) - start_time

            # Get any output that was produced before error (from FrameStack)
            frame_output = FrameStack.get_output(acc_state.frame_stack)

            broadcast_execution_failure_with_output(
              e,
              node,
              frame_output.stdout,
              frame_output.stderr,
              acc_state.context.exit_code,
              acc_state.session_id
            )

            # Continue with unchanged state
            acc_state
        end
      end)
    else
      # Normal mode - just thread state without special accumulation logic
      Enum.reduce(nodes, state, fn node, acc_state ->
        start_time = System.monotonic_time(:microsecond)

        # Execute the node
        try do
          new_state = simple_execute_with_state(node, acc_state)
          duration = System.monotonic_time(:microsecond) - start_time

          # Get output from FrameStack
          frame_output = FrameStack.get_output(new_state.frame_stack)

          # Broadcast with output
          broadcast_execution_success_with_output(
            node,
            new_state.context,
            acc_state.context,
            duration,
            frame_output.stdout,
            frame_output.stderr,
            new_state.session_id
          )

          new_state
        rescue
          e ->
            _duration = System.monotonic_time(:microsecond) - start_time

            # Get any output that was produced before error (from FrameStack)
            frame_output = FrameStack.get_output(acc_state.frame_stack)

            broadcast_execution_failure_with_output(
              e,
              node,
              frame_output.stdout,
              frame_output.stderr,
              acc_state.context.exit_code,
              acc_state.session_id
            )

            # Continue with unchanged state
            acc_state
        end
      end)
    end
  end

  defp execute_command_list(_, state, _accumulate), do: state

  # Execute body nodes - RShell uses lists of children directly - ExecutionState version
  # accumulate: whether to accumulate output across all commands (needed for loops)
  defp execute_body_nodes(children, state, accumulate) when is_list(children) do
    require Logger
    Logger.debug("execute_body_nodes: #{length(children)} children, accumulate=#{accumulate}")
    Enum.each(children, fn child ->
      Logger.debug("  child type: #{inspect(child.__struct__)}")
    end)
    result_state = execute_command_list(children, state, accumulate)
    Logger.debug("execute_body_nodes result: command_count=#{result_state.context.command_count}")
    result_state
  end

  defp execute_body_nodes(_, state, _accumulate), do: state

  # =============================================================================
  # Control Flow Execution Functions (RShell Implementation)
  # =============================================================================

  # Execute RShell if statement with elif/else support (ExecutionState version)
  # RShell structure: condition is Parenthesized node, body is Block, alternative is list
  @spec execute_if_statement(Types.IfStatement.t(), ExecutionState.t()) :: ExecutionState.t()
  defp execute_if_statement(
         %Types.IfStatement{condition: condition_node, body: body_node, alternative: alternatives},
         state
       ) do
    require Logger
    Logger.debug("execute_if_statement called")
    Logger.debug("  condition_node: #{inspect(condition_node.__struct__)}")
    Logger.debug("  body_node: #{inspect(body_node.__struct__)}")

    # Evaluate condition expression (returns boolean or uses exit code)
    condition_result = evaluate_condition(condition_node, state.context, state.session_id)
    Logger.debug("  condition_result: #{inspect(condition_result)}")

    if condition_result do
      # Condition is true - execute then-body
      Logger.debug("  executing if body")
      result_state = execute_block(body_node, state, false)
      Logger.debug("  if body executed, command_count: #{result_state.context.command_count}")
      result_state
    else
      # Condition is false - try alternatives (elif/else)
      Logger.debug("  condition false, checking alternatives")
      execute_alternatives(alternatives, state)
    end
  end

  # Execute elif/else alternatives (ExecutionState version)
  defp execute_alternatives([], state) do
    # No alternatives - return state unchanged
    state
  end

  defp execute_alternatives([alt | rest], state) do
    case alt do
      %Types.ElifClause{condition: elif_cond, body: elif_body} ->
        # Evaluate elif condition
        if evaluate_condition(elif_cond, state.context, state.session_id) do
          # This elif matched - execute body
          execute_block(elif_body, state, false)
        else
          # Try next alternative
          execute_alternatives(rest, state)
        end

      %Types.ElseClause{body: else_body} ->
        # Else clause always executes
        execute_block(else_body, state, false)

      _ ->
        # Unknown alternative type - skip and continue
        execute_alternatives(rest, state)
    end
  end

  # Evaluate condition expression (from ParenthesizedExpression node)
  defp evaluate_condition(%Types.ParenthesizedExpression{children: children}, context, session_id) when is_list(children) and length(children) > 0 do
    # Find the actual expression (skip children with text "(" or ")")
    expr = Enum.find(children, fn child ->
      case child do
        %{source_info: %{text: text}} when text in ["(", ")"] -> false
        _ -> true
      end
    end)

    if expr do
      evaluate_condition(expr, context, session_id)
    else
      # No expression found - treat as false
      false
    end
  end

  # Also handle Parenthesized wrapper (aliased node)
  defp evaluate_condition(%Types.Parenthesized{children: children}, context, session_id) when is_list(children) do
    # Parenthesized contains 3 ParenthesizedExpression children: "(", content, ")"
    # Find the middle child that has actual content
    content_child = Enum.find(children, fn child ->
      case child do
        %Types.ParenthesizedExpression{children: inner_children} when inner_children != [] ->
          # Check if it's not just a paren token
          case child do
            %{source_info: %{text: text}} when text in ["(", ")"] -> false
            _ -> true
          end
        _ -> false
      end
    end)

    if content_child do
      evaluate_condition(content_child, context, session_id)
    else
      # No content found - treat as false
      false
    end
  end

  # Fallback: Direct expression evaluation (for Identifier and other expression nodes)
  defp evaluate_condition(expr, context, _session_id) do
    require Logger
    Logger.debug("evaluate_condition: evaluating #{inspect(expr.__struct__)}")

    result = try do
      ExprEvaluator.evaluate(expr, context)
    rescue
      e ->
        Logger.error("ExprEvaluator.evaluate crashed: #{Exception.message(e)}")
        Logger.error("  expr: #{inspect(expr, pretty: true)}")
        Logger.error("  context.env: #{inspect(Map.keys(context.env))}")
        reraise e, __STACKTRACE__
    end

    Logger.debug("  result: #{inspect(result)}")

    # Use ExprEvaluator's truthy? function for consistent truthiness evaluation
    truthiness = case result do
      result when is_boolean(result) -> result
      val when val in [0, "", nil, false] -> false
      _ -> ExprEvaluator.truthy?(result)
    end

    Logger.debug("  truthiness: #{inspect(truthiness)}")
    truthiness
  end

  # Execute RShell for statement with actual FrameStack (ExecutionState version)
  # RShell structure: variable is Identifier, iterable is expression, body is Block
  @spec execute_for_statement(Types.ForStatement.t(), ExecutionState.t()) :: ExecutionState.t()
  defp execute_for_statement(
         %Types.ForStatement{variable: var_node, iterable: iterable_node, body: body_node},
         state
       ) do
    # Extract variable name
    var_name = extract_variable_name(var_node)

    # Evaluate iterable expression to get collection
    iterable_value = ExprEvaluator.evaluate(iterable_node, state.context)

    # Convert to list if needed
    values =
      case iterable_value do
        list when is_list(list) -> list
        map when is_map(map) -> [map]
        string when is_binary(string) -> String.split(string, ~r/\s+/, trim: true)
        other -> [other]
      end

    # Push loop frame onto FrameStack with :accumulate mode
    new_frame_stack = FrameStack.push_frame(state.frame_stack, :loop, :accumulate, %{type: :for, variable: var_name})
    loop_state = %{state | frame_stack: new_frame_stack}

    # Iterate over values with actual frame-based accumulation
    final_state = Enum.reduce(values, loop_state, fn value, acc_state ->
      # Store native value in environment (using FrameStack)
      new_env = Map.put(acc_state.context.env, var_name, value)
      iteration_context = %{acc_state.context | env: new_env}
      iteration_state = %{acc_state | context: iteration_context}

      # Execute body with accumulate=true so commands add to the frame
      execute_block(body_node, iteration_state, true)
    end)

    # Pop frame and get accumulated output
    {popped_stack, accumulated_output} = FrameStack.pop_frame(final_state.frame_stack)

    # Add accumulated output to parent frame (so it's visible to caller)
    updated_stack = FrameStack.add_output(popped_stack, accumulated_output.stdout, accumulated_output.stderr)

    %{final_state | frame_stack: updated_stack}
  end

  # Execute RShell while statement (ExecutionState version with actual FrameStack)
  # RShell structure: condition is Parenthesized, body is Block
  @spec execute_while_statement(Types.WhileStatement.t(), ExecutionState.t()) :: ExecutionState.t()
  defp execute_while_statement(
         %Types.WhileStatement{condition: condition_node, body: body_node},
         state
       ) do
    # Push loop frame onto FrameStack with :accumulate mode
    new_frame_stack = FrameStack.push_frame(state.frame_stack, :loop, :accumulate, %{type: :while})
    loop_state = %{state | frame_stack: new_frame_stack}

    # Execute while loop with actual frame-based accumulation
    final_state = execute_while_loop_with_frames(condition_node, body_node, loop_state)

    # Pop frame and get accumulated output
    {popped_stack, accumulated_output} = FrameStack.pop_frame(final_state.frame_stack)

    # Add accumulated output to parent frame (so it's visible to caller)
    updated_stack = FrameStack.add_output(popped_stack, accumulated_output.stdout, accumulated_output.stderr)

    %{final_state | frame_stack: updated_stack}
  end

  # Frame-based while loop execution - uses actual FrameStack operations
  defp execute_while_loop_with_frames(condition_node, body_node, state) do
    # Evaluate condition
    if evaluate_condition(condition_node, state.context, state.session_id) do
      # Condition is true - execute body
      body_state = execute_block(body_node, state, true)

      # Continue loop (accumulated output is in frame_stack)
      execute_while_loop_with_frames(condition_node, body_node, body_state)
    else
      # Condition is false - return final state
      # Accumulated output will be popped by caller
      state
    end
  end

  # Execute a Block node (contains children list) - ExecutionState version
  # accumulate: whether to accumulate output across all commands in the block
  @spec execute_block(Types.t(), ExecutionState.t(), boolean()) :: ExecutionState.t()
  defp execute_block(%Types.Block{children: children}, state, accumulate) do
    require Logger
    Logger.debug("execute_block Block: #{length(children)} children, accumulate=#{accumulate}")
    execute_body_nodes(children, state, accumulate)
  end

  # Execute an ExprBlock node (wrapper around Block nodes) - ExecutionState version
  defp execute_block(%Types.ExprBlock{children: children}, state, accumulate) do
    require Logger
    Logger.debug("execute_block ExprBlock: #{length(children)} children, accumulate=#{accumulate}")
    # ExprBlock contains Block nodes as children (opening brace, content, closing brace)
    # Find the middle Block that has actual content
    content_block = Enum.find(children, fn child ->
      case child do
        %Types.Block{children: block_children} when block_children != [] -> true
        _ -> false
      end
    end)

    case content_block do
      %Types.Block{children: block_children} ->
        Logger.debug("execute_block ExprBlock -> found content Block with #{length(block_children)} children")
        # Execute the content directly (don't recurse through execute_block)
        execute_body_nodes(block_children, state, accumulate)
      _ ->
        Logger.debug("execute_block ExprBlock -> no content found")
        state
    end
  end

  # Fallback for non-Block nodes - ExecutionState version
  defp execute_block(node, state, _accumulate) when is_struct(node) do
    simple_execute_with_state(node, state)
  end

  defp execute_block(_, state, _accumulate), do: state

  # Extract variable name from Identifier node
  defp extract_variable_name(%Types.Identifier{source_info: %{text: text}}), do: text
  defp extract_variable_name(%{source_info: %{text: text}}), do: text
  defp extract_variable_name(_), do: ""
end
