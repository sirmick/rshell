defmodule RShell.Runtime.ExecutionPipeline do
  @moduledoc """
  Clean execution pipeline separating execution from broadcasting concerns.

  Eliminates process dictionary usage and provides single point of control
  for all execution and broadcasting logic.
  """

  alias RShell.PubSub

  defstruct [
    :node,
    :context,
    :session_id,
    :start_time,
    :result,
    :duration
  ]

  @doc """
  Execute a node through the pipeline, handling execution and broadcasting.

  Returns the updated context.
  """
  def execute(node, context, session_id) do
    %__MODULE__{
      node: node,
      context: context,
      session_id: session_id,
      start_time: System.monotonic_time(:microsecond)
    }
    |> run_execution()
    |> calculate_duration()
    |> broadcast_if_needed()
    |> extract_context()
  end

  # Execute the node, capturing success or error
  defp run_execution(%{node: node, context: ctx, session_id: sid} = pipeline) do
    require Logger
    try do
      # Delegate to actual execution logic (imported from Runtime module)
      new_context = RShell.Runtime.do_execute_node(node, ctx, sid)

      # DEBUG: Log what do_execute_node returned
      Logger.debug("ExecutionPipeline.run_execution: do_execute_node returned context.exit_code=#{new_context.exit_code}")

      %{pipeline | result: {:ok, new_context}}
    rescue
      e ->
        %{pipeline | result: {:error, e}}
    end
  end

  # Calculate execution duration
  defp calculate_duration(pipeline) do
    duration = System.monotonic_time(:microsecond) - pipeline.start_time
    %{pipeline | duration: duration}
  end

  # Broadcast execution result for ALL executable nodes
  # This ensures control flow nodes (if/for/while) propagate accumulated output
  defp broadcast_if_needed(pipeline) do
    case pipeline.result do
      {:ok, ctx} ->
        # Broadcast for any successful execution
        broadcast_success(pipeline, ctx)

      {:error, error} ->
        broadcast_failure(pipeline, error)
    end

    pipeline
  end

  # Extract final context from pipeline
  defp extract_context(%{result: {:ok, ctx}}), do: ctx
  defp extract_context(%{context: ctx}), do: ctx

  # Broadcast successful execution
  # NOTE: Output is now in FrameStack, not context.last_output
  # But for now, we'll broadcast empty arrays since we don't have access to ExecutionState here
  defp broadcast_success(pipeline, new_context) do
    result = %{
      status: :success,
      node: pipeline.node,
      node_type: get_node_type(pipeline.node),
      node_text: get_node_text(pipeline.node),
      node_line: get_node_line(pipeline.node),
      exit_code: new_context.exit_code,
      stdout: [],  # Output is in FrameStack, not accessible here
      stderr: [],  # Output is in FrameStack, not accessible here
      context: %{
        env: new_context.env,
        cwd: new_context.cwd,
        exit_code: new_context.exit_code
      },
      duration_us: pipeline.duration,
      timestamp: DateTime.utc_now()
    }

    PubSub.broadcast(pipeline.session_id, :runtime, {:execution_result, result})
  end

  # Broadcast execution failure
  defp broadcast_failure(pipeline, exception) do
    error_reason =
      case exception do
        %RuntimeError{} -> "NotImplementedError"
        _ -> exception.__struct__ |> Module.split() |> List.last()
      end

    result = %{
      status: :error,
      node: pipeline.node,
      node_type: get_node_type(pipeline.node),
      node_text: get_node_text(pipeline.node),
      node_line: get_node_line(pipeline.node),
      error: Exception.message(exception),
      reason: error_reason,
      stdout: "",
      stderr: "",
      exit_code: nil,
      timestamp: DateTime.utc_now()
    }

    PubSub.broadcast(pipeline.session_id, :runtime, {:execution_result, result})
  end

  # Helper: Extract node type safely
  defp get_node_type(node) when is_struct(node) do
    node.__struct__ |> Module.split() |> List.last()
  end

  defp get_node_type(_), do: "Unknown"

  # Helper: Extract node text safely
  defp get_node_text(%{source_info: %{text: text}}) when is_binary(text), do: text
  defp get_node_text(_), do: nil

  # Helper: Extract node line safely
  defp get_node_line(%{source_info: %{start_line: line}}) when is_integer(line), do: line
  defp get_node_line(_), do: nil
end
