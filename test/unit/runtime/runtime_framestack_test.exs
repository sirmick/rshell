defmodule RShell.Runtime.RuntimeFrameStackTest do
  use ExUnit.Case, async: true

  alias RShell.Runtime
  alias RShell.Runtime.FrameStack

  describe "Runtime initialization with FrameStack" do
    test "initializes with frame stack" do
      {:ok, runtime} = Runtime.start_link(session_id: "test_init", env: %{}, cwd: "/")
      state = :sys.get_state(runtime)

      # Old context still exists
      assert state.context.cwd == "/"
      assert state.context.env == %{}

      # New frame stack exists
      assert state.frame_stack != nil
      assert length(state.frame_stack.frames) == 1

      # Feature flag defaults to false (safe)
      assert state.use_frames == false

      # Cleanup
      GenServer.stop(runtime)
    end

    test "frame stack has correct initial state" do
      {:ok, runtime} = Runtime.start_link(
        session_id: "test_stack",
        env: %{"TEST" => "value"},
        cwd: "/home/test"
      )
      state = :sys.get_state(runtime)

      # Frame stack matches context
      assert state.frame_stack.global_context.cwd == "/home/test"
      assert state.frame_stack.global_context.env["TEST"] == "value"

      # Global frame has isolate mode
      current_frame = FrameStack.current_frame(state.frame_stack)
      assert current_frame.type == :global
      assert current_frame.output_mode == :isolate

      # Cleanup
      GenServer.stop(runtime)
    end

    test "reset reinitializes frame stack" do
      {:ok, runtime} = Runtime.start_link(
        session_id: "test_reset",
        env: %{"INITIAL" => "value"},
        cwd: "/initial"
      )

      # Get initial state
      initial_state = :sys.get_state(runtime)
      initial_stack_id = make_ref()

      # Reset runtime
      Runtime.reset(runtime)

      # Get state after reset
      reset_state = :sys.get_state(runtime)

      # Frame stack was recreated
      assert reset_state.frame_stack != nil
      assert length(reset_state.frame_stack.frames) == 1

      # Initial values restored
      assert reset_state.frame_stack.global_context.cwd == "/initial"
      assert reset_state.frame_stack.global_context.env["INITIAL"] == "value"

      # Cleanup
      GenServer.stop(runtime)
    end
  end

  describe "Runtime maintains compatibility" do
    test "existing context-based code still works" do
      {:ok, runtime} = Runtime.start_link(
        session_id: "test_compat",
        env: %{"X" => "42"},
        cwd: "/test"
      )

      # Old API still works
      assert Runtime.get_variable(runtime, "X") == "42"
      assert Runtime.get_cwd(runtime) == "/test"

      context = Runtime.get_context(runtime)
      assert context.env["X"] == "42"
      assert context.cwd == "/test"

      # Cleanup
      GenServer.stop(runtime)
    end
  end
end
