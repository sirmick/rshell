defmodule RShell.Runtime.FrameTest do
  use ExUnit.Case, async: true

  alias RShell.Runtime.Frame
  import RShell.TestHelpers

  describe "Frame.new/3" do
    test "creates frame with defaults" do
      frame = Frame.new(:global, :isolate)

      assert frame.type == :global
      assert frame.output_mode == :isolate
      assert frame.scope == %{}

      # Materialize streams to assert empty output
      output = materialize_output(frame)
      assert output.stdout == []
      assert output.stderr == []

      assert frame.metadata == %{}
      assert frame.parent_scope == nil
    end

    test "creates frame with metadata" do
      frame = Frame.new(:loop, :accumulate, %{iteration: 0})

      assert frame.type == :loop
      assert frame.output_mode == :accumulate
      assert frame.metadata == %{iteration: 0}
    end

    test "supports all frame types" do
      types = [:global, :loop, :function, :subshell, :command_substitution]

      for type <- types do
        frame = Frame.new(type, :isolate)
        assert frame.type == type
      end
    end

    test "supports all output modes" do
      modes = [:isolate, :accumulate, :pipe, :capture]

      for mode <- modes do
        frame = Frame.new(:global, mode)
        assert frame.output_mode == mode
      end
    end

    test "initializes empty scope and accumulated output" do
      frame = Frame.new(:loop, :accumulate)

      assert frame.scope == %{}

      # Materialize streams to assert empty output
      output = materialize_output(frame)
      assert output.stdout == []
      assert output.stderr == []
    end
  end
end
