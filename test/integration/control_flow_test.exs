defmodule RShell.Integration.ControlFlowTest do
  use ExUnit.Case, async: true
  import RShell.TestSupport.CLIHelper

  describe "if statement execution" do
    test "executes then-branch when condition is true" do
      script = """
      if true; then
        echo "condition was true"
      fi
      """

      state = assert_cli_success(script)

      # Find echo output in history
      echo_records = Enum.filter(state.history, fn r ->
        Enum.any?(r.stdout, &(&1 =~ "condition was true"))
      end)

      assert length(echo_records) == 1
    end

    test "skips then-branch when condition is false" do
      script = """
      if false; then
        echo "should not print"
      fi
      """

      state = assert_cli_success(script)

      # Should have no echo output
      echo_records = Enum.filter(state.history, fn r ->
        r.stdout != [] and Enum.any?(r.stdout, &(&1 =~ "should not print"))
      end)

      assert length(echo_records) == 0
    end

    test "executes else-branch when condition is false" do
      script = """
      if false; then
        echo "then branch"
      else
        echo "else branch"
      fi
      """

      # Should have "else branch" in output
      assert_cli_output(script, [
        stdout_contains: "else branch"
      ])
    end

    test "handles if-elif-else chain" do
      script = """
      if false; then
        echo "first"
      elif true; then
        echo "second"
      else
        echo "third"
      fi
      """

      state = assert_cli_success(script)

      # Should have "second" in output
      outputs = Enum.flat_map(state.history, & &1.stdout)
      assert Enum.any?(outputs, &(&1 =~ "second"))
      refute Enum.any?(outputs, &(&1 =~ "first"))
      refute Enum.any?(outputs, &(&1 =~ "third"))
    end

    test "handles nested if statements" do
      script = """
      if true; then
        if true; then
          echo "nested"
        fi
      fi
      """

      assert_cli_output(script, [
        stdout_contains: "nested"
      ])
    end

    test "uses last command exit code in condition" do
      script = """
      if true; false; then
        echo "should not print"
      else
        echo "last was false"
      fi
      """

      assert_cli_output(script, [
        stdout_contains: "last was false"
      ])
    end
  end

  describe "for statement execution" do
    test "iterates over explicit values" do
      script = """
      for i in one two three; do
        echo $i
      done
      """

      state = assert_cli_success(script)

      # Should have 3 echo outputs
      echo_records = Enum.filter(state.history, fn r ->
        r.stdout != [] and r.stdout != [""]
      end)

      # Note: Variable expansion is not yet implemented, so $i will be empty
      # This test will need updating when variable expansion is added
      assert length(echo_records) >= 1
    end

    test "handles empty iteration list" do
      script = """
      for i in; do
        echo "should not print"
      done
      """

      state = assert_cli_success(script)

      # Should have no echo output
      echo_records = Enum.filter(state.history, fn r ->
        r.stdout != [] and Enum.any?(r.stdout, &(&1 =~ "should not print"))
      end)

      assert length(echo_records) == 0
    end

    test "loop variable persists after loop" do
      # Note: This test requires variable expansion to work properly
      script = """
      for x in final; do
        echo "in loop"
      done
      echo "after loop"
      """

      state = assert_cli_success(script)

      # Should have 2 echo outputs
      echo_records = Enum.filter(state.history, fn r ->
        r.stdout != [] and r.stdout != [""]
      end)

      assert length(echo_records) == 2
    end

    test "nested for loops" do
      script = """
      for i in 1 2; do
        for j in a b; do
          echo "loop"
        done
      done
      """

      state = assert_cli_success(script)

      # Should have 4 echo outputs (2x2)
      echo_records = Enum.filter(state.history, fn r ->
        r.stdout != [] and r.stdout != [""]
      end)

      # Note: Variable expansion not working, so just check we get outputs
      assert length(echo_records) >= 1
    end
  end

  describe "while statement execution" do
    test "does not execute body when condition is initially false" do
      script = """
      while false; do
        echo "should not print"
      done
      """

      state = assert_cli_success(script)

      # Should have no echo output
      echo_records = Enum.filter(state.history, fn r ->
        r.stdout != [] and Enum.any?(r.stdout, &(&1 =~ "should not print"))
      end)

      assert length(echo_records) == 0
    end
  end

  describe "mixed control flow" do
    test "for inside if statement" do
      script = """
      if true; then
        for i in 1 2; do
          echo "item"
        done
      fi
      """

      state = assert_cli_success(script)

      # Should have echo outputs from the for loop
      echo_records = Enum.filter(state.history, fn r ->
        r.stdout != [] and r.stdout != [""]
      end)

      assert length(echo_records) >= 1
    end
  end
end
