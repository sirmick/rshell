defmodule RShell.BuiltinsTest do
  use ExUnit.Case, async: true
  doctest RShell.Builtins

  alias RShell.Builtins

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
      assert {%{}, "hello\n", "", 0} = Builtins.execute("echo", ["hello"], "", %{})
    end

    test "returns error for unknown builtin" do
      assert {:error, :not_a_builtin} = Builtins.execute("unknown", [], "", %{})
    end
  end

  describe "shell_echo/3" do
    test "outputs newline with no arguments" do
      {context, stdout, stderr, exit_code} = Builtins.shell_echo([], "", %{})

      assert context == %{}
      assert stdout == "\n"
      assert stderr == ""
      assert exit_code == 0
    end

    test "outputs single argument with newline" do
      {context, stdout, stderr, exit_code} = Builtins.shell_echo(["hello"], "", %{})

      assert context == %{}
      assert stdout == "hello\n"
      assert stderr == ""
      assert exit_code == 0
    end

    test "outputs multiple arguments separated by spaces" do
      {context, stdout, stderr, exit_code} =
        Builtins.shell_echo(["hello", "world", "test"], "", %{})

      assert context == %{}
      assert stdout == "hello world test\n"
      assert stderr == ""
      assert exit_code == 0
    end

    test "preserves context unchanged" do
      context = %{cwd: "/home/user", env: %{"PATH" => "/usr/bin"}}
      {new_context, _stdout, _stderr, _exit_code} = Builtins.shell_echo(["test"], "", context)

      assert new_context == context
    end

    test "ignores stdin" do
      {_context, stdout, _stderr, _exit_code} = Builtins.shell_echo(["hello"], "ignored", %{})

      assert stdout == "hello\n"
    end
  end

  describe "shell_echo/3 with -n flag" do
    test "suppresses trailing newline" do
      {_context, stdout, _stderr, _exit_code} = Builtins.shell_echo(["-n", "hello"], "", %{})

      assert stdout == "hello"
    end

    test "suppresses newline with no text" do
      {_context, stdout, _stderr, _exit_code} = Builtins.shell_echo(["-n"], "", %{})

      assert stdout == ""
    end

    test "suppresses newline with multiple arguments" do
      {_context, stdout, _stderr, _exit_code} =
        Builtins.shell_echo(["-n", "hello", "world"], "", %{})

      assert stdout == "hello world"
    end
  end

  describe "shell_echo/3 with -e flag" do
    test "interprets newline escape" do
      {_context, stdout, _stderr, _exit_code} =
        Builtins.shell_echo(["-e", "hello\\nworld"], "", %{})

      assert stdout == "hello\nworld\n"
    end

    test "interprets tab escape" do
      {_context, stdout, _stderr, _exit_code} =
        Builtins.shell_echo(["-e", "hello\\tworld"], "", %{})

      assert stdout == "hello\tworld\n"
    end

    test "interprets multiple escapes" do
      {_context, stdout, _stderr, _exit_code} =
        Builtins.shell_echo(["-e", "line1\\nline2\\tindented"], "", %{})

      assert stdout == "line1\nline2\tindented\n"
    end

    test "interprets backslash escape" do
      {_context, stdout, _stderr, _exit_code} =
        Builtins.shell_echo(["-e", "hello\\\\world"], "", %{})

      assert stdout == "hello\\world\n"
    end

    test "interprets alert escape" do
      {_context, stdout, _stderr, _exit_code} =
        Builtins.shell_echo(["-e", "hello\\aworld"], "", %{})

      assert stdout == "hello\aworld\n"
    end

    test "interprets backspace escape" do
      {_context, stdout, _stderr, _exit_code} =
        Builtins.shell_echo(["-e", "hello\\bworld"], "", %{})

      assert stdout == "hello\bworld\n"
    end

    test "interprets escape character" do
      {_context, stdout, _stderr, _exit_code} =
        Builtins.shell_echo(["-e", "hello\\eworld"], "", %{})

      assert stdout == "hello\eworld\n"
    end

    test "interprets form feed escape" do
      {_context, stdout, _stderr, _exit_code} =
        Builtins.shell_echo(["-e", "hello\\fworld"], "", %{})

      assert stdout == "hello\fworld\n"
    end

    test "interprets carriage return escape" do
      {_context, stdout, _stderr, _exit_code} =
        Builtins.shell_echo(["-e", "hello\\rworld"], "", %{})

      assert stdout == "hello\rworld\n"
    end

    test "interprets vertical tab escape" do
      {_context, stdout, _stderr, _exit_code} =
        Builtins.shell_echo(["-e", "hello\\vworld"], "", %{})

      assert stdout == "hello\vworld\n"
    end
  end

  describe "shell_echo/3 with -E flag" do
    test "disables escape interpretation" do
      {_context, stdout, _stderr, _exit_code} =
        Builtins.shell_echo(["-E", "hello\\nworld"], "", %{})

      assert stdout == "hello\\nworld\n"
    end

    test "overrides previous -e flag" do
      {_context, stdout, _stderr, _exit_code} =
        Builtins.shell_echo(["-e", "-E", "hello\\nworld"], "", %{})

      assert stdout == "hello\\nworld\n"
    end
  end

  describe "shell_echo/3 with combined flags" do
    test "combines -n and -e flags" do
      {_context, stdout, _stderr, _exit_code} =
        Builtins.shell_echo(["-n", "-e", "hello\\nworld"], "", %{})

      assert stdout == "hello\nworld"
    end

    test "combines -e and -n flags (order reversed)" do
      {_context, stdout, _stderr, _exit_code} =
        Builtins.shell_echo(["-e", "-n", "hello\\nworld"], "", %{})

      assert stdout == "hello\nworld"
    end
  end

  describe "shell_echo/3 with flag-like arguments" do
    test "treats -n as text after non-flag argument" do
      {_context, stdout, _stderr, _exit_code} =
        Builtins.shell_echo(["hello", "-n", "world"], "", %{})

      assert stdout == "hello -n world\n"
    end

    test "treats flags as text after non-flag argument" do
      {_context, stdout, _stderr, _exit_code} =
        Builtins.shell_echo(["text", "-n", "-e"], "", %{})

      assert stdout == "text -n -e\n"
    end

    test "outputs literal flags when used alone as text" do
      {_context, stdout, _stderr, _exit_code} = Builtins.shell_echo(["-n"], "", %{})

      assert stdout == ""
    end
  end

  describe "shell_echo/3 edge cases" do
    test "handles empty strings in arguments" do
      {_context, stdout, _stderr, _exit_code} =
        Builtins.shell_echo(["hello", "", "world"], "", %{})

      assert stdout == "hello  world\n"
    end

    test "handles arguments with spaces" do
      {_context, stdout, _stderr, _exit_code} =
        Builtins.shell_echo(["hello world", "test"], "", %{})

      assert stdout == "hello world test\n"
    end

    test "handles special characters" do
      {_context, stdout, _stderr, _exit_code} =
        Builtins.shell_echo(["$VAR", "*", "?", "[a-z]"], "", %{})

      assert stdout == "$VAR * ? [a-z]\n"
    end
  end
end