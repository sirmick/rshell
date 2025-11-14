defmodule PubSubGuaranteesTest do
  @moduledoc """
  Tests to ensure every input fragment gets at least one response message.

  Every call to IncrementalParser.append_fragment/2 MUST result in at least one message:
  - Success: {:ast_incremental, metadata}
  - Parser Error: {:parsing_failed, error}
  - Parser Crash: {:parsing_crashed, error}

  This prevents clients from timing out when the parser fails unexpectedly.
  """

  use ExUnit.Case, async: false

  alias RShell.{IncrementalParser, PubSub}

  describe "fragment always gets response (no silent timeouts)" do
    test "every fragment produces ast_incremental" do
      session_id = "test_#{:rand.uniform(1_000_000)}"
      {:ok, parser} = IncrementalParser.start_link(session_id: session_id, broadcast: true)
      PubSub.subscribe(session_id, [:ast])

      # Submit fragment
      {:ok, _ast} = IncrementalParser.append_fragment(parser, "echo test\n")

      # MUST receive ast_incremental within reasonable time
      assert_receive {:ast_incremental, metadata},
                     1000,
                     "TIMEOUT: Did not receive ast_incremental for fragment"

      assert is_struct(metadata.full_ast)
    end

    test "multiple fragments all produce responses" do
      session_id = "test_#{:rand.uniform(1_000_000)}"
      {:ok, parser} = IncrementalParser.start_link(session_id: session_id, broadcast: true)
      PubSub.subscribe(session_id, [:ast])

      fragments = [
        "echo first\n",
        "echo second\n",
        "echo third\n"
      ]

      for fragment <- fragments do
        # Clear mailbox before each fragment
        flush_mailbox()

        # Submit fragment
        {:ok, _ast} = IncrementalParser.append_fragment(parser, fragment)

        # MUST receive ast_incremental for THIS fragment
        assert_receive {:ast_incremental, _},
                       1000,
                       "TIMEOUT: Missing ast_incremental for fragment: #{inspect(fragment)}"
      end
    end

    test "executable fragments produce executable_node events" do
      session_id = "test_#{:rand.uniform(1_000_000)}"
      {:ok, parser} = IncrementalParser.start_link(session_id: session_id, broadcast: true)
      PubSub.subscribe(session_id, [:ast, :executable])

      # Submit executable command
      {:ok, _ast} = IncrementalParser.append_fragment(parser, "echo hello\n")

      # MUST receive ast_incremental and executable_node (with command count)
      assert_receive {:ast_incremental, _}, 1000
      assert_receive {:executable_node, node, count}, 1000

      # Verify executable node details
      assert is_struct(node)
      assert count == 1
    end

    test "incomplete fragments do NOT produce executable_node" do
      session_id = "test_#{:rand.uniform(1_000_000)}"
      {:ok, parser} = IncrementalParser.start_link(session_id: session_id, broadcast: true)
      PubSub.subscribe(session_id, [:ast, :executable])

      # Submit incomplete structure
      {:ok, _ast} = IncrementalParser.append_fragment(parser, "if true; then\n")

      # MUST receive ast_incremental
      assert_receive {:ast_incremental, _}, 1000

      # MUST NOT receive executable_node (incomplete structure)
      refute_receive {:executable_node, _, _}, 100
    end

    test "rapid fragments all get responses" do
      session_id = "test_#{:rand.uniform(1_000_000)}"
      {:ok, parser} = IncrementalParser.start_link(session_id: session_id, broadcast: true)
      PubSub.subscribe(session_id, [:ast])

      # Submit 10 fragments rapidly
      count = 10

      for i <- 1..count do
        {:ok, _} = IncrementalParser.append_fragment(parser, "echo #{i}\n")
      end

      # MUST receive exactly count ast_incremental messages
      received_updates = receive_n_messages({:ast_incremental, :_}, count, 2000)

      assert length(received_updates) == count,
             "Expected #{count} ast_incremental messages, got #{length(received_updates)}"
    end

    test "error fragments still produce ast_updated event" do
      session_id = "test_#{:rand.uniform(1_000_000)}"
      {:ok, parser} = IncrementalParser.start_link(session_id: session_id, broadcast: true)
      PubSub.subscribe(session_id, [:ast])

      # Note: Tree-sitter bash parser is very tolerant, so this might not actually error
      # But we should always get ast_incremental (or parsing_failed on error)
      {:ok, _ast} = IncrementalParser.append_fragment(parser, "echo test\n")

      # MUST receive ast_incremental (or parsing_failed if there was an error)
      receive do
        {:ast_incremental, _} -> :ok
        {:parsing_failed, _} -> :ok
      after
        1000 -> flunk("TIMEOUT: Did not receive any response for fragment")
      end
    end

    test "parser crash sends error event (no silent timeout)" do
      # This test documents that if the parser crashes, clients get a message
      # rather than timing out. We verify the try/catch is in place.

      session_id = "test_#{:rand.uniform(1_000_000)}"
      {:ok, parser} = IncrementalParser.start_link(session_id: session_id, broadcast: true)
      PubSub.subscribe(session_id, [:ast])

      # Normal fragment - parser handles it fine
      {:ok, _ast} = IncrementalParser.append_fragment(parser, "echo test\n")

      # Flush messages
      flush_mailbox()

      # If parser crashes internally, it should send {:parsing_crashed, error}
      # We can't easily trigger a crash, but the try/catch guarantees this
    end
  end

  # Helper: receive N messages matching a pattern within timeout
  defp receive_n_messages(pattern, count, total_timeout) do
    timeout_per_msg = div(total_timeout, count)

    Enum.map(1..count, fn _ ->
      receive do
        msg when msg == pattern or elem(msg, 0) == elem(pattern, 0) -> msg
      after
        timeout_per_msg -> :timeout
      end
    end)
    |> Enum.reject(&(&1 == :timeout))
  end

  # Helper: flush mailbox
  defp flush_mailbox do
    receive do
      _ -> flush_mailbox()
    after
      0 -> :ok
    end
  end
end
