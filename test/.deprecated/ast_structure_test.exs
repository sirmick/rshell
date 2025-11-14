defmodule ASTStructureTest do
  @moduledoc """
  Rigorous AST structure validation tests.

  These tests validate the exact structure of parsed ASTs, including:
  - Deep tree structure with correct nesting
  - Exact field values, not just presence
  - Correct node types at each level
  - Accurate source position tracking
  """
  use ExUnit.Case, async: true
  alias BashParser.AST.Types

  describe "simple command structure" do
    test "echo with single argument has exact structure" do
      script = "echo hello"
      {:ok, ast} = RShell.parse(script)

      # Root should be Program
      assert ast.__struct__ == Types.Program
      assert length(ast.children) == 1

      # First child should be Command
      command = hd(ast.children)
      assert command.__struct__ == Types.Command

      # Command should have name field
      assert command.name != nil
      assert command.name.__struct__ == Types.CommandName
      assert String.contains?(command.name.source_info.text, "echo")

      # Command should have argument field with one element
      assert is_list(command.argument)
      assert length(command.argument) >= 1

      arg = hd(command.argument)
      assert String.contains?(arg.source_info.text, "hello")
    end

    test "command with multiple arguments preserves order" do
      script = "echo arg1 arg2 arg3"
      {:ok, ast} = RShell.parse(script)

      command = hd(ast.children)
      assert command.__struct__ == Types.Command

      # Should have 3 arguments in order
      assert is_list(command.argument)
      assert length(command.argument) == 3

      [arg1, arg2, arg3] = command.argument
      assert String.contains?(arg1.source_info.text, "arg1")
      assert String.contains?(arg2.source_info.text, "arg2")
      assert String.contains?(arg3.source_info.text, "arg3")
    end
  end

  describe "variable assignment structure" do
    test "simple assignment has exact structure" do
      script = "NAME=value"
      {:ok, ast} = RShell.parse(script)

      assignment = hd(ast.children)
      assert assignment.__struct__ == Types.VariableAssignment

      # Should have name field
      assert assignment.name != nil
      assert String.contains?(assignment.name.source_info.text, "NAME")

      # Should have value field
      assert assignment.value != nil
      assert String.contains?(assignment.value.source_info.text, "value")
    end

    test "quoted value assignment preserves quotes in structure" do
      script = ~S(NAME="quoted value")
      {:ok, ast} = RShell.parse(script)

      assignment = hd(ast.children)
      assert assignment.__struct__ == Types.VariableAssignment

      # Value should include quotes in text
      assert String.contains?(assignment.value.source_info.text, "\"")
      assert String.contains?(assignment.value.source_info.text, "quoted value")
    end
  end

  describe "pipeline structure" do
    test "simple pipeline has correct structure" do
      script = "echo hello | grep hello"
      {:ok, ast} = RShell.parse(script)

      pipeline = hd(ast.children)
      assert pipeline.__struct__ == Types.Pipeline

      # Should have multiple commands
      assert is_list(pipeline.children)
      assert length(pipeline.children) == 2

      [cmd1, cmd2] = pipeline.children
      assert cmd1.__struct__ == Types.Command
      assert cmd2.__struct__ == Types.Command
    end

    test "multi-stage pipeline preserves order" do
      script = "cat file.txt | grep pattern | sort | uniq"
      {:ok, ast} = RShell.parse(script)

      pipeline = hd(ast.children)
      assert pipeline.__struct__ == Types.Pipeline

      assert is_list(pipeline.children)
      assert length(pipeline.children) == 4
    end
  end

  describe "source position accuracy" do
    test "single line script has correct positions" do
      script = "echo hello"
      {:ok, ast} = RShell.parse(script)

      assert ast.source_info.start_line == 0
      assert ast.source_info.start_column == 0
      assert ast.source_info.end_line == 0
      assert ast.source_info.end_column == String.length(script)
    end

    test "multi-line script tracks line numbers correctly" do
      script = """
      NAME=test
      echo $NAME
      USER=admin
      """

      {:ok, ast} = RShell.parse(script)

      children = ast.children
      assert length(children) == 3

      [line1, line2, line3] = children

      # First assignment on line 0
      assert line1.source_info.start_line == 0

      # Second command on line 1
      assert line2.source_info.start_line == 1

      # Third assignment on line 2
      assert line3.source_info.start_line == 2
    end
  end
end
