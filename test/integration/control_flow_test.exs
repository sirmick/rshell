defmodule RShell.Integration.ControlFlowTest do
  use ExUnit.Case, async: true
  import RShell.TestSupport.CLIHelper

  describe "if statement execution" do
    test "executes then-branch when condition is true" do
      script = """
      if (true) {
        echo "condition was true"
      }
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
      if (false) {
        echo "should not print"
      }
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
      if (false) {
        echo "then branch"
      } else {
        echo "else branch"
      }
      """

      # Should have "else branch" in output
      assert_cli_output(script, [
        stdout_contains: "else branch"
      ])
    end

    test "handles if-elif-else chain" do
      script = """
      if (false) {
        echo "first"
      } elif (true) {
        echo "second"
      } else {
        echo "third"
      }
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
      if (true) {
        if (true) {
          echo "nested"
        }
      }
      """

      assert_cli_output(script, [
        stdout_contains: "nested"
      ])
    end

    test "uses boolean expression in condition" do
      script = """
      X = 5
      if (X == 5) {
        echo "X is 5"
      } else {
        echo "X is not 5"
      }
      """

      assert_cli_output(script, [
        stdout_contains: "X is 5"
      ])
    end
  end

  describe "for statement execution" do
    test "iterates over explicit values" do
      script = """
      for (i in ["one", "two", "three"]) {
        echo $i
      }
      """

      state = assert_cli_success(script)

      # Should have 3 echo outputs with values
      outputs = Enum.flat_map(state.history, & &1.stdout)
      assert Enum.any?(outputs, &(&1 =~ "one"))
      assert Enum.any?(outputs, &(&1 =~ "two"))
      assert Enum.any?(outputs, &(&1 =~ "three"))
    end

    test "handles empty iteration list" do
      script = """
      for (i in []) {
        echo "should not print"
      }
      """

      state = assert_cli_success(script)

      # Should have no echo output
      echo_records = Enum.filter(state.history, fn r ->
        r.stdout != [] and Enum.any?(r.stdout, &(&1 =~ "should not print"))
      end)

      assert length(echo_records) == 0
    end

    test "loop variable persists after loop" do
      script = """
      for (x in ["final"]) {
        echo "in loop"
      }
      echo "after loop: $x"
      """

      state = assert_cli_success(script)

      # Should have output showing variable persistence
      outputs = Enum.flat_map(state.history, & &1.stdout)
      assert Enum.any?(outputs, &(&1 =~ "in loop"))
      assert Enum.any?(outputs, &(&1 =~ "after loop: final"))
    end

    test "nested for loops" do
      script = """
      for (i in [1, 2]) {
        for (j in ["a", "b"]) {
          echo "loop"
        }
      }
      """

      state = assert_cli_success(script)

      # Should have 4 echo outputs (2x2)
      echo_records = Enum.filter(state.history, fn r ->
        r.stdout != [] and r.stdout != [""]
      end)

      assert length(echo_records) == 4
    end
  end

  describe "while statement execution" do
    test "does not execute body when condition is initially false" do
      script = """
      while (false) {
        echo "should not print"
      }
      """

      state = assert_cli_success(script)

      # Should have no echo output
      echo_records = Enum.filter(state.history, fn r ->
        r.stdout != [] and Enum.any?(r.stdout, &(&1 =~ "should not print"))
      end)

      assert length(echo_records) == 0
    end

    test "executes body while condition is true" do
      script = """
      X = 0
      while (X < 3) {
        echo $X
        X = X + 1
      }
      """

      state = assert_cli_success(script)

      # Should have outputs showing loop execution
      outputs = Enum.flat_map(state.history, & &1.stdout)
      assert Enum.any?(outputs, &(&1 =~ "0"))
      assert Enum.any?(outputs, &(&1 =~ "1"))
      assert Enum.any?(outputs, &(&1 =~ "2"))
    end
  end

  describe "mixed control flow" do
    test "for inside if statement" do
      script = """
      if (true) {
        for (i in [1, 2]) {
          echo "item"
        }
      }
      """

      state = assert_cli_success(script)

      # Should have 2 echo outputs from the for loop
      echo_records = Enum.filter(state.history, fn r ->
        r.stdout != [] and r.stdout != [""]
      end)

      assert length(echo_records) == 2
    end

    test "if inside for loop" do
      script = """
      for (i in [1, 2, 3]) {
        if (i == 2) {
          echo "found two"
        }
      }
      """

      state = assert_cli_success(script)

      # Should have one output
      outputs = Enum.flat_map(state.history, & &1.stdout)
      assert Enum.any?(outputs, &(&1 =~ "found two"))
    end
  end
end
