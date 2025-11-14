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
    Enum.reduce(executable_nodes, nil, fn node, _acc ->
      case Runtime.execute_node(runtime_pid, node) do
        {:ok, context} ->
          # Build execution result from context
          %{
            status: :success,
            node: node,
            node_type: get_node_type(node),
            node_text: get_node_text(node),
            node_line: get_node_line(node),
            exit_code: context.exit_code,
            stdout: context.last_output.stdout,
            stderr: context.last_output.stderr,
            context: context,
            duration_us: 0,  # Already tracked in exec_metrics
            timestamp: DateTime.utc_now()
          }

        {:error, reason} ->
          # Execution failed
          %{
            status: :error,
            node: node,
            node_type: get_node_type(node),
            node_text: get_node_text(node),
            node_line: get_node_line(node),
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

  # Find executable nodes in AST (same logic as IncrementalParser)
  defp find_executable_nodes(%{children: children}) when is_list(children) do
    Enum.filter(children, &is_executable_node?/1)
  end
  defp find_executable_nodes(_), do: []

  # Check if node is executable (same as IncrementalParser.is_executable_node?)
  defp is_executable_node?(typed_node) do
    case typed_node do
      %BashParser.AST.Types.Command{} -> true
      %BashParser.AST.Types.Pipeline{} -> true
      %BashParser.AST.Types.List{} -> true
      %BashParser.AST.Types.Subshell{} -> true
      %BashParser.AST.Types.CompoundStatement{} -> true
      %BashParser.AST.Types.ForStatement{} -> true
      %BashParser.AST.Types.WhileStatement{} -> true
      %BashParser.AST.Types.IfStatement{} -> true
      %BashParser.AST.Types.CaseStatement{} -> true
      %BashParser.AST.Types.FunctionDefinition{} -> true
      %BashParser.AST.Types.DeclarationCommand{} -> true
      %BashParser.AST.Types.VariableAssignment{} -> true
      %BashParser.AST.Types.UnsetCommand{} -> true
      %BashParser.AST.Types.TestCommand{} -> true
      %BashParser.AST.Types.CStyleForStatement{} -> true
      _ -> false
    end
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
