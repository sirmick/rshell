defmodule RShell.Integration.CompoundAssignmentTest do
  use ExUnit.Case, async: true
  import RShell.TestSupport.CLIHelper

  describe "compound assignment operators" do
    test "+= adds to existing value" do
      script = """
      X = 10
      X += 5
      echo $X
      """

      assert_cli_output(script, [
        stdout_contains: "15"
      ])
    end

    test "-= subtracts from existing value" do
      script = """
      X = 20
      X -= 7
      echo $X
      """

      assert_cli_output(script, [
        stdout_contains: "13"
      ])
    end

    test "*= multiplies existing value" do
      script = """
      X = 4
      X *= 3
      echo $X
      """

      assert_cli_output(script, [
        stdout_contains: "12"
      ])
    end

    test "/= divides existing value" do
      script = """
      X = 20
      X /= 4
      echo $X
      """

      assert_cli_output(script, [
        stdout_contains: "5"
      ])
    end

    test "%= modulo on existing value" do
      script = """
      X = 17
      X %= 5
      echo $X
      """

      assert_cli_output(script, [
        stdout_contains: "2"
      ])
    end

    test "compound assignments work with floats" do
      script = """
      X = 10.5
      X += 2.5
      echo $X
      """

      assert_cli_output(script, [
        stdout_contains: "13"
      ])
    end

    test "compound assignment on undefined variable treats it as 0" do
      script = """
      Y += 5
      echo $Y
      """

      assert_cli_output(script, [
        stdout_contains: "5"
      ])
    end

    test "chained compound assignments" do
      script = """
      X = 10
      X += 5
      X *= 2
      X -= 4
      echo $X
      """

      assert_cli_output(script, [
        stdout_contains: "26"
      ])
    end
  end
end
