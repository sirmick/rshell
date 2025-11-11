defmodule RShell.BuiltinsHelpTest do
  use ExUnit.Case, async: true

  alias RShell.Builtins

  describe "get_builtin_help/1 integration" do
    test "returns help for echo builtin" do
      help = Builtins.get_builtin_help("echo")

      assert help =~ "echo"
      assert help =~ "write arguments to standard output"
      assert help =~ "Options:"
      assert help =~ "-n"
      assert help =~ "no-newline"
    end

    test "returns help for pwd builtin" do
      help = Builtins.get_builtin_help("pwd")

      assert help =~ "pwd"
      assert help =~ "print working directory"
    end

    test "returns help for cd builtin" do
      help = Builtins.get_builtin_help("cd")

      assert help =~ "cd"
      assert help =~ "change the working directory"
    end

    test "returns help for export builtin" do
      help = Builtins.get_builtin_help("export")

      assert help =~ "export"
      assert help =~ "environment"
      assert help =~ "Options:"
    end

    test "handles atom names" do
      help = Builtins.get_builtin_help(:echo)
      assert is_binary(help)
      assert help =~ "echo"
    end
  end

  describe "man builtin integration" do
    test "displays help for specified builtin" do
      context = %{env: %{}, cwd: "/", mode: :simulate}

      {_ctx, stdout, stderr, exit_code} = Builtins.shell_man(["echo"], "", context)

      assert stdout =~ "echo"
      assert stdout =~ "write arguments"
      assert stderr == ""
      assert exit_code == 0
    end

    test "lists all builtins with -a flag" do
      context = %{env: %{}, cwd: "/", mode: :simulate}

      {_ctx, stdout, _stderr, exit_code} = Builtins.shell_man(["-a"], "", context)

      assert stdout =~ "Available builtins:"
      assert stdout =~ "echo"
      assert stdout =~ "pwd"
      assert stdout =~ "cd"
      assert exit_code == 0
    end

    test "returns error for unknown builtin" do
      context = %{env: %{}, cwd: "/", mode: :simulate}

      {_ctx, _stdout, stderr, exit_code} = Builtins.shell_man(["nonexistent"], "", context)

      assert stderr =~ "no manual entry"
      assert exit_code == 1
    end

    test "returns error when no command specified" do
      context = %{env: %{}, cwd: "/", mode: :simulate}

      {_ctx, _stdout, stderr, exit_code} = Builtins.shell_man([], "", context)

      assert stderr =~ "missing command name"
      assert exit_code == 1
    end
  end
end
