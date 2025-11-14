defmodule RShell.PubSubTest do
  use ExUnit.Case, async: false

  alias RShell.PubSub

  setup do
    # Ensure application is started
    {:ok, _} = Application.ensure_all_started(:rshell)

    session_id = "test_session_#{:erlang.unique_integer([:positive])}"

    on_exit(fn ->
      # Clean up subscriptions
      PubSub.unsubscribe(session_id, [:ast, :executable, :runtime, :output, :context])
    end)

    {:ok, session_id: session_id}
  end

  describe "pubsub_name/0" do
    test "returns the correct PubSub name" do
      assert PubSub.pubsub_name() == :rshell_pubsub
    end
  end

  describe "topic generation" do
    test "ast_topic/1 generates correct topic", %{session_id: session_id} do
      assert PubSub.ast_topic(session_id) == "session:#{session_id}:ast"
    end

    test "executable_topic/1 generates correct topic", %{session_id: session_id} do
      assert PubSub.executable_topic(session_id) == "session:#{session_id}:executable"
    end

    test "runtime_topic/1 generates correct topic", %{session_id: session_id} do
      assert PubSub.runtime_topic(session_id) == "session:#{session_id}:runtime"
    end

    test "output_topic/1 generates correct topic", %{session_id: session_id} do
      assert PubSub.output_topic(session_id) == "session:#{session_id}:output"
    end

    test "context_topic/1 generates correct topic", %{session_id: session_id} do
      assert PubSub.context_topic(session_id) == "session:#{session_id}:context"
    end

    test "topics are unique per session" do
      session1 = "session1"
      session2 = "session2"

      assert PubSub.ast_topic(session1) != PubSub.ast_topic(session2)
      assert PubSub.executable_topic(session1) != PubSub.executable_topic(session2)
    end
  end

  describe "subscribe/2 with specific topics" do
    test "subscribes to single topic", %{session_id: session_id} do
      assert :ok = PubSub.subscribe(session_id, [:ast])

      # Broadcast a message
      message = {:ast_updated, %{"type" => "program"}}
      assert :ok = PubSub.broadcast(session_id, :ast, message)

      # Should receive the message
      assert_receive ^message, 100
    end

    test "subscribes to multiple topics", %{session_id: session_id} do
      assert :ok = PubSub.subscribe(session_id, [:ast, :output])

      # Broadcast to both topics
      ast_msg = {:ast_updated, %{}}
      output_msg = {:stdout, "hello\n"}

      assert :ok = PubSub.broadcast(session_id, :ast, ast_msg)
      assert :ok = PubSub.broadcast(session_id, :output, output_msg)

      # Should receive both messages
      assert_receive ^ast_msg, 100
      assert_receive ^output_msg, 100
    end

    test "subscribes to all available topics", %{session_id: session_id} do
      assert :ok = PubSub.subscribe(session_id, [:ast, :executable, :runtime, :output, :context])

      # Broadcast to each topic
      messages = [
        {:ast, {:ast_updated, %{}}},
        {:executable, {:executable_node, %{}}},
        {:runtime, {:execution_started, 1}},
        {:output, {:stdout, "test"}},
        {:context, {:var_set, "FOO", "bar"}}
      ]

      for {topic, msg} <- messages do
        assert :ok = PubSub.broadcast(session_id, topic, msg)
      end

      # Should receive all messages
      for {_topic, msg} <- messages do
        assert_receive ^msg, 100
      end
    end
  end

  describe "subscribe/2 with :all" do
    test "subscribes to all topics at once", %{session_id: session_id} do
      assert :ok = PubSub.subscribe(session_id, :all)

      # Broadcast to each topic
      messages = [
        {:ast, {:ast_updated, %{}}},
        {:executable, {:executable_node, %{}}},
        {:runtime, {:execution_started, 1}},
        {:output, {:stdout, "test"}},
        {:context, {:var_set, "FOO", "bar"}}
      ]

      for {topic, msg} <- messages do
        assert :ok = PubSub.broadcast(session_id, topic, msg)
      end

      # Should receive all messages
      for {_topic, msg} <- messages do
        assert_receive ^msg, 100
      end
    end
  end

  describe "unsubscribe/2" do
    test "unsubscribes from specific topic", %{session_id: session_id} do
      # Subscribe to both
      PubSub.subscribe(session_id, [:ast, :output])

      # Unsubscribe from one
      assert :ok = PubSub.unsubscribe(session_id, [:ast])

      # Broadcast to both
      ast_msg = {:ast_updated, %{}}
      output_msg = {:stdout, "hello"}

      PubSub.broadcast(session_id, :ast, ast_msg)
      PubSub.broadcast(session_id, :output, output_msg)

      # Should only receive output message
      refute_receive ^ast_msg, 100
      assert_receive ^output_msg, 100
    end

    test "unsubscribes from multiple topics", %{session_id: session_id} do
      # Subscribe to all
      PubSub.subscribe(session_id, :all)

      # Unsubscribe from some
      assert :ok = PubSub.unsubscribe(session_id, [:ast, :executable, :runtime])

      # Broadcast to unsubscribed topics
      PubSub.broadcast(session_id, :ast, {:ast_updated, %{}})
      PubSub.broadcast(session_id, :executable, {:executable_node, %{}})
      PubSub.broadcast(session_id, :runtime, {:execution_started, 1})

      # Should not receive these
      refute_receive {:ast_updated, _}, 100
      refute_receive {:executable_node, _}, 100
      refute_receive {:execution_started, _}, 100

      # But should still receive these
      output_msg = {:stdout, "test"}
      context_msg = {:var_set, "X", "y"}

      PubSub.broadcast(session_id, :output, output_msg)
      PubSub.broadcast(session_id, :context, context_msg)

      assert_receive ^output_msg, 100
      assert_receive ^context_msg, 100
    end
  end

  describe "broadcast/3" do
    test "broadcasts message to subscribed processes", %{session_id: session_id} do
      PubSub.subscribe(session_id, [:ast])

      message = {:ast_updated, %{"type" => "program", "children" => []}}
      assert :ok = PubSub.broadcast(session_id, :ast, message)

      assert_receive ^message, 100
    end

    test "does not broadcast to unsubscribed processes", %{session_id: session_id} do
      # Don't subscribe

      message = {:ast_updated, %{}}
      assert :ok = PubSub.broadcast(session_id, :ast, message)

      refute_receive ^message, 100
    end

    test "broadcasts to multiple subscribers", %{session_id: session_id} do
      # Spawn another process that subscribes
      parent = self()

      child =
        spawn_link(fn ->
          PubSub.subscribe(session_id, [:output])
          send(parent, :child_ready)

          receive do
            msg -> send(parent, {:child_received, msg})
          after
            200 -> send(parent, :child_timeout)
          end
        end)

      # Wait for child to subscribe
      assert_receive :child_ready, 100

      # Parent also subscribes
      PubSub.subscribe(session_id, [:output])

      # Broadcast message
      message = {:stdout, "hello from parent\n"}
      assert :ok = PubSub.broadcast(session_id, :output, message)

      # Both should receive
      assert_receive ^message, 100
      assert_receive {:child_received, ^message}, 100

      # Cleanup
      Process.exit(child, :normal)
    end
  end

  describe "broadcast_from/4" do
    test "excludes sender from broadcast", %{session_id: session_id} do
      # Subscribe in current process
      PubSub.subscribe(session_id, [:runtime])

      # Spawn another process that also subscribes
      parent = self()

      child =
        spawn_link(fn ->
          PubSub.subscribe(session_id, [:runtime])
          send(parent, :child_ready)

          receive do
            msg -> send(parent, {:child_received, msg})
          after
            200 -> send(parent, :child_timeout)
          end
        end)

      # Wait for child to subscribe
      assert_receive :child_ready, 100

      # Broadcast from current process (should exclude self)
      message = {:execution_completed, 1, :ok}
      assert :ok = PubSub.broadcast_from(self(), session_id, :runtime, message)

      # Current process should NOT receive
      refute_receive ^message, 100

      # But child should receive
      assert_receive {:child_received, ^message}, 100

      # Cleanup
      Process.exit(child, :normal)
    end
  end

  describe "session isolation" do
    test "messages don't leak between sessions" do
      session1 = "session_1"
      session2 = "session_2"

      # Subscribe to both sessions
      PubSub.subscribe(session1, [:ast])
      PubSub.subscribe(session2, [:ast])

      # Broadcast to session1
      msg1 = {:ast_updated, %{"session" => 1}}
      PubSub.broadcast(session1, :ast, msg1)

      # Should only receive msg1 once (from session1 subscription)
      assert_receive ^msg1, 100
      refute_receive ^msg1, 100

      # Broadcast to session2
      msg2 = {:ast_updated, %{"session" => 2}}
      PubSub.broadcast(session2, :ast, msg2)

      # Should only receive msg2 once (from session2 subscription)
      assert_receive ^msg2, 100
      refute_receive ^msg2, 100

      # Cleanup
      PubSub.unsubscribe(session1, [:ast])
      PubSub.unsubscribe(session2, [:ast])
    end

    test "different topics in same session don't interfere" do
      session_id = "test_session"

      # Subscribe to different topics
      PubSub.subscribe(session_id, [:ast])
      PubSub.subscribe(session_id, [:output])

      # Broadcast to ast
      ast_msg = {:ast_updated, %{}}
      PubSub.broadcast(session_id, :ast, ast_msg)

      # Should receive ast message
      assert_receive ^ast_msg, 100

      # Broadcast to output
      output_msg = {:stdout, "test"}
      PubSub.broadcast(session_id, :output, output_msg)

      # Should receive output message
      assert_receive ^output_msg, 100

      # No cross-talk
      refute_receive _, 100

      # Cleanup
      PubSub.unsubscribe(session_id, [:ast, :output])
    end
  end

  describe "message formats" do
    test "supports AST update messages", %{session_id: session_id} do
      PubSub.subscribe(session_id, [:ast])

      ast = %{
        "type" => "program",
        "children" => [%{"type" => "command", "text" => "echo hello"}],
        "text" => "echo hello\n"
      }

      message = {:ast_updated, ast}
      PubSub.broadcast(session_id, :ast, message)

      assert_receive {:ast_updated, received_ast}, 100
      assert received_ast == ast
    end

    test "supports executable node messages", %{session_id: session_id} do
      PubSub.subscribe(session_id, [:executable])

      node = %{
        "type" => "command",
        "text" => "ls -la",
        "start_row" => 0,
        "end_row" => 0
      }

      message = {:executable_node, node, 1}
      PubSub.broadcast(session_id, :executable, message)

      assert_receive {:executable_node, ^node, 1}, 100
    end

    test "supports runtime execution messages", %{session_id: session_id} do
      PubSub.subscribe(session_id, [:runtime])

      # Started
      PubSub.broadcast(session_id, :runtime, {:execution_started, 1})
      assert_receive {:execution_started, 1}, 100

      # Completed
      PubSub.broadcast(session_id, :runtime, {:execution_completed, 1, {:ok, 0}})
      assert_receive {:execution_completed, 1, {:ok, 0}}, 100

      # Failed
      PubSub.broadcast(session_id, :runtime, {:execution_failed, 1, {:error, :enoent}})
      assert_receive {:execution_failed, 1, {:error, :enoent}}, 100
    end

    test "supports output messages", %{session_id: session_id} do
      PubSub.subscribe(session_id, [:output])

      # Stdout
      PubSub.broadcast(session_id, :output, {:stdout, "hello world\n"})
      assert_receive {:stdout, "hello world\n"}, 100

      # Stderr
      PubSub.broadcast(session_id, :output, {:stderr, "error: file not found\n"})
      assert_receive {:stderr, "error: file not found\n"}, 100
    end

    test "supports context change messages", %{session_id: session_id} do
      PubSub.subscribe(session_id, [:context])

      # Variable set
      PubSub.broadcast(session_id, :context, {:var_set, "PATH", "/usr/bin"})
      assert_receive {:var_set, "PATH", "/usr/bin"}, 100

      # Working directory changed
      PubSub.broadcast(session_id, :context, {:cwd_changed, "/home/user"})
      assert_receive {:cwd_changed, "/home/user"}, 100

      # Function defined
      PubSub.broadcast(session_id, :context, {:function_defined, "my_func"})
      assert_receive {:function_defined, "my_func"}, 100

      # Alias defined
      PubSub.broadcast(session_id, :context, {:alias_defined, "ll", "ls -la"})
      assert_receive {:alias_defined, "ll", "ls -la"}, 100
    end
  end

  describe "error handling" do
    test "handles invalid topic atoms gracefully" do
      session_id = "test"

      # This should raise FunctionClauseError since there's no topic_for clause for :invalid
      assert_raise FunctionClauseError, fn ->
        PubSub.subscribe(session_id, [:invalid_topic])
      end
    end

    test "broadcast succeeds even with no subscribers", %{session_id: session_id} do
      # Don't subscribe, just broadcast
      assert :ok = PubSub.broadcast(session_id, :ast, {:test_message, "no subscribers"})
    end
  end
end
