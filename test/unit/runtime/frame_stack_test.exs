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
end
