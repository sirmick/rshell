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
            Logger.debug("ExprLine: no executable child found, returning context unchanged")
            context
          node ->
            Logger.debug("ExprLine: executing #{inspect(node.__struct__)}")
            do_execute_node(node, context, session_id)
        end

      # RShell wraps control flow in ControlFlow nodes - extract the inner statement
      %Types.ControlFlow{children: [inner_node | _]} ->
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

      %Types.IfStatement{} = stmt ->
        # RShell if statement execution
        execute_if_statement(stmt, context, session_id)

      %Types.ForStatement{} = stmt ->
        # RShell for loop execution
        execute_for_statement(stmt, context, session_id)

      %Types.WhileStatement{} = stmt ->
        # RShell while loop execution
        execute_while_statement(stmt, context, session_id)

      %Types.Newline{} ->
        # Newlines are not executable - just return context unchanged
        context

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
  # Uses ExprEvaluator to convert AST directly to native Elixir types (NO JSON!)
  defp execute_rshell_assignment(
         %Types.Assignment{name: name_node, value: value_node},
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

    # NEW: Use ExprEvaluator to convert AST to native value
    native_value = ExprEvaluator.evaluate(value_node, context)

    # Update environment with native value
    new_env = Map.put(context.env, var_name, native_value)

    # Broadcast variable_set event
    PubSub.broadcast(session_id, :context, {:variable_set, %{
      name: var_name,
      value: native_value
    }})

    # Assignments produce NO output
    %{context | env: new_env, last_output: %{stdout: [], stderr: []}}
  end

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

  # Execute a list of commands sequentially, threading context through each
  # Broadcasts execution results for each command
  # Returns tuple {final_context, accumulated_output} for use by loops
  defp execute_command_list(nodes, context, session_id, accumulate \\ false) when is_list(nodes) do
    if accumulate do
      # Accumulate output across all commands (for loops)
      {final_context, accumulated} = Enum.reduce(nodes, {context, %{stdout: [], stderr: []}}, fn node, {acc_context, acc_output} ->
        start_time = System.monotonic_time(:microsecond)

        # Execute the node
        try do
          new_context = simple_execute(node, acc_context, session_id)
          duration = System.monotonic_time(:microsecond) - start_time

          # Accumulate output from this command
          new_accumulated = %{
            stdout: acc_output.stdout ++ new_context.last_output.stdout,
            stderr: acc_output.stderr ++ new_context.last_output.stderr
          }

          # Broadcast with the command's own output
          broadcast_execution_success_with_output(
            node,
            new_context,
            acc_context,
            duration,
            new_context.last_output.stdout,
            new_context.last_output.stderr,
            session_id
          )

          {new_context, new_accumulated}
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
            {acc_context, acc_output}
        end
      end)

      # Return context with accumulated output
      %{final_context | last_output: accumulated}
    else
      # Normal mode - just thread context without accumulating
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
  end

  defp execute_command_list(_, context, _session_id, _accumulate), do: context

  # Execute body nodes - RShell uses lists of children directly
  # accumulate: whether to accumulate output across all commands (needed for loops)
  defp execute_body_nodes(children, context, session_id, accumulate \\ false) when is_list(children) do
    require Logger
    Logger.debug("execute_body_nodes: #{length(children)} children, accumulate=#{accumulate}")
    Enum.each(children, fn child ->
      Logger.debug("  child type: #{inspect(child.__struct__)}")
    end)
    result = execute_command_list(children, context, session_id, accumulate)
    Logger.debug("execute_body_nodes result: command_count=#{result.command_count}")
    result
  end

  defp execute_body_nodes(_, context, _session_id, _accumulate), do: context

  # =============================================================================
  # Control Flow Execution Functions (RShell Implementation)
  # =============================================================================

  # Execute RShell if statement with elif/else support
  # RShell structure: condition is Parenthesized node, body is Block, alternative is list
  defp execute_if_statement(
         %Types.IfStatement{condition: condition_node, body: body_node, alternative: alternatives},
         context,
         session_id
       ) do
    require Logger
    Logger.debug("execute_if_statement called")
    Logger.debug("  condition_node: #{inspect(condition_node.__struct__)}")
    Logger.debug("  body_node: #{inspect(body_node.__struct__)}")

    # Evaluate condition expression (returns boolean or uses exit code)
    condition_result = evaluate_condition(condition_node, context, session_id)
    Logger.debug("  condition_result: #{inspect(condition_result)}")

    if condition_result do
      # Condition is true - execute then-body
      Logger.debug("  executing if body")
      result = execute_block(body_node, context, session_id, false)
      Logger.debug("  if body executed, command_count: #{result.command_count}")
      result
    else
      # Condition is false - try alternatives (elif/else)
      Logger.debug("  condition false, checking alternatives")
      execute_alternatives(alternatives, context, session_id)
    end
  end

  # Execute elif/else alternatives
  defp execute_alternatives([], context, _session_id) do
    # No alternatives - return context unchanged
    context
  end

  defp execute_alternatives([alt | rest], context, session_id) do
    case alt do
      %Types.ElifClause{condition: elif_cond, body: elif_body} ->
        # Evaluate elif condition
        if evaluate_condition(elif_cond, context, session_id) do
          # This elif matched - execute body
          execute_block(elif_body, context, session_id, false)
        else
          # Try next alternative
          execute_alternatives(rest, context, session_id)
        end

      %Types.ElseClause{body: else_body} ->
        # Else clause always executes
        execute_block(else_body, context, session_id, false)

      _ ->
        # Unknown alternative type - skip and continue
        execute_alternatives(rest, context, session_id)
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

  # Execute RShell for statement with native type support
  # RShell structure: variable is Identifier, iterable is expression, body is Block
  defp execute_for_statement(
         %Types.ForStatement{variable: var_node, iterable: iterable_node, body: body_node},
         context,
         session_id
       ) do
    # Extract variable name
    var_name = extract_variable_name(var_node)

    # Evaluate iterable expression to get collection
    iterable_value = ExprEvaluator.evaluate(iterable_node, context)

    # Convert to list if needed
    values =
      case iterable_value do
        list when is_list(list) -> list
        map when is_map(map) -> [map]
        string when is_binary(string) -> String.split(string, ~r/\s+/, trim: true)
        other -> [other]
      end

    # Iterate over values, accumulating output from all iterations
    final_context = Enum.reduce(values, context, fn value, acc_context ->
      # Store native value in environment
      new_env = Map.put(acc_context.env, var_name, value)
      # Clear last_output for this iteration
      loop_context = %{acc_context | env: new_env, last_output: %{stdout: [], stderr: []}}
      # Execute body and get result
      result_context = execute_block(body_node, loop_context, session_id, false)

      # Accumulate output from this iteration into acc_context
      %{result_context |
        last_output: %{
          stdout: acc_context.last_output.stdout ++ result_context.last_output.stdout,
          stderr: acc_context.last_output.stderr ++ result_context.last_output.stderr
        }
      }
    end)

    final_context
  end

  # Execute RShell while statement
  # RShell structure: condition is Parenthesized, body is Block
  defp execute_while_statement(
         %Types.WhileStatement{condition: condition_node, body: body_node},
         context,
         session_id
       ) do
    # NEW: Use frame stack for while loop execution
    execute_while_loop_with_frames(condition_node, body_node, context, session_id)
  end

  # Frame-based while loop execution
  defp execute_while_loop_with_frames(condition_node, body_node, context, session_id) do
    # Evaluate condition
    if evaluate_condition(condition_node, context, session_id) do
      # Condition is true - execute body and continue
      # Clear last_output for this iteration
      clean_context = %{context | last_output: %{stdout: [], stderr: []}}
      body_context = execute_block(body_node, clean_context, session_id, true)

      # Accumulate output from this iteration into context
      accumulated_context = %{body_context |
        last_output: %{
          stdout: context.last_output.stdout ++ body_context.last_output.stdout,
          stderr: context.last_output.stderr ++ body_context.last_output.stderr
        }
      }

      # Continue loop with accumulated output in context
      execute_while_loop_with_frames(condition_node, body_node, accumulated_context, session_id)
    else
      # Condition is false - return final context with accumulated output
      context
    end
  end

  # Execute a Block node (contains children list)
  # accumulate: whether to accumulate output across all commands in the block
  defp execute_block(%Types.Block{children: children}, context, session_id, accumulate) do
    require Logger
    Logger.debug("execute_block Block: #{length(children)} children, accumulate=#{accumulate}")
    execute_body_nodes(children, context, session_id, accumulate)
  end

  # Execute an ExprBlock node (wrapper around Block nodes)
  defp execute_block(%Types.ExprBlock{children: children}, context, session_id, accumulate) do
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
        execute_body_nodes(block_children, context, session_id, accumulate)
      _ ->
        Logger.debug("execute_block ExprBlock -> no content found")
        context
    end
  end

  # Fallback for non-Block nodes
  defp execute_block(node, context, session_id, _accumulate) when is_struct(node) do
    simple_execute(node, context, session_id)
  end

  defp execute_block(_, context, _session_id, _accumulate), do: context

  # Extract variable name from Identifier node
  defp extract_variable_name(%Types.Identifier{source_info: %{text: text}}), do: text
  defp extract_variable_name(%{source_info: %{text: text}}), do: text
  defp extract_variable_name(_), do: ""
end
