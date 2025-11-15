defmodule RShell.Unit.Builtins.MathTest do
  use ExUnit.Case, async: true

  alias RShell.Builtins

  @empty_context %{
    mode: :simulate,
    env: %{},
    cwd: "/tmp",
    exit_code: 0,
    command_count: 0,
    output: [],
    errors: []
  }

  describe "math:add" do
    test "adds two integers" do
      {_ctx, stdout, stderr, exit_code} =
        Builtins.execute("math:add", ["5", "3"], "", @empty_context)

      result = Enum.to_list(stdout) |> List.first()
      assert result == 8
      # Empty stderr stream
      stderr_list = Enum.to_list(stderr)
      assert stderr_list == [] || stderr_list == [[]]
      assert exit_code == 0
    end

    test "adds multiple integers" do
      {_ctx, stdout, _stderr, exit_code} =
        Builtins.execute("math:add", ["10", "20", "30"], "", @empty_context)

      result = Enum.to_list(stdout) |> List.first()
      assert result == 60
      assert exit_code == 0
    end

    test "adds floats" do
      {_ctx, stdout, _stderr, exit_code} =
        Builtins.execute("math:add", ["3.14", "2.86"], "", @empty_context)

      result = Enum.to_list(stdout) |> List.first()
      assert_in_delta result, 6.0, 0.001
      assert exit_code == 0
    end

    test "adds native numbers from context" do
      context = %{@empty_context | env: %{"X" => 5, "Y" => 10}}
      {_ctx, stdout, _stderr, exit_code} =
        Builtins.execute("math:add", [5, 10], "", context)

      result = Enum.to_list(stdout) |> List.first()
      assert result == 15
      assert exit_code == 0
    end

    test "returns error with no arguments" do
      {_ctx, stdout, stderr, exit_code} =
        Builtins.execute("math:add", [], "", @empty_context)

      # Empty stdout stream
      stdout_list = Enum.to_list(stdout)
      assert stdout_list == [] || stdout_list == [[]]
      stderr_text = Enum.to_list(stderr) |> Enum.join("")
      assert stderr_text =~ "requires at least one argument"
      assert exit_code == 1
    end

    test "single argument returns the number" do
      {_ctx, stdout, _stderr, exit_code} =
        Builtins.execute("math:add", ["42"], "", @empty_context)

      result = Enum.to_list(stdout) |> List.first()
      assert result == 42
      assert exit_code == 0
    end
  end

  describe "math:sub" do
    test "subtracts two integers" do
      {_ctx, stdout, stderr, exit_code} =
        Builtins.execute("math:sub", ["10", "3"], "", @empty_context)

      result = Enum.to_list(stdout) |> List.first()
      assert result == 7
      # Empty stderr stream
      stderr_list = Enum.to_list(stderr)
      assert stderr_list == [] || stderr_list == [[]]
      assert exit_code == 0
    end

    test "subtracts left to right" do
      {_ctx, stdout, _stderr, exit_code} =
        Builtins.execute("math:sub", ["100", "20", "5"], "", @empty_context)

      result = Enum.to_list(stdout) |> List.first()
      assert result == 75
      assert exit_code == 0
    end

    test "negates single argument" do
      {_ctx, stdout, _stderr, exit_code} =
        Builtins.execute("math:sub", ["5"], "", @empty_context)

      result = Enum.to_list(stdout) |> List.first()
      assert result == -5
      assert exit_code == 0
    end

    test "returns error with no arguments" do
      {_ctx, _stdout, stderr, exit_code} =
        Builtins.execute("math:sub", [], "", @empty_context)

      stderr_text = Enum.to_list(stderr) |> Enum.join("")
      assert stderr_text =~ "requires at least one argument"
      assert exit_code == 1
    end
  end

  describe "math:mul" do
    test "multiplies two integers" do
      {_ctx, stdout, stderr, exit_code} =
        Builtins.execute("math:mul", ["5", "3"], "", @empty_context)

      result = Enum.to_list(stdout) |> List.first()
      assert result == 15
      # Empty stderr stream
      stderr_list = Enum.to_list(stderr)
      assert stderr_list == [] || stderr_list == [[]]
      assert exit_code == 0
    end

    test "multiplies multiple integers" do
      {_ctx, stdout, _stderr, exit_code} =
        Builtins.execute("math:mul", ["2", "3", "4"], "", @empty_context)

      result = Enum.to_list(stdout) |> List.first()
      assert result == 24
      assert exit_code == 0
    end

    test "multiplies floats" do
      {_ctx, stdout, _stderr, exit_code} =
        Builtins.execute("math:mul", ["3.5", "2"], "", @empty_context)

      result = Enum.to_list(stdout) |> List.first()
      assert_in_delta result, 7.0, 0.001
      assert exit_code == 0
    end

    test "single argument returns the number" do
      {_ctx, stdout, _stderr, exit_code} =
        Builtins.execute("math:mul", ["42"], "", @empty_context)

      result = Enum.to_list(stdout) |> List.first()
      assert result == 42
      assert exit_code == 0
    end

    test "returns error with no arguments" do
      {_ctx, _stdout, stderr, exit_code} =
        Builtins.execute("math:mul", [], "", @empty_context)

      stderr_text = Enum.to_list(stderr) |> Enum.join("")
      assert stderr_text =~ "requires at least one argument"
      assert exit_code == 1
    end
  end

  describe "math:div" do
    test "divides two integers returning float" do
      {_ctx, stdout, stderr, exit_code} =
        Builtins.execute("math:div", ["10", "2"], "", @empty_context)

      result = Enum.to_list(stdout) |> List.first()
      assert result == 5.0
      # Empty stderr stream
      stderr_list = Enum.to_list(stderr)
      assert stderr_list == [] || stderr_list == [[]]
      assert exit_code == 0
    end

    test "divides left to right" do
      {_ctx, stdout, _stderr, exit_code} =
        Builtins.execute("math:div", ["100", "5", "2"], "", @empty_context)

      result = Enum.to_list(stdout) |> List.first()
      assert_in_delta result, 10.0, 0.001
      assert exit_code == 0
    end

    test "returns float for integer division" do
      {_ctx, stdout, _stderr, exit_code} =
        Builtins.execute("math:div", ["7", "2"], "", @empty_context)

      result = Enum.to_list(stdout) |> List.first()
      assert_in_delta result, 3.5, 0.001
      assert exit_code == 0
    end

    test "returns error for division by zero" do
      {_ctx, _stdout, stderr, exit_code} =
        Builtins.execute("math:div", ["10", "0"], "", @empty_context)

      stderr_text = Enum.to_list(stderr) |> Enum.join("")
      assert stderr_text =~ "division by zero"
      assert exit_code == 1
    end

    test "returns error with no arguments" do
      {_ctx, _stdout, stderr, exit_code} =
        Builtins.execute("math:div", [], "", @empty_context)

      stderr_text = Enum.to_list(stderr) |> Enum.join("")
      assert stderr_text =~ "requires at least one argument"
      assert exit_code == 1
    end

    test "returns error with single argument" do
      {_ctx, _stdout, stderr, exit_code} =
        Builtins.execute("math:div", ["10"], "", @empty_context)

      stderr_text = Enum.to_list(stderr) |> Enum.join("")
      assert stderr_text =~ "requires at least two arguments"
      assert exit_code == 1
    end
  end
  describe "math:eq" do
    test "returns 1 when numbers are equal" do
      {_ctx, stdout, stderr, exit_code} =
        Builtins.execute("math:eq", ["5", "5"], "", @empty_context)

      result = Enum.to_list(stdout) |> List.first()
      assert result == 1
      # Empty stderr stream
      stderr_list = Enum.to_list(stderr)
      assert stderr_list == [] || stderr_list == [[]]
      assert exit_code == 0
    end

    test "returns 0 when numbers are not equal" do
      {_ctx, stdout, _stderr, exit_code} =
        Builtins.execute("math:eq", ["10", "3"], "", @empty_context)

      result = Enum.to_list(stdout) |> List.first()
      assert result == 0
      assert exit_code == 0
    end

    test "compares floats correctly" do
      {_ctx, stdout, _stderr, exit_code} =
        Builtins.execute("math:eq", ["3.14", "3.14"], "", @empty_context)

      result = Enum.to_list(stdout) |> List.first()
      assert result == 1
      assert exit_code == 0
    end

    test "compares native numbers" do
      {_ctx, stdout, _stderr, exit_code} =
        Builtins.execute("math:eq", [42, 42], "", @empty_context)

      result = Enum.to_list(stdout) |> List.first()
      assert result == 1
      assert exit_code == 0
    end

    test "returns error with no arguments" do
      {_ctx, _stdout, stderr, exit_code} =
        Builtins.execute("math:eq", [], "", @empty_context)

      stderr_text = Enum.to_list(stderr) |> Enum.join("")
      assert stderr_text =~ "requires exactly two arguments"
      assert exit_code == 1
    end

    test "returns error with one argument" do
      {_ctx, _stdout, stderr, exit_code} =
        Builtins.execute("math:eq", ["5"], "", @empty_context)

      stderr_text = Enum.to_list(stderr) |> Enum.join("")
      assert stderr_text =~ "requires exactly two arguments"
      assert exit_code == 1
    end

    test "returns error with more than two arguments" do
      {_ctx, _stdout, stderr, exit_code} =
        Builtins.execute("math:eq", ["5", "5", "5"], "", @empty_context)

      stderr_text = Enum.to_list(stderr) |> Enum.join("")
      assert stderr_text =~ "requires exactly two arguments"
      assert exit_code == 1
    end
  end

  describe "math:neq" do
    test "returns 1 when numbers are not equal" do
      {_ctx, stdout, stderr, exit_code} =
        Builtins.execute("math:neq", ["5", "3"], "", @empty_context)

      result = Enum.to_list(stdout) |> List.first()
      assert result == 1
      # Empty stderr stream
      stderr_list = Enum.to_list(stderr)
      assert stderr_list == [] || stderr_list == [[]]
      assert exit_code == 0
    end

    test "returns 0 when numbers are equal" do
      {_ctx, stdout, _stderr, exit_code} =
        Builtins.execute("math:neq", ["10", "10"], "", @empty_context)

      result = Enum.to_list(stdout) |> List.first()
      assert result == 0
      assert exit_code == 0
    end

    test "compares floats correctly" do
      {_ctx, stdout, _stderr, exit_code} =
        Builtins.execute("math:neq", ["3.14", "2.71"], "", @empty_context)

      result = Enum.to_list(stdout) |> List.first()
      assert result == 1
      assert exit_code == 0
    end

    test "returns error with no arguments" do
      {_ctx, _stdout, stderr, exit_code} =
        Builtins.execute("math:neq", [], "", @empty_context)

      stderr_text = Enum.to_list(stderr) |> Enum.join("")
      assert stderr_text =~ "requires exactly two arguments"
      assert exit_code == 1
    end

    test "returns error with one argument" do
      {_ctx, _stdout, stderr, exit_code} =
        Builtins.execute("math:neq", ["5"], "", @empty_context)

      stderr_text = Enum.to_list(stderr) |> Enum.join("")
      assert stderr_text =~ "requires exactly two arguments"
      assert exit_code == 1
    end
  end

  describe "math:mod" do
    test "returns modulo of positive numbers" do
      {_ctx, stdout, stderr, exit_code} =
        Builtins.execute("math:mod", ["10", "3"], "", @empty_context)

      result = Enum.to_list(stdout) |> List.first()
      assert result == 1
      # Empty stderr stream
      stderr_list = Enum.to_list(stderr)
      assert stderr_list == [] || stderr_list == [[]]
      assert exit_code == 0
    end

    test "modulo with negative dividend returns positive result" do
      {_ctx, stdout, _stderr, exit_code} =
        Builtins.execute("math:mod", ["-10", "3"], "", @empty_context)

      result = Enum.to_list(stdout) |> List.first()
      # -10 mod 3 = 2 (result has sign of divisor)
      assert result == 2
      assert exit_code == 0
    end

    test "modulo with negative divisor" do
      {_ctx, stdout, _stderr, exit_code} =
        Builtins.execute("math:mod", ["10", "-3"], "", @empty_context)

      result = Enum.to_list(stdout) |> List.first()
      # 10 mod -3 = -2 (result has sign of divisor)
      assert result == -2
      assert exit_code == 0
    end

    test "modulo with both negative" do
      {_ctx, stdout, _stderr, exit_code} =
        Builtins.execute("math:mod", ["-10", "-3"], "", @empty_context)

      result = Enum.to_list(stdout) |> List.first()
      # -10 mod -3 = -1 (result has sign of divisor)
      assert result == -1
      assert exit_code == 0
    end

    test "converts floats to integers" do
      {_ctx, stdout, _stderr, exit_code} =
        Builtins.execute("math:mod", ["10.7", "3.2"], "", @empty_context)

      result = Enum.to_list(stdout) |> List.first()
      # 10 mod 3 = 1
      assert result == 1
      assert exit_code == 0
    end

    test "returns error for division by zero" do
      {_ctx, _stdout, stderr, exit_code} =
        Builtins.execute("math:mod", ["10", "0"], "", @empty_context)

      stderr_text = Enum.to_list(stderr) |> Enum.join("")
      assert stderr_text =~ "division by zero"
      assert exit_code == 1
    end

    test "returns error with no arguments" do
      {_ctx, _stdout, stderr, exit_code} =
        Builtins.execute("math:mod", [], "", @empty_context)

      stderr_text = Enum.to_list(stderr) |> Enum.join("")
      assert stderr_text =~ "requires exactly two arguments"
      assert exit_code == 1
    end

    test "returns error with one argument" do
      {_ctx, _stdout, stderr, exit_code} =
        Builtins.execute("math:mod", ["10"], "", @empty_context)

      stderr_text = Enum.to_list(stderr) |> Enum.join("")
      assert stderr_text =~ "requires exactly two arguments"
      assert exit_code == 1
    end

    test "returns error with more than two arguments" do
      {_ctx, _stdout, stderr, exit_code} =
        Builtins.execute("math:mod", ["10", "3", "2"], "", @empty_context)

      stderr_text = Enum.to_list(stderr) |> Enum.join("")
      assert stderr_text =~ "requires exactly two arguments"
      assert exit_code == 1
    end
  end

  describe "math:rem" do
    test "returns remainder of positive numbers" do
      {_ctx, stdout, stderr, exit_code} =
        Builtins.execute("math:rem", ["10", "3"], "", @empty_context)

      result = Enum.to_list(stdout) |> List.first()
      assert result == 1
      # Empty stderr stream
      stderr_list = Enum.to_list(stderr)
      assert stderr_list == [] || stderr_list == [[]]
      assert exit_code == 0
    end

    test "remainder with negative dividend returns negative result" do
      {_ctx, stdout, _stderr, exit_code} =
        Builtins.execute("math:rem", ["-10", "3"], "", @empty_context)

      result = Enum.to_list(stdout) |> List.first()
      # -10 rem 3 = -1 (result has sign of dividend)
      assert result == -1
      assert exit_code == 0
    end

    test "remainder with negative divisor" do
      {_ctx, stdout, _stderr, exit_code} =
        Builtins.execute("math:rem", ["10", "-3"], "", @empty_context)

      result = Enum.to_list(stdout) |> List.first()
      # 10 rem -3 = 1 (result has sign of dividend)
      assert result == 1
      assert exit_code == 0
    end

    test "remainder with both negative" do
      {_ctx, stdout, _stderr, exit_code} =
        Builtins.execute("math:rem", ["-10", "-3"], "", @empty_context)

      result = Enum.to_list(stdout) |> List.first()
      # -10 rem -3 = -1 (result has sign of dividend)
      assert result == -1
      assert exit_code == 0
    end

    test "converts floats to integers" do
      {_ctx, stdout, _stderr, exit_code} =
        Builtins.execute("math:rem", ["10.7", "3.2"], "", @empty_context)

      result = Enum.to_list(stdout) |> List.first()
      # 10 rem 3 = 1
      assert result == 1
      assert exit_code == 0
    end

    test "returns error for division by zero" do
      {_ctx, _stdout, stderr, exit_code} =
        Builtins.execute("math:rem", ["10", "0"], "", @empty_context)

      stderr_text = Enum.to_list(stderr) |> Enum.join("")
      assert stderr_text =~ "division by zero"
      assert exit_code == 1
    end

    test "returns error with no arguments" do
      {_ctx, _stdout, stderr, exit_code} =
        Builtins.execute("math:rem", [], "", @empty_context)

      stderr_text = Enum.to_list(stderr) |> Enum.join("")
      assert stderr_text =~ "requires exactly two arguments"
      assert exit_code == 1
    end

    test "returns error with one argument" do
      {_ctx, _stdout, stderr, exit_code} =
        Builtins.execute("math:rem", ["10"], "", @empty_context)

      stderr_text = Enum.to_list(stderr) |> Enum.join("")
      assert stderr_text =~ "requires exactly two arguments"
      assert exit_code == 1
    end

    test "returns error with more than two arguments" do
      {_ctx, _stdout, stderr, exit_code} =
        Builtins.execute("math:rem", ["10", "3", "2"], "", @empty_context)

      stderr_text = Enum.to_list(stderr) |> Enum.join("")
      assert stderr_text =~ "requires exactly two arguments"
      assert exit_code == 1
    end
  end


  describe "namespace support" do
    test "is_builtin? recognizes namespaced commands" do
      assert Builtins.is_builtin?("math:add") == true
      assert Builtins.is_builtin?("math:sub") == true
      assert Builtins.is_builtin?("math:mul") == true
      assert Builtins.is_builtin?("math:div") == true
      assert Builtins.is_builtin?("math:eq") == true
      assert Builtins.is_builtin?("math:neq") == true
      assert Builtins.is_builtin?("math:mod") == true
      assert Builtins.is_builtin?("math:rem") == true
    end

    test "is_builtin? rejects unknown namespaced commands" do
      assert Builtins.is_builtin?("math:unknown") == false
      assert Builtins.is_builtin?("str:upper") == false
    end
  end
end
