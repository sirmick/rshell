defmodule RShell.Runtime.FrameStackTest do
  use ExUnit.Case, async: true
  alias RShell.Runtime.FrameStack

  describe "stream-based output" do
    test "accepts lists and converts to streams" do
      stack = FrameStack.new()
      stack = FrameStack.add_output(stack, ["hello\n"], [])

      output = FrameStack.get_output(stack)
      assert Enum.to_list(output.stdout) == ["hello\n"]
      assert Enum.to_list(output.stderr) == []
    end

    test "accepts streams directly" do
      stack = FrameStack.new()
      stream = Stream.map(["world\n"], & &1)
      stack = FrameStack.add_output(stack, stream, Stream.map([], & &1))

      output = FrameStack.get_output(stack)
      assert Enum.to_list(output.stdout) == ["world\n"]
    end

    test "accepts binary strings" do
      stack = FrameStack.new()
      stack = FrameStack.add_output(stack, "hello\n", "")

      output = FrameStack.get_output(stack)
      assert Enum.to_list(output.stdout) == ["hello\n"]
      assert Enum.to_list(output.stderr) == []
    end

    test "accumulate mode concatenates streams lazily" do
      stack = FrameStack.new(output_mode: :accumulate)

      stack = FrameStack.add_output(stack, ["a"], [])
      stack = FrameStack.add_output(stack, ["b"], [])
      stack = FrameStack.add_output(stack, ["c"], [])

      output = FrameStack.get_output(stack)
      assert Enum.to_list(output.stdout) == ["a", "b", "c"]
    end

    test "isolate mode replaces streams" do
      stack = FrameStack.new(output_mode: :isolate)

      stack = FrameStack.add_output(stack, ["first"], [])
      stack = FrameStack.add_output(stack, ["second"], [])

      output = FrameStack.get_output(stack)
      assert Enum.to_list(output.stdout) == ["second"]
    end

    test "mixed types in accumulate mode" do
      stack = FrameStack.new(output_mode: :accumulate)

      # Add list
      stack = FrameStack.add_output(stack, ["line1\n"], [])
      # Add string
      stack = FrameStack.add_output(stack, "line2\n", "")
      # Add stream
      stream = Stream.map(["line3\n"], & &1)
      stack = FrameStack.add_output(stack, stream, Stream.map([], & &1))

      output = FrameStack.get_output(stack)
      assert Enum.to_list(output.stdout) == ["line1\n", "line2\n", "line3\n"]
    end

    test "clear_output resets to empty streams" do
      stack = FrameStack.new()
      stack = FrameStack.add_output(stack, ["test\n"], [])
      stack = FrameStack.clear_output(stack)

      output = FrameStack.get_output(stack)
      assert Enum.to_list(output.stdout) == []
      assert Enum.to_list(output.stderr) == []
    end

    test "stderr works with streams" do
      stack = FrameStack.new(output_mode: :accumulate)

      stack = FrameStack.add_output(stack, ["out1"], ["err1"])
      stack = FrameStack.add_output(stack, ["out2"], ["err2"])

      output = FrameStack.get_output(stack)
      assert Enum.to_list(output.stdout) == ["out1", "out2"]
      assert Enum.to_list(output.stderr) == ["err1", "err2"]
    end

    test "pop_frame returns accumulated streams" do
      stack = FrameStack.new(output_mode: :accumulate)
      stack = FrameStack.push_frame(stack, :loop, :accumulate)

      # Add output to loop frame
      stack = FrameStack.add_output(stack, ["iter1"], [])
      stack = FrameStack.add_output(stack, ["iter2"], [])

      # Pop frame
      {_stack, output} = FrameStack.pop_frame(stack)

      # Output is streams
      assert Enum.to_list(output.stdout) == ["iter1", "iter2"]
      assert Enum.to_list(output.stderr) == []
    end

    test "empty string becomes empty stream" do
      stack = FrameStack.new()
      stack = FrameStack.add_output(stack, "", "")

      output = FrameStack.get_output(stack)
      assert Enum.to_list(output.stdout) == []
      assert Enum.to_list(output.stderr) == []
    end
  end

  describe "backwards compatibility" do
    test "existing code using lists continues to work" do
      stack = FrameStack.new(output_mode: :accumulate)

      # Old-style: pass lists
      stack = FrameStack.add_output(stack, ["line1\n"], [])
      stack = FrameStack.add_output(stack, ["line2\n"], [])

      # Get output and materialize
      output = FrameStack.get_output(stack)
      stdout = Enum.to_list(output.stdout)

      assert stdout == ["line1\n", "line2\n"]
    end

    test "new initialization creates empty streams" do
      stack = FrameStack.new()
      output = FrameStack.get_output(stack)

      # Should be enumerables (Stream structs)
      assert is_struct(output.stdout, Stream)
      assert is_struct(output.stderr, Stream)

      # But materialize to empty lists
      assert Enum.to_list(output.stdout) == []
      assert Enum.to_list(output.stderr) == []
    end
  end
end
