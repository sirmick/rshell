defmodule StreamParserTest do
  use ExUnit.Case

  alias RShell.StreamParser
  import TestHelperTypedAST

  @moduledoc """
  Tests for the StreamParser synchronous wrapper.

  These tests demonstrate the efficient GenServer reuse pattern:
  - Single GenServer started once and reused across tests
  - Parser state reset between tests for isolation
  - Much faster than creating new resources per test
  """

  describe "parse/1" do
    test "parses a simple command" do
      assert {:ok, ast} = StreamParser.parse("echo 'hello'\n")
      assert get_type(ast) == "program"
      assert is_list(get_children(ast))
    end

    test "auto-resets between calls" do
      # First parse
      {:ok, _ast1} = StreamParser.parse("echo 'first'\n")

      # Second parse should NOT contain 'first' (auto-reset)
      {:ok, _ast2} = StreamParser.parse("echo 'second'\n")

      # Verify only 'second' is in buffer
      pid = StreamParser.parser_pid()
      input = RShell.IncrementalParser.get_accumulated_input(pid)
      assert input == "echo 'second'\n"
      refute String.contains?(input, "first")
    end

    test "handles parse errors gracefully" do
      # Invalid syntax
      {:ok, ast} = StreamParser.parse("if then fi\n")

      # Should parse but have errors
      assert get_type(ast) == "program"
      pid = StreamParser.parser_pid()
      assert RShell.IncrementalParser.has_errors?(pid) == true
    end

    test "supports reset: false option" do
      # Parse without reset
      {:ok, _ast1} = StreamParser.parse("echo 'first'\n")
      {:ok, _ast2} = StreamParser.parse("echo 'second'\n", reset: false)

      # Should have both fragments
      pid = StreamParser.parser_pid()
      input = RShell.IncrementalParser.get_accumulated_input(pid)
      assert String.contains?(input, "first")
      assert String.contains?(input, "second")
    end
  end

  describe "parse_fragments/1" do
    test "accumulates multiple fragments" do
      fragments = [
        "echo 'hello'\n",
        "echo 'world'\n"
      ]

      {:ok, ast} = StreamParser.parse_fragments(fragments)

      assert get_type(ast) == "program"
      pid = StreamParser.parser_pid()
      input = RShell.IncrementalParser.get_accumulated_input(pid)
      assert String.contains?(input, "hello")
      assert String.contains?(input, "world")
    end

    test "completes incomplete fragments" do
      fragments = [
        "if [ -f file ]; then\n",
        "  echo 'exists'\n",
        "fi\n"
      ]

      {:ok, ast} = StreamParser.parse_fragments(fragments)

      assert get_type(ast) == "program"
      assert length(get_children(ast)) >= 1
    end

    test "returns error for empty list" do
      assert {:error, :no_fragments} = StreamParser.parse_fragments([])
    end
  end

  describe "parser lifecycle" do
    test "reuses same GenServer across calls" do
      {:ok, _} = StreamParser.parse("echo 'test1'\n")
      pid1 = StreamParser.parser_pid()

      {:ok, _} = StreamParser.parse("echo 'test2'\n")
      pid2 = StreamParser.parser_pid()

      # Should be same PID (reused)
      assert pid1 == pid2
      assert Process.alive?(pid1)
    end

    test "parser_pid returns nil before first use" do
      # Stop any existing parser
      StreamParser.stop()

      # Should be nil
      assert StreamParser.parser_pid() == nil

      # Start it
      {:ok, _} = StreamParser.parse("echo 'test'\n")
      assert is_pid(StreamParser.parser_pid())
    end
  end

  describe "reset/0" do
    test "explicitly resets parser state" do
      {:ok, _} = StreamParser.parse("echo 'before'\n", reset: false)

      pid = StreamParser.parser_pid()
      size_before = RShell.IncrementalParser.get_buffer_size(pid)
      assert size_before > 0

      :ok = StreamParser.reset()

      size_after = RShell.IncrementalParser.get_buffer_size(pid)
      assert size_after == 0
    end

    test "returns error when parser not started" do
      StreamParser.stop()
      assert {:error, :not_started} = StreamParser.reset()
    end
  end

  describe "performance" do
    test "is fast due to GenServer reuse" do
      # Warmup
      StreamParser.parse("echo 'warmup'\n")

      # Measure 100 parses
      start_time = System.monotonic_time(:millisecond)

      for i <- 1..100 do
        {:ok, _} = StreamParser.parse("echo 'test#{i}'\n")
      end

      end_time = System.monotonic_time(:millisecond)
      duration = end_time - start_time

      # Should be very fast (< 500ms for 100 parses on most systems)
      # This is much faster than creating new resources each time
      assert duration < 1000, "100 parses took #{duration}ms, expected < 1000ms"
    end
  end
end
