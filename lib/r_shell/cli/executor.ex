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
      {:ok, _ast} ->
        parse_metrics = Metrics.stop(parse_metrics)

        # Collect AST event (still async for observability)
        {incremental_ast, full_ast} = collect_ast_event(state.session_id, 100)

        # Start execution metrics
        exec_metrics = Metrics.start()

        # SYNCHRONOUS execution - execute only INCREMENTAL nodes (changed_nodes), not full AST
        # This prevents re-executing nodes from previous fragments
        execution_result = execute_ast_synchronously_incremental(incremental_ast, state.runtime_pid, state.session_id)

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

  # Execute incremental AST nodes only (changed_nodes from parser)
  # This prevents re-executing nodes from previous fragments
  defp execute_ast_synchronously_incremental(changed_nodes, runtime_pid, _session_id) when is_list(changed_nodes) do
    # Filter to only executable nodes
    executable_nodes = Enum.filter(changed_nodes, &ASTUtils.executable?/1)

    # Execute each node synchronously
    execute_nodes_list(executable_nodes, runtime_pid)
  end

  defp execute_ast_synchronously_incremental(nil, _runtime_pid, _session_id) do
    # No incremental nodes - nothing to execute
    nil
  end

  # Execute a list of nodes and return the last result
  defp execute_nodes_list(nodes, runtime_pid) do
    # CRITICAL: Return the LAST result, but keep executing all nodes
    Enum.reduce(nodes, nil, fn node, _prev_result ->
      case Runtime.execute_node(runtime_pid, node) do
        {:ok, context} ->
          # Get frame_stack from runtime to access output
          runtime_state = :sys.get_state(runtime_pid)
          frame_output = RShell.Runtime.FrameStack.get_output(runtime_state.frame_stack)

          # CRITICAL: Materialize streams BEFORE clearing FrameStack
          # ExecutionRecord is a persistent snapshot - must hold actual data, not lazy references
          # Streams would become empty after clear_output() invalidates the source data
          stdout_list = Enum.to_list(frame_output.stdout)
          stderr_list = Enum.to_list(frame_output.stderr)

          # Build execution result with materialized lists
          result = %{
            status: :success,
            node: node,
            node_type: ASTUtils.node_type(node),
            node_text: ASTUtils.node_text(node),
            node_line: ASTUtils.node_line(node),
            exit_code: context.exit_code,
            stdout: stdout_list,
            stderr: stderr_list,
            context: context,
            # Already tracked in exec_metrics
            duration_us: 0,
            timestamp: DateTime.utc_now()
          }

          # Clear FrameStack to prevent output leakage to next command
          cleared_stack = RShell.Runtime.FrameStack.clear_output(runtime_state.frame_stack)
          :sys.replace_state(runtime_pid, fn state -> %{state | frame_stack: cleared_stack} end)

          result

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
