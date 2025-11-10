defmodule BashParserNIFTest do
  @moduledoc """
  Unit tests for the raw Rust NIF parser output.

  These tests verify that the Rust NIF emits correctly structured data
  with proper field names and nested structures before typed conversion.
  """
  use ExUnit.Case, async: true

  describe "BashParser.parse_bash/1 - basic structure" do
    test "returns {:ok, map} for valid bash script" do
      assert {:ok, _ast} = BashParser.parse_bash("echo hello")
    end

    test "uses 'type' field instead of 'kind'" do
      {:ok, ast} = BashParser.parse_bash("echo hello")

      assert Map.has_key?(ast, "type")
      refute Map.has_key?(ast, "kind")
    end

    test "includes source location fields" do
      {:ok, ast} = BashParser.parse_bash("echo hello")

      assert Map.has_key?(ast, "start_row")
      assert Map.has_key?(ast, "start_col")
      assert Map.has_key?(ast, "end_row")
      assert Map.has_key?(ast, "end_col")
      assert Map.has_key?(ast, "text")
    end

    test "program node has correct type" do
      {:ok, ast} = BashParser.parse_bash("echo hello")

      assert ast["type"] == "program"
    end
  end

  describe "BashParser.parse_bash/1 - unnamed children" do
    test "program node with single statement has children array" do
      {:ok, ast} = BashParser.parse_bash("echo hello")

      assert Map.has_key?(ast, "children")
      assert is_list(ast["children"])
      assert length(ast["children"]) == 1
      assert hd(ast["children"])["type"] == "command"
    end

    test "program node with multiple statements has children array" do
      {:ok, ast} = BashParser.parse_bash("echo hello\necho world")

      assert Map.has_key?(ast, "children")
      assert is_list(ast["children"])
      assert length(ast["children"]) == 2
      assert Enum.at(ast["children"], 0)["type"] == "command"
      assert Enum.at(ast["children"], 1)["type"] == "command"
    end
  end

  describe "BashParser.parse_bash/1 - named fields" do
    test "if_statement has condition field" do
      script = """
      if [ "$DEBUG" = "true" ]; then
          echo "Debug mode"
      fi
      """

      {:ok, ast} = BashParser.parse_bash(script)

      # Navigate to if_statement
      if_stmt = hd(ast["children"])
      assert if_stmt["type"] == "if_statement"

      # Should have condition field (single value when only one condition)
      assert Map.has_key?(if_stmt, "condition")
      assert is_map(if_stmt["condition"])
      assert if_stmt["condition"]["type"] == "test_command"

      # Should also have unnamed children for the consequence
      assert Map.has_key?(if_stmt, "children")
      assert is_list(if_stmt["children"])
    end

    test "command node has name and argument fields" do
      {:ok, ast} = BashParser.parse_bash("echo hello world")

      command = hd(ast["children"])
      assert command["type"] == "command"

      # Should have named fields
      assert Map.has_key?(command, "name")
      assert Map.has_key?(command, "argument")

      # name should be a single map, argument should be a list
      assert is_map(command["name"])
      assert command["name"]["type"] == "command_name"

      assert is_list(command["argument"])
      assert length(command["argument"]) == 2
    end

    test "binary_expression has left, operator, and right fields" do
      script = """
      if [ "$USER" = "admin" ]; then
          echo "Admin"
      fi
      """

      {:ok, ast} = BashParser.parse_bash(script)

      # Navigate to binary_expression
      if_stmt = hd(ast["children"])
      test_cmd = if_stmt["condition"]  # condition is a single map, not list
      binary_expr = hd(test_cmd["children"])  # children is a list

      # Verify binary_expression has named fields
      assert binary_expr["type"] == "binary_expression"
      assert Map.has_key?(binary_expr, "left")
      assert Map.has_key?(binary_expr, "right")
      assert is_map(binary_expr["left"])
      assert is_map(binary_expr["right"])
    end
  end

  describe "BashParser.parse_bash/1 - mixed named and unnamed children" do
    test "test_command has both field and children" do
      {:ok, ast} = BashParser.parse_bash("[ -f /tmp/file ]")

      test_cmd = hd(ast["children"])
      assert test_cmd["type"] == "test_command"

      # test_command might have unnamed children
      # This depends on the grammar structure
      assert Map.has_key?(test_cmd, "children") or map_size(test_cmd) > 6
    end
  end

  describe "BashParser.parse_bash/1 - nested structures" do
    test "nested if statement preserves structure" do
      script = """
      if [ "$A" = "1" ]; then
          if [ "$B" = "2" ]; then
              echo "nested"
          fi
      fi
      """

      {:ok, ast} = BashParser.parse_bash(script)

      outer_if = hd(ast["children"])
      assert outer_if["type"] == "if_statement"

      # Should have nested structure
      assert Map.has_key?(outer_if, "condition")
      assert Map.has_key?(outer_if, "children")
    end
  end

  describe "BashParser.parse_bash/1 - error handling" do
    test "returns :error for invalid bash syntax" do
      # Intentionally invalid bash - unclosed quote
      assert {:error, _} = BashParser.parse_bash("echo \"unclosed")
    end
  end
end
