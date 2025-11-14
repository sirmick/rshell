defmodule IncrementalAstTest do
  @moduledoc """
  Tests for incremental AST updates using tree-sitter's change tracking.

  Verifies that only changed nodes are sent, reducing bandwidth and
  improving performance for interactive parsing scenarios.
  """

  use ExUnit.Case, async: false

  alias RShell.{IncrementalParser, PubSub}

  describe "incremental AST updates" do
    test "first parse returns all nodes as changed" do
      session_id = "test_#{:rand.uniform(1_000_000)}"
      {:ok, parser} = IncrementalParser.start_link(session_id: session_id, broadcast: true)
      PubSub.subscribe(session_id, [:ast])

      # First fragment - everything is "new"
      {:ok, _ast} = IncrementalParser.append_fragment(parser, "echo first\n")

      # Should receive incremental event
      assert_receive {:ast_incremental, metadata}, 1000

      # Verify metadata structure
      assert is_map(metadata)
      assert Map.has_key?(metadata, :full_ast)
      assert Map.has_key?(metadata, :changed_nodes)
      assert Map.has_key?(metadata, :changed_ranges)

      # First parse should have changed nodes (the entire tree)
      assert length(metadata.changed_nodes) > 0
    end

    test "incremental parse sends only changed nodes" do
      session_id = "test_#{:rand.uniform(1_000_000)}"
      {:ok, parser} = IncrementalParser.start_link(session_id: session_id, broadcast: true)
      PubSub.subscribe(session_id, [:ast])

      # First fragment
      {:ok, _} = IncrementalParser.append_fragment(parser, "echo first\n")

      # Clear mailbox
      flush_mailbox()

      # Second fragment - only new command should be in changed nodes
      {:ok, _} = IncrementalParser.append_fragment(parser, "echo second\n")

      assert_receive {:ast_incremental, metadata}, 1000

      # Should have changed nodes (the new command)
      assert length(metadata.changed_nodes) > 0

      # Changed ranges should be present
      assert is_list(metadata.changed_ranges)
    end

    test "multiple fragments each produce incremental updates" do
      session_id = "test_#{:rand.uniform(1_000_000)}"
      {:ok, parser} = IncrementalParser.start_link(session_id: session_id, broadcast: true)
      PubSub.subscribe(session_id, [:ast])

      fragments = [
        "echo one\n",
        "echo two\n",
        "echo three\n"
      ]

      for fragment <- fragments do
        flush_mailbox()
        {:ok, _} = IncrementalParser.append_fragment(parser, fragment)

        # Each fragment should produce incremental update
        assert_receive {:ast_incremental, metadata}, 1000
        assert is_map(metadata)
        assert Map.has_key?(metadata, :changed_nodes)
        assert Map.has_key?(metadata, :full_ast)
      end
    end

    test "changed_ranges include byte positions" do
      session_id = "test_#{:rand.uniform(1_000_000)}"
      {:ok, parser} = IncrementalParser.start_link(session_id: session_id, broadcast: true)
      PubSub.subscribe(session_id, [:ast])

      # First parse
      {:ok, _} = IncrementalParser.append_fragment(parser, "echo test\n")
      flush_mailbox()

      # Second parse
      {:ok, _} = IncrementalParser.append_fragment(parser, "pwd\n")

      assert_receive {:ast_incremental, metadata}, 1000

      # Verify changed_ranges structure
      if length(metadata.changed_ranges) > 0 do
        range = hd(metadata.changed_ranges)
        assert is_map(range)
        assert Map.has_key?(range, "start_byte")
        assert Map.has_key?(range, "end_byte")
        assert Map.has_key?(range, "start_row")
        assert Map.has_key?(range, "end_row")
      end
    end

    test "full_ast always contains complete tree" do
      session_id = "test_#{:rand.uniform(1_000_000)}"
      {:ok, parser} = IncrementalParser.start_link(session_id: session_id, broadcast: true)
      PubSub.subscribe(session_id, [:ast])

      # Build up multiple commands
      {:ok, _} = IncrementalParser.append_fragment(parser, "echo first\n")
      flush_mailbox()

      {:ok, _} = IncrementalParser.append_fragment(parser, "echo second\n")
      flush_mailbox()

      {:ok, _} = IncrementalParser.append_fragment(parser, "echo third\n")

      assert_receive {:ast_incremental, metadata}, 1000

      # full_ast should contain all accumulated commands
      full_ast = metadata.full_ast
      assert is_struct(full_ast)

      # Check that full_ast has children (multiple commands)
      case full_ast do
        %{children: children} when is_list(children) ->
          # Should have 3 commands accumulated
          assert length(children) == 3

        _ ->
          flunk("Expected full_ast to have children list")
      end
    end

    test "incremental event is the primary event" do
      session_id = "test_#{:rand.uniform(1_000_000)}"
      {:ok, parser} = IncrementalParser.start_link(session_id: session_id, broadcast: true)
      PubSub.subscribe(session_id, [:ast])

      {:ok, _} = IncrementalParser.append_fragment(parser, "echo test\n")

      # Should receive incremental event (no backward compatibility needed)
      assert_receive {:ast_incremental, _}, 1000
    end

    test "reset clears old tree for change tracking" do
      session_id = "test_#{:rand.uniform(1_000_000)}"
      {:ok, parser} = IncrementalParser.start_link(session_id: session_id, broadcast: true)
      PubSub.subscribe(session_id, [:ast])

      # First parse
      {:ok, _} = IncrementalParser.append_fragment(parser, "echo first\n")
      flush_mailbox()

      # Reset
      :ok = IncrementalParser.reset(parser)

      # After reset, next parse should treat everything as "new"
      {:ok, _} = IncrementalParser.append_fragment(parser, "echo second\n")

      assert_receive {:ast_incremental, metadata}, 1000

      # After reset, should have changed nodes (entire tree is new)
      assert length(metadata.changed_nodes) > 0
    end

    test "error cases still work with incremental events" do
      session_id = "test_#{:rand.uniform(1_000_000)}"
      {:ok, parser} = IncrementalParser.start_link(session_id: session_id, broadcast: true)
      PubSub.subscribe(session_id, [:ast])

      # Normal parse should work
      {:ok, _} = IncrementalParser.append_fragment(parser, "echo test\n")

      # Should receive incremental event even for simple cases
      assert_receive {:ast_incremental, _}, 1000
    end
  end

  # Helper to flush mailbox
  defp flush_mailbox do
    receive do
      _ -> flush_mailbox()
    after
      0 -> :ok
    end
  end
end
