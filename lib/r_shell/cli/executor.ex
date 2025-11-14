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

  @doc """
  Execute a script fragment and return updated state with execution record.

  This is the core execution function used by all CLI modes.
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

        # Start execution metrics
        exec_metrics = Metrics.start()

        # Collect events (AST, execution results)
        {incremental_ast, full_ast, execution_result} =
          collect_events(state.session_id, 5000)

        exec_metrics = Metrics.stop(exec_metrics)

        # Extract output and context from execution result
        {exit_code, stdout, stderr, context} = extract_execution_data(
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
        {:ok, new_state}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Collect PubSub events after parsing
  #
  # The parser ALWAYS sends one of these events immediately:
  # - :ast_incremental (success)
  # - :parsing_failed (error)
  # - :parsing_crashed (crash)
  #
  # If tree has no errors, it may also send:
  # - :executable_node (one per executable node)
  #
  # If executable nodes were sent, runtime will send:
  # - :execution_result (one per execution)
  # - :variable_set (for variable assignments)
  defp collect_events(_session_id, _initial_timeout) do
    # Wait for the mandatory AST event (no timeout needed - parser always sends it)
    receive do
      {:ast_incremental, metadata} ->
        # Got AST, now collect any executable nodes and execution results
        new_incremental = metadata.changed_nodes
        new_full = metadata.full_ast
        collect_execution_events(100, new_incremental, new_full, nil)

      {:parsing_failed, _error} ->
        # Parse failed, no AST
        {nil, nil, nil}

      {:parsing_crashed, _error} ->
        # Parser crashed, no AST
        {nil, nil, nil}
    end
  end

  # After receiving AST event, collect any execution-related events
  # Use short timeout since these events are sent immediately if tree has no errors
  defp collect_execution_events(timeout, incremental_ast, full_ast, execution_result) do
    receive do
      {:executable_node, _typed_node, _count} ->
        # Executable node detected, wait for execution result
        collect_execution_events(timeout, incremental_ast, full_ast, execution_result)

      {:execution_result, result} ->
        # Execution complete, collect any additional events briefly
        collect_execution_events(100, incremental_ast, full_ast, result)

      {:variable_set, _info} ->
        # Variable was set, continue collecting
        collect_execution_events(timeout, incremental_ast, full_ast, execution_result)

    after
      timeout ->
        # No more events, return collected data
        {incremental_ast, full_ast, execution_result}
    end
  end

  # Extract execution data from result and runtime
  defp extract_execution_data(nil, runtime_pid) do
    # No execution result (e.g., just parsing)
    context = Runtime.get_context(runtime_pid)
    {context.exit_code, [], [], context}
  end

  defp extract_execution_data(result, runtime_pid) do
    context = Runtime.get_context(runtime_pid)
    exit_code = Map.get(result, :exit_code, context.exit_code)
    stdout = Map.get(result, :stdout, [])
    stderr = Map.get(result, :stderr, [])
    {exit_code, stdout, stderr, context}
  end
end
