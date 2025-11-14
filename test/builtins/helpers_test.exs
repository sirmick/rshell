 defmodule RShell.Builtins.HelpersTest do
  use ExUnit.Case, async: true

  @moduledoc """
  Tests for the Builtins.Helpers compile-time infrastructure.

  Note: These tests verify integration with the actual RShell.Builtins module
  since test-defined modules don't have runtime docstring access.
  """

  alias RShell.Builtins

  # Helper to materialize streams to strings for assertions
  defp materialize(stream) when is_function(stream) do
    stream |> Enum.map(&to_string/1) |> Enum.join("")
  end

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
      context = %{env: %{}, cwd: "/"}

      # Echo with -n flag
      {_ctx, stdout, _stderr, exit_code} = Builtins.execute("echo", ["-n", "test"], "", context)

      assert materialize(stdout) == "test"  # No newline because -n flag worked
      assert exit_code == 0
    end

    test "man builtin displays help using the infrastructure" do
      context = %{env: %{}, cwd: "/"}

      {_ctx, stdout, _stderr, _exit} = Builtins.execute("man", ["echo"], "", context)

      assert materialize(stdout) =~ "echo"
      assert materialize(stdout) =~ "write arguments"
    end

    test "man builtin lists all available builtins" do
      context = %{env: %{}, cwd: "/"}

      {_ctx, stdout, _stderr, _exit} = Builtins.execute("man", ["-a"], "", context)

      assert materialize(stdout) =~ "Available builtins:"
      assert materialize(stdout) =~ "echo"
      assert materialize(stdout) =~ "pwd"
      assert materialize(stdout) =~ "cd"
      assert materialize(stdout) =~ "export"
      assert materialize(stdout) =~ "man"
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
      assert function_exported?(Builtins, :shell_env, 3)
    end
  end
end
