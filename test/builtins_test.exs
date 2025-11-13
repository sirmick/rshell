defmodule RShell.BuiltinsTest do
  use ExUnit.Case, async: true
  doctest RShell.Builtins

  alias RShell.Builtins

  # Helper to materialize streams to strings for assertions
  defp materialize(stream) when is_function(stream) do
    stream |> Enum.map(&to_string/1) |> Enum.join("")
  end

  describe "is_builtin?/1" do
    test "returns true for echo" do
      assert Builtins.is_builtin?("echo")
    end

    test "returns false for unknown commands" do
      refute Builtins.is_builtin?("ls")
      refute Builtins.is_builtin?("grep")
      refute Builtins.is_builtin?("unknown")
    end
  end

  describe "execute/4" do
    test "executes echo builtin" do
      {ctx, stdout, stderr, exit_code} = Builtins.execute("echo", ["hello"], "", %{})
      assert ctx == %{}
      assert materialize(stdout) == "hello\n"
      assert materialize(stderr) == ""
      assert exit_code == 0
    end

    test "returns error for unknown builtin" do
      assert {:error, :not_a_builtin} = Builtins.execute("unknown", [], "", %{})
    end
  end

  describe "shell_echo/3" do
    test "outputs newline with no arguments" do
      {context, stdout, stderr, exit_code} = Builtins.execute("echo", [], "", %{})

      assert context == %{}
      assert materialize(stdout) == "\n"
      assert materialize(stderr) == ""
      assert exit_code == 0
    end

    test "outputs single argument with newline" do
      {context, stdout, stderr, exit_code} = Builtins.execute("echo", ["hello"], "", %{})

      assert context == %{}
      assert materialize(stdout) == "hello\n"
      assert materialize(stderr) == ""
      assert exit_code == 0
    end

    test "outputs multiple arguments separated by spaces" do
      {context, stdout, stderr, exit_code} =
        Builtins.execute("echo", ["hello", "world", "test"], "", %{})

      assert context == %{}
      assert materialize(stdout) == "hello world test\n"
      assert materialize(stderr) == ""
      assert exit_code == 0
    end

    test "preserves context unchanged" do
      context = %{cwd: "/home/user", env: %{"PATH" => "/usr/bin"}}
      {new_context, _stdout, _stderr, _exit_code} = Builtins.execute("echo", ["test"], "", context)

      assert new_context == context
    end

    test "ignores stdin" do
      {_context, stdout, _stderr, _exit_code} = Builtins.execute("echo", ["hello"], "ignored", %{})

      assert materialize(stdout) == "hello\n"
    end
  end

  describe "shell_echo/3 with -n flag" do
    test "suppresses trailing newline" do
      {_context, stdout, _stderr, _exit_code} = Builtins.execute("echo", ["-n", "hello"], "", %{})

      assert materialize(stdout) == "hello"
    end

    test "suppresses newline with no text" do
      {_context, stdout, _stderr, _exit_code} = Builtins.execute("echo", ["-n"], "", %{})

      assert materialize(stdout) == ""
    end

    test "suppresses newline with multiple arguments" do
      {_context, stdout, _stderr, _exit_code} =
        Builtins.execute("echo", ["-n", "hello", "world"], "", %{})

      assert materialize(stdout) == "hello world"
    end
  end

  describe "shell_echo/3 with -e flag" do
    test "interprets newline escape" do
      {_context, stdout, _stderr, _exit_code} =
        Builtins.execute("echo", ["-e", "hello\\nworld"], "", %{})

      assert materialize(stdout) == "hello\nworld\n"
    end

    test "interprets tab escape" do
      {_context, stdout, _stderr, _exit_code} =
        Builtins.execute("echo", ["-e", "hello\\tworld"], "", %{})

      assert materialize(stdout) == "hello\tworld\n"
    end

    test "interprets multiple escapes" do
      {_context, stdout, _stderr, _exit_code} =
        Builtins.execute("echo", ["-e", "line1\\nline2\\tindented"], "", %{})

      assert materialize(stdout) == "line1\nline2\tindented\n"
    end

    test "interprets backslash escape" do
      {_context, stdout, _stderr, _exit_code} =
        Builtins.execute("echo", ["-e", "hello\\\\world"], "", %{})

      assert materialize(stdout) == "hello\\world\n"
    end

    test "interprets alert escape" do
      {_context, stdout, _stderr, _exit_code} =
        Builtins.execute("echo", ["-e", "hello\\aworld"], "", %{})

      assert materialize(stdout) == "hello\aworld\n"
    end

    test "interprets backspace escape" do
      {_context, stdout, _stderr, _exit_code} =
        Builtins.execute("echo", ["-e", "hello\\bworld"], "", %{})

      assert materialize(stdout) == "hello\bworld\n"
    end

    test "interprets escape character" do
      {_context, stdout, _stderr, _exit_code} =
        Builtins.execute("echo", ["-e", "hello\\eworld"], "", %{})

      assert materialize(stdout) == "hello\eworld\n"
    end

    test "interprets form feed escape" do
      {_context, stdout, _stderr, _exit_code} =
        Builtins.execute("echo", ["-e", "hello\\fworld"], "", %{})

      assert materialize(stdout) == "hello\fworld\n"
    end

    test "interprets carriage return escape" do
      {_context, stdout, _stderr, _exit_code} =
        Builtins.execute("echo", ["-e", "hello\\rworld"], "", %{})

      assert materialize(stdout) == "hello\rworld\n"
    end

    test "interprets vertical tab escape" do
      {_context, stdout, _stderr, _exit_code} =
        Builtins.execute("echo", ["-e", "hello\\vworld"], "", %{})

      assert materialize(stdout) == "hello\vworld\n"
    end
  end

  describe "shell_echo/3 with -E flag" do
    test "disables escape interpretation" do
      {_context, stdout, _stderr, _exit_code} =
        Builtins.execute("echo", ["-E", "hello\\nworld"], "", %{})

      assert materialize(stdout) == "hello\\nworld\n"
    end

    test "overrides previous -e flag" do
      {_context, stdout, _stderr, _exit_code} =
        Builtins.execute("echo", ["-e", "-E", "hello\\nworld"], "", %{})

      assert materialize(stdout) == "hello\\nworld\n"
    end
  end

  describe "shell_echo/3 with combined flags" do
    test "combines -n and -e flags" do
      {_context, stdout, _stderr, _exit_code} =
        Builtins.execute("echo", ["-n", "-e", "hello\\nworld"], "", %{})

      assert materialize(stdout) == "hello\nworld"
    end

    test "combines -e and -n flags (order reversed)" do
      {_context, stdout, _stderr, _exit_code} =
        Builtins.execute("echo", ["-e", "-n", "hello\\nworld"], "", %{})

      assert materialize(stdout) == "hello\nworld"
    end
  end

  describe "shell_echo/3 with flag-like arguments" do
    test "treats -n as text after non-flag argument" do
      {_context, stdout, _stderr, _exit_code} =
        Builtins.execute("echo", ["hello", "-n", "world"], "", %{})

      assert materialize(stdout) == "hello -n world\n"
    end

    test "treats flags as text after non-flag argument" do
      {_context, stdout, _stderr, _exit_code} =
        Builtins.execute("echo", ["text", "-n", "-e"], "", %{})

      assert materialize(stdout) == "text -n -e\n"
    end

    test "outputs literal flags when used alone as text" do
      {_context, stdout, _stderr, _exit_code} = Builtins.execute("echo", ["-n"], "", %{})

      assert materialize(stdout) == ""
    end
  end

  describe "shell_echo/3 edge cases" do
    test "handles empty strings in arguments" do
      {_context, stdout, _stderr, _exit_code} =
        Builtins.execute("echo", ["hello", "", "world"], "", %{})

      assert materialize(stdout) == "hello  world\n"
    end

    test "handles arguments with spaces" do
      {_context, stdout, _stderr, _exit_code} =
        Builtins.execute("echo", ["hello world", "test"], "", %{})

      assert materialize(stdout) == "hello world test\n"
    end

    test "handles special characters" do
      {_context, stdout, _stderr, _exit_code} =
        Builtins.execute("echo", ["$VAR", "*", "?", "[a-z]"], "", %{})

      assert materialize(stdout) == "$VAR * ? [a-z]\n"
    end
  end
end
