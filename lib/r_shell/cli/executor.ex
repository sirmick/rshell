defmodule RShell.CLI.Executor do
  @moduledoc """
  Shared execution logic for CLI modes.

  Handles:
  - Fragment execution with metrics collection
  - Event collection from PubSub
  - State accumulation
  """

  alias RShell.CLI.{Metrics, ExecutionRecord, State}
  alias RShell.{IncrementalParser, Runtime}
  alias BashParser.AST.Utils, as: ASTUtils

  @doc """
  Execute a script fragment and return updated state with execution record.

  This is the core execution function used by all CLI modes.
  Now uses SYNCHRONOUS execution instead of async PubSub.
  """
  @spec execute_fragment(String.t(), State.t()) :: {:ok, State.t()} | {:error, term()}
  def execute_fragment(fragment, %State{} = state) do
    timestamp = DateTime.utc_now()

    # Start parse metrics
    parse_metrics = Metrics.start()

    # Parse the fragment
    case IncrementalParser.append_fragment(state.parser_pid, fragment) do
      {:ok, ast} ->
        parse_metrics = Metrics.stop(parse_metrics)

        # Collect AST event (still async for observability)
        {incremental_ast, full_ast} = collect_ast_event(state.session_id, 100)

        # Start execution metrics
        exec_metrics = Metrics.start()

        # SYNCHRONOUS execution - directly call runtime for executable nodes
        execution_result = execute_ast_synchronously(ast, state.runtime_pid, state.session_id)

        exec_metrics = Metrics.stop(exec_metrics)

        # Extract output and context from execution result
        {exit_code, stdout, stderr, context} =
          extract_execution_data(
            execution_result,
            state.runtime_pid
          )

        # Build execution record
        record = %ExecutionRecord{
          fragment: fragment,
          timestamp: timestamp,
          parse_metrics: parse_metrics,
          exec_metrics: exec_metrics,
          incremental_ast: incremental_ast,
          full_ast: full_ast,
          execution_result: execution_result,
          exit_code: exit_code,
          stdout: stdout,
          stderr: stderr,
          context: context
        }

        # Add to history
        new_state = %{state | history: state.history ++ [record]}

        # Drain any remaining PubSub events to prevent stale messages
        drain_pubsub_events(state.session_id)

        {:ok, new_state}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Drain any remaining PubSub events to prevent stale messages
  defp drain_pubsub_events(session_id) do
    receive do
      {:ast_incremental, _} -> drain_pubsub_events(session_id)
      {:executable_node, _, _} -> drain_pubsub_events(session_id)
      {:variable_set, _} -> drain_pubsub_events(session_id)
      {:parsing_failed, _} -> drain_pubsub_events(session_id)
      {:parsing_crashed, _} -> drain_pubsub_events(session_id)
    after
      0 -> :ok
    end
  end

  # Collect only AST event after parsing (for observability)
  # Parser still broadcasts AST events, but execution is now synchronous
  defp collect_ast_event(_session_id, timeout) do
    receive do
      {:ast_incremental, metadata} ->
        # Got AST event
        {metadata.changed_nodes, metadata.full_ast}

      {:parsing_failed, _error} ->
        # Parse failed, no AST
        {nil, nil}

      {:parsing_crashed, _error} ->
        # Parser crashed, no AST
        {nil, nil}
    after
      timeout ->
        # Timeout - shouldn't happen, but handle gracefully
        {nil, nil}
    end
  end

  # Execute AST nodes synchronously by directly calling Runtime
  # Returns execution_result map or nil if nothing executable
  defp execute_ast_synchronously(ast, runtime_pid, _session_id) do
    # Find executable nodes in the AST
    executable_nodes = find_executable_nodes(ast)

    # Execute each node synchronously
    # CRITICAL: Return the LAST result, but keep executing all nodes
    # (Previous bug: ignored accumulator, so last result was always returned)
    Enum.reduce(executable_nodes, nil, fn node, _prev_result ->
      case Runtime.execute_node(runtime_pid, node) do
        {:ok, context} ->
          # Build execution result from context
          %{
            status: :success,
            node: node,
            node_type: ASTUtils.node_type(node),
            node_text: ASTUtils.node_text(node),
            node_line: ASTUtils.node_line(node),
            exit_code: context.exit_code,
            stdout: context.last_output.stdout,
            stderr: context.last_output.stderr,
            context: context,
            # Already tracked in exec_metrics
            duration_us: 0,
            timestamp: DateTime.utc_now()
          }

        {:error, reason} ->
          # Execution failed
          %{
            status: :error,
            node: node,
            node_type: ASTUtils.node_type(node),
            node_text: ASTUtils.node_text(node),
            node_line: ASTUtils.node_line(node),
            error: reason,
            reason: "ExecutionError",
            stdout: [],
            stderr: [],
            exit_code: nil,
            timestamp: DateTime.utc_now()
          }
      end
    end)
  end

  # Find executable nodes in AST
  defp find_executable_nodes(%{children: children}) when is_list(children) do
    Enum.filter(children, &ASTUtils.executable?/1)
  end

  defp find_executable_nodes(_), do: []

  # Extract execution data from result and runtime
  defp extract_execution_data(nil, runtime_pid) do
    # No execution result (e.g., just parsing)
    context = Runtime.get_context(runtime_pid)
    {context.exit_code, [], [], context}
  end

  defp extract_execution_data(result, _runtime_pid) do
    # Use context from execution_result - it already has correct exit_code
    context = Map.get(result, :context)
    exit_code = Map.get(result, :exit_code, 0)
    stdout = Map.get(result, :stdout, [])
    stderr = Map.get(result, :stderr, [])
    {exit_code, stdout, stderr, context}
  end
end
