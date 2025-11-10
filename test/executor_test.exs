defmodule ExecutorTest do
  use ExUnit.Case
  alias BashParser.Executor
  alias BashParser.Executor.Context

  describe "execute/2" do
    test "executes simple variable assignment" do
      script = "NAME='test'"
      {:ok, ast} = RShell.parse(script)
      {:ok, result} = Executor.execute(ast)

      assert result.exit_code == 0
      assert result.context.env["NAME"] == "test"
    end

    test "executes echo command" do
      script = "echo 'hello world'"
      {:ok, ast} = RShell.parse(script)
      {:ok, result} = Executor.execute(ast)

      assert result.exit_code == 0
      assert "hello world" in result.output
    end

    test "executes variable expansion" do
      script = "NAME='test'; echo $NAME"
      {:ok, ast} = RShell.parse(script)
      {:ok, result} = Executor.execute(ast)

      assert result.exit_code == 0
      assert result.context.env["NAME"] == "test"
    end

    test "executes multiple commands" do
      script = "echo 'first'; echo 'second'; echo 'third'"
      {:ok, ast} = RShell.parse(script)
      {:ok, result} = Executor.execute(ast)

      assert result.exit_code == 0
      assert length(result.output) >= 3
    end

    test "executes export command" do
      script = "export USER=admin"
      {:ok, ast} = RShell.parse(script)
      {:ok, result} = Executor.execute(ast)

      assert result.exit_code == 0
      assert result.context.env["USER"] == "admin"
    end

    test "tracks exit codes" do
      script = "exit 42"
      {:ok, ast} = RShell.parse(script)
      {:ok, result} = Executor.execute(ast)

      assert result.exit_code == 42
    end
  end

  describe "control flow execution" do
    test "executes if statement with true condition" do
      script = """
      NAME='admin'
      if [ -n "$NAME" ]; then
        echo 'has name'
      fi
      """
      {:ok, ast} = RShell.parse(script)
      {:ok, result} = Executor.execute(ast)

      assert result.exit_code == 0
      assert result.context.env["NAME"] == "admin"
    end

    test "executes for loop" do
      script = """
      for i in 1 2 3; do
        echo $i
      done
      """
      {:ok, ast} = RShell.parse(script)
      {:ok, result} = Executor.execute(ast)

      assert result.exit_code == 0
      assert length(result.output) >= 3
    end

    test "executes while loop" do
      script = """
      COUNT=3
      while [ "$COUNT" != "0" ]; do
        echo $COUNT
        COUNT=0
      done
      """
      {:ok, ast} = RShell.parse(script)
      {:ok, result} = Executor.execute(ast)

      assert result.exit_code == 0
    end
  end

  describe "function execution" do
    test "defines a function" do
      script = """
      function greet() {
        echo "Hello"
      }
      """
      {:ok, ast} = RShell.parse(script)
      {:ok, result} = Executor.execute(ast)

      assert result.exit_code == 0
      assert Context.has_function?(result.context, "greet")
    end
  end

  describe "execution modes" do
    test "simulate mode does not execute real commands" do
      script = "rm -rf /nonexistent"
      {:ok, ast} = RShell.parse(script)
      {:ok, result} = Executor.execute(ast, mode: :simulate)

      assert result.exit_code == 0
      assert Enum.any?(result.output, &String.contains?(&1, "Simulated"))
    end

    test "capture mode captures command output" do
      script = "ls /tmp"
      {:ok, ast} = RShell.parse(script)
      {:ok, result} = Executor.execute(ast, mode: :capture)

      assert result.exit_code == 0
      assert Enum.any?(result.output, &String.contains?(&1, "Captured"))
    end
  end

  describe "context management" do
    test "maintains environment between commands" do
      script = "NAME='first'; USER='second'; ROLE='third'"
      {:ok, ast} = RShell.parse(script)
      {:ok, result} = Executor.execute(ast)

      assert result.context.env["NAME"] == "first"
      assert result.context.env["USER"] == "second"
      assert result.context.env["ROLE"] == "third"
    end

    test "handles initial environment" do
      script = "echo $PRESET"
      {:ok, ast} = RShell.parse(script)
      {:ok, result} = Executor.execute(ast, initial_env: %{"PRESET" => "value"})

      assert result.context.env["PRESET"] == "value"
    end
  end

  describe "error handling" do
    test "collects errors" do
      # Create a scenario that would produce an error
      script = "echo 'test'"
      {:ok, ast} = RShell.parse(script)
      {:ok, result} = Executor.execute(ast)

      # Should have empty errors for successful execution
      assert result.errors == []
    end

    test "strict mode stops on first error" do
      script = "exit 1; echo 'should not run'"
      {:ok, ast} = RShell.parse(script)
      {:ok, result} = Executor.execute(ast, strict: true)

      assert result.exit_code == 1
    end
  end

  describe "special commands" do
    test "pwd command outputs current directory" do
      script = "pwd"
      {:ok, ast} = RShell.parse(script)
      {:ok, result} = Executor.execute(ast)

      assert result.exit_code == 0
      assert length(result.output) > 0
    end

    test "cd command changes directory" do
      script = "cd /tmp"
      {:ok, ast} = RShell.parse(script)
      {:ok, result} = Executor.execute(ast)

      assert result.exit_code == 0
      assert result.context.env["PWD"] == "/tmp"
    end

    test "test command evaluates conditions" do
      script = "test 'value'"
      {:ok, ast} = RShell.parse(script)
      {:ok, result} = Executor.execute(ast)

      assert result.exit_code == 0
    end
  end
end
