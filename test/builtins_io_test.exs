defmodule RShell.BuiltinsIOTest do
  @moduledoc """
  Tests for builtin command I/O with Stream-based design.

  Verifies that builtins return Streams for stdout/stderr.
  According to BUILTIN_DESIGN.md, builtins use Stream-only I/O.
  """
  use ExUnit.Case
  alias RShell.Builtins

  @empty_context %{
    env: %{},
    cwd: "/tmp",
    exit_code: 0,
    command_count: 0,
    output: [],
    errors: []
  }

  # Helper to materialize streams to strings for assertions
  defp materialize(stream) when is_function(stream) do
    stream |> Enum.map(&to_string/1) |> Enum.join("")
  end

  describe "Stream-based I/O" do
    test "builtins return Stream stdout" do
      {_ctx, stdout, stderr, exit_code} =
        Builtins.execute("echo", ["hello"], "", @empty_context)

      # Stdout should be a Stream (function)
      assert is_function(stdout)
      assert materialize(stdout) == "hello\n"

      # Stderr should be a Stream (empty)
      assert is_function(stderr)
      assert materialize(stderr) == ""

      assert exit_code == 0
    end

    test "echo with -n flag works correctly" do
      {_ctx, stdout, _stderr, _} =
        Builtins.execute("echo", ["-n", "test"], "", @empty_context)

      assert materialize(stdout) == "test"
    end

    test "context modified by stateful builtins" do
      {new_ctx, _stdout, _stderr, _} =
        Builtins.execute("export", ["TEST_VAR=test_value"], "", @empty_context)

      assert new_ctx.env["TEST_VAR"] == "test_value"
    end
  end
end
