defmodule RShell.PubSub do
  @moduledoc """
  PubSub topic definitions and subscription helpers.

  Provides a centralized way to manage Phoenix.PubSub topics for RShell's
  event-driven architecture. Each session has its own namespace of topics
  for isolation.

  ## Topics (per session)

  - `session:{id}:ast` - AST updates from parser
  - `session:{id}:executable` - Executable nodes ready for execution
  - `session:{id}:runtime` - Runtime execution events
  - `session:{id}:output` - Command output (stdout/stderr)
  - `session:{id}:context` - Context changes (vars, cwd, functions)

  ## Examples

      # Subscribe to specific topics
      RShell.PubSub.subscribe("my_session", [:ast, :output])

      # Subscribe to all topics
      RShell.PubSub.subscribe("my_session", :all)

      # Broadcast a message
      RShell.PubSub.broadcast("my_session", :ast, {:ast_updated, ast})
  """

  @pubsub_name :rshell_pubsub

  @doc "Get the PubSub process name"
  def pubsub_name, do: @pubsub_name

  # Topic generators

  @doc "Generate AST topic for a session"
  def ast_topic(session_id), do: "session:#{session_id}:ast"

  @doc "Generate executable topic for a session"
  def executable_topic(session_id), do: "session:#{session_id}:executable"

  @doc "Generate runtime topic for a session"
  def runtime_topic(session_id), do: "session:#{session_id}:runtime"

  @doc "Generate output topic for a session"
  def output_topic(session_id), do: "session:#{session_id}:output"

  @doc "Generate context topic for a session"
  def context_topic(session_id), do: "session:#{session_id}:context"

  @doc """
  Subscribe to specific topics for a session.

  ## Examples

      # Subscribe to specific topics
      RShell.PubSub.subscribe("my_session", [:ast, :output])

      # Subscribe to all topics
      RShell.PubSub.subscribe("my_session", :all)
  """
  @spec subscribe(String.t(), :all | [atom()]) :: :ok
  def subscribe(session_id, :all) do
    subscribe(session_id, [:ast, :executable, :runtime, :output, :context])
  end

  def subscribe(session_id, topic_atoms) when is_list(topic_atoms) do
    Enum.each(topic_atoms, fn atom ->
      topic = topic_for(session_id, atom)
      Phoenix.PubSub.subscribe(@pubsub_name, topic)
    end)
  end

  @doc """
  Unsubscribe from topics.

  ## Examples

      RShell.PubSub.unsubscribe("my_session", [:ast])
  """
  @spec unsubscribe(String.t(), [atom()]) :: :ok
  def unsubscribe(session_id, topic_atoms) when is_list(topic_atoms) do
    Enum.each(topic_atoms, fn atom ->
      topic = topic_for(session_id, atom)
      Phoenix.PubSub.unsubscribe(@pubsub_name, topic)
    end)
  end

  @doc """
  Broadcast a message to a topic.

  ## Examples

      RShell.PubSub.broadcast("my_session", :ast, {:ast_updated, ast})
      RShell.PubSub.broadcast("my_session", :output, {:stdout, "hello\\n"})
  """
  @spec broadcast(String.t(), atom(), term()) :: :ok | {:error, term()}
  def broadcast(session_id, topic_atom, message) do
    topic = topic_for(session_id, topic_atom)
    Phoenix.PubSub.broadcast(@pubsub_name, topic, message)
  end

  @doc """
  Broadcast a message to a topic from a specific node.

  Similar to broadcast/3 but uses broadcast_from/4 to exclude the sender.
  """
  @spec broadcast_from(pid(), String.t(), atom(), term()) :: :ok | {:error, term()}
  def broadcast_from(from_pid, session_id, topic_atom, message) do
    topic = topic_for(session_id, topic_atom)
    Phoenix.PubSub.broadcast_from(@pubsub_name, from_pid, topic, message)
  end

  # Private helpers

  defp topic_for(session_id, :ast), do: ast_topic(session_id)
  defp topic_for(session_id, :executable), do: executable_topic(session_id)
  defp topic_for(session_id, :runtime), do: runtime_topic(session_id)
  defp topic_for(session_id, :output), do: output_topic(session_id)
  defp topic_for(session_id, :context), do: context_topic(session_id)
end
