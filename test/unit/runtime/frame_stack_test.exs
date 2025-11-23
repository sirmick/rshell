defmodule RShell.Runtime.FrameStackTest do
  use ExUnit.Case, async: true

  alias RShell.Runtime.FrameStack
  alias RShell.Runtime.Frame

  describe "FrameStack.new/1" do
    test "initializes with global frame" do
      stack = FrameStack.new()

      assert length(stack.frames) == 1
      frame = FrameStack.current_frame(stack)
      assert frame.type == :global
      assert frame.output_mode == :isolate
    end

    test "initializes with custom output mode" do
      stack = FrameStack.new(output_mode: :accumulate)

      frame = FrameStack.current_frame(stack)
      assert frame.output_mode == :accumulate
    end

    test "initializes with custom context" do
      custom_context = %{
        env: %{"FOO" => "bar"},
        cwd: "/home/user",
        exit_code: 0,
        command_count: 0
      }

      stack = FrameStack.new(context: custom_context)

      assert stack.global_context.env == %{"FOO" => "bar"}
      assert stack.global_context.cwd == "/home/user"
    end

    test "initializes with default context when not provided" do
      stack = FrameStack.new()

      assert stack.global_context.env == %{}
      assert stack.global_context.cwd == "/"
      assert stack.global_context.exit_code == 0
      assert stack.global_context.command_count == 0
    end
  end

  describe "FrameStack.push_frame/4" do
    test "pushes frame onto stack" do
      stack = FrameStack.new()
      stack = FrameStack.push_frame(stack, :loop, :accumulate)

      assert length(stack.frames) == 2
      assert FrameStack.current_frame(stack).type == :loop
      assert FrameStack.current_frame(stack).output_mode == :accumulate
    end

    test "pushes frame with metadata" do
      stack = FrameStack.new()
      stack = FrameStack.push_frame(stack, :loop, :accumulate, %{iteration: 0})

      assert FrameStack.current_frame(stack).metadata.iteration == 0
    end

    test "can push multiple frames" do
      stack = FrameStack.new()
      stack = FrameStack.push_frame(stack, :loop, :accumulate)
      stack = FrameStack.push_frame(stack, :loop, :accumulate)

      assert length(stack.frames) == 3
      assert FrameStack.current_frame(stack).type == :loop
    end
  end

  describe "FrameStack.pop_frame/1" do
    test "pops frame and returns accumulated output" do
      stack = FrameStack.new()
      stack = FrameStack.push_frame(stack, :loop, :accumulate)

      {stack, output} = FrameStack.pop_frame(stack)

      assert length(stack.frames) == 1
      assert output == %{stdout: [], stderr: []}
    end

    test "returns to global frame after pop" do
      stack = FrameStack.new()
      stack = FrameStack.push_frame(stack, :loop, :accumulate)

      {stack, _output} = FrameStack.pop_frame(stack)

      assert FrameStack.current_frame(stack).type == :global
    end
  end

  describe "FrameStack.current_frame/1" do
    test "returns top frame" do
      stack = FrameStack.new()
      frame = FrameStack.current_frame(stack)

      assert frame.type == :global
    end

    test "returns most recently pushed frame" do
      stack = FrameStack.new()
      stack = FrameStack.push_frame(stack, :loop, :accumulate, %{name: "outer"})
      stack = FrameStack.push_frame(stack, :loop, :accumulate, %{name: "inner"})

      frame = FrameStack.current_frame(stack)
      assert frame.metadata.name == "inner"
    end
  end

  describe "FrameStack.output_mode/1" do
    test "returns output mode of current frame" do
      stack = FrameStack.new(output_mode: :isolate)
      assert FrameStack.output_mode(stack) == :isolate
    end

    test "returns output mode after pushing frame" do
      stack = FrameStack.new(output_mode: :isolate)
      stack = FrameStack.push_frame(stack, :loop, :accumulate)

      assert FrameStack.output_mode(stack) == :accumulate
    end
  end

  describe "FrameStack.get_variable/2 and set_variable/3" do
    test "sets and gets variables in current frame" do
      stack = FrameStack.new()
      stack = FrameStack.set_variable(stack, "X", 42)

      assert FrameStack.get_variable(stack, "X") == 42
    end

    test "returns nil for undefined variables" do
      stack = FrameStack.new()
      assert FrameStack.get_variable(stack, "UNDEFINED") == nil
    end

    test "variable shadowing works across frames" do
      stack = FrameStack.new()
      stack = FrameStack.update_global_env(stack, "X", 10)

      # Push new frame and shadow X
      stack = FrameStack.push_frame(stack, :loop, :accumulate)
      stack = FrameStack.set_variable(stack, "X", 20)

      # Current frame sees shadowed value
      assert FrameStack.get_variable(stack, "X") == 20

      # Pop frame - back to global value
      {stack, _output} = FrameStack.pop_frame(stack)
      assert FrameStack.get_variable(stack, "X") == 10
    end

    test "looks up variables in parent frames" do
      stack = FrameStack.new()
      stack = FrameStack.update_global_env(stack, "GLOBAL", "value")

      stack = FrameStack.push_frame(stack, :loop, :accumulate)
      stack = FrameStack.set_variable(stack, "LOCAL", "local_value")

      # Can see both local and global
      assert FrameStack.get_variable(stack, "LOCAL") == "local_value"
      assert FrameStack.get_variable(stack, "GLOBAL") == "value"
    end

    test "nested frames search up the chain" do
      stack = FrameStack.new()
      stack = FrameStack.update_global_env(stack, "A", 1)

      # First loop frame
      stack = FrameStack.push_frame(stack, :loop, :accumulate)
      stack = FrameStack.set_variable(stack, "B", 2)

      # Second loop frame (nested)
      stack = FrameStack.push_frame(stack, :loop, :accumulate)
      stack = FrameStack.set_variable(stack, "C", 3)

      # Can see all variables from nested frame
      assert FrameStack.get_variable(stack, "A") == 1  # global
      assert FrameStack.get_variable(stack, "B") == 2  # parent frame
      assert FrameStack.get_variable(stack, "C") == 3  # current frame
    end
  end

  describe "FrameStack.update_global_env/3" do
    test "updates global environment" do
      stack = FrameStack.new()
      stack = FrameStack.update_global_env(stack, "PATH", "/usr/bin")

      assert stack.global_context.env["PATH"] == "/usr/bin"
    end

    test "global variables visible from all frames" do
      stack = FrameStack.new()
      stack = FrameStack.update_global_env(stack, "GLOBAL", "value")

      stack = FrameStack.push_frame(stack, :loop, :accumulate)
      assert FrameStack.get_variable(stack, "GLOBAL") == "value"

      stack = FrameStack.push_frame(stack, :loop, :accumulate)
      assert FrameStack.get_variable(stack, "GLOBAL") == "value"
    end
  end

  describe "FrameStack output accumulation" do
    test "isolate mode replaces output" do
      stack = FrameStack.new(output_mode: :isolate)

      stack = FrameStack.add_output(stack, ["first\n"], [])
      assert FrameStack.get_output(stack) == %{stdout: ["first\n"], stderr: []}

      stack = FrameStack.add_output(stack, ["second\n"], [])
      assert FrameStack.get_output(stack) == %{stdout: ["second\n"], stderr: []}
    end

    test "accumulate mode appends output" do
      stack = FrameStack.new()
      stack = FrameStack.push_frame(stack, :loop, :accumulate)

      stack = FrameStack.add_output(stack, ["first\n"], [])
      stack = FrameStack.add_output(stack, ["second\n"], [])

      output = FrameStack.get_output(stack)
      assert output == %{stdout: ["first\n", "second\n"], stderr: []}
    end

    test "accumulate mode handles both stdout and stderr" do
      stack = FrameStack.new()
      stack = FrameStack.push_frame(stack, :loop, :accumulate)

      stack = FrameStack.add_output(stack, ["out1\n"], ["err1\n"])
      stack = FrameStack.add_output(stack, ["out2\n"], ["err2\n"])

      output = FrameStack.get_output(stack)
      assert output == %{stdout: ["out1\n", "out2\n"], stderr: ["err1\n", "err2\n"]}
    end

    test "clear_output empties accumulated output" do
      stack = FrameStack.new()
      stack = FrameStack.add_output(stack, ["test\n"], [])
      stack = FrameStack.clear_output(stack)

      assert FrameStack.get_output(stack) == %{stdout: [], stderr: []}
    end

    test "output is frame-specific" do
      stack = FrameStack.new()
      stack = FrameStack.add_output(stack, ["global\n"], [])

      # Push new frame
      stack = FrameStack.push_frame(stack, :loop, :accumulate)
      stack = FrameStack.add_output(stack, ["loop\n"], [])

      # Current frame has only loop output
      assert FrameStack.get_output(stack) == %{stdout: ["loop\n"], stderr: []}

      # Pop back to global
      {stack, loop_output} = FrameStack.pop_frame(stack)
      assert loop_output == %{stdout: ["loop\n"], stderr: []}
      assert FrameStack.get_output(stack) == %{stdout: ["global\n"], stderr: []}
    end
  end
end
