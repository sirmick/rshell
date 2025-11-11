defmodule RShell.Builtins.HelpersTest do
  use ExUnit.Case, async: true

  @moduledoc """
  Tests for the Builtins.Helpers compile-time infrastructure.

  Note: These tests verify integration with the actual RShell.Builtins module
  since test-defined modules don't have runtime docstring access.
  """

  alias RShell.Builtins

  describe "integration with RShell.Builtins" do
    test "get_builtin_help returns documentation for echo" do
      help = Builtins.get_builtin_help(:echo)

      assert is_binary(help)
      assert help =~ "echo"
      assert help =~ "write arguments"
    end

    test "get_builtin_help works with string names" do
      help = Builtins.get_builtin_help("pwd")

      assert is_binary(help)
      assert help =~ "pwd"
    end

    test "builtins can access options through parse_builtin_options" do
      # Test through actual execution - echo uses the infrastructure
      context = %{env: %{}, cwd: "/", mode: :simulate}

      # Echo with -n flag
      {_ctx, stdout, _stderr, exit_code} = Builtins.shell_echo(["-n", "test"], "", context)

      assert stdout == "test"  # No newline because -n flag worked
      assert exit_code == 0
    end

    test "man builtin displays help using the infrastructure" do
      context = %{env: %{}, cwd: "/", mode: :simulate}

      {_ctx, stdout, _stderr, _exit} = Builtins.shell_man(["echo"], "", context)

      assert stdout =~ "echo"
      assert stdout =~ "write arguments"
    end

    test "man builtin lists all available builtins" do
      context = %{env: %{}, cwd: "/", mode: :simulate}

      {_ctx, stdout, _stderr, _exit} = Builtins.shell_man(["-a"], "", context)

      assert stdout =~ "Available builtins:"
      assert stdout =~ "echo"
      assert stdout =~ "pwd"
      assert stdout =~ "cd"
      assert stdout =~ "export"
      assert stdout =~ "man"
    end
  end

  describe "compile-time function generation" do
    test "Builtins module has get_builtin_help function" do
      assert function_exported?(Builtins, :get_builtin_help, 1)
    end

    test "Builtins module has all shell_* functions" do
      assert function_exported?(Builtins, :shell_echo, 3)
      assert function_exported?(Builtins, :shell_pwd, 3)
      assert function_exported?(Builtins, :shell_cd, 3)
      assert function_exported?(Builtins, :shell_export, 3)
      assert function_exported?(Builtins, :shell_printenv, 3)
      assert function_exported?(Builtins, :shell_man, 3)
      assert function_exported?(Builtins, :shell_true, 3)
      assert function_exported?(Builtins, :shell_false, 3)
    end
  end
end
