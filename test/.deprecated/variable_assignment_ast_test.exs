defmodule VariableAssignmentASTTest do
  use ExUnit.Case, async: true

  alias BashParser.AST.Types

  describe "VariableAssignment AST structure" do
    test "simple string assignment: X=hello" do
      {:ok, ast_map} = BashParser.parse_bash("X=hello")
      ast = Types.from_map(ast_map)

      IO.puts("\n=== AST for: X=hello ===")
      IO.inspect(ast, pretty: true, limit: :infinity)

      # Extract the assignment node
      assert %Types.Program{children: [assignment]} = ast
      assert %Types.VariableAssignment{} = assignment

      IO.puts("\n=== VariableAssignment node ===")
      IO.inspect(assignment, pretty: true, limit: :infinity)
    end

    test "numeric assignment: COUNT=0" do
      {:ok, ast_map} = BashParser.parse_bash("COUNT=0")
      ast = Types.from_map(ast_map)

      IO.puts("\n=== AST for: COUNT=0 ===")
      IO.inspect(ast, pretty: true, limit: :infinity)

      assert %Types.Program{children: [assignment]} = ast
      assert %Types.VariableAssignment{name: name, value: value} = assignment

      IO.puts("\n=== Name node ===")
      IO.inspect(name, pretty: true, limit: :infinity)

      IO.puts("\n=== Value node ===")
      IO.inspect(value, pretty: true, limit: :infinity)
    end

    test "quoted string assignment: Y=\"hello world\"" do
      {:ok, ast_map} = BashParser.parse_bash("Y=\"hello world\"")
      ast = Types.from_map(ast_map)

      IO.puts("\n=== AST for: Y=\"hello world\" ===")
      IO.inspect(ast, pretty: true, limit: :infinity)

      assert %Types.Program{children: [assignment]} = ast
      assert %Types.VariableAssignment{value: value} = assignment

      IO.puts("\n=== Value node (quoted string) ===")
      IO.inspect(value, pretty: true, limit: :infinity)
    end

    test "JSON map assignment: CONFIG={\"x\":1}" do
      {:ok, ast_map} = BashParser.parse_bash("CONFIG={\"x\":1}")
      ast = Types.from_map(ast_map)

      IO.puts("\n=== AST for: CONFIG={\"x\":1} ===")
      IO.inspect(ast, pretty: true, limit: :infinity)

      assert %Types.Program{children: [assignment]} = ast
      assert %Types.VariableAssignment{value: value} = assignment

      IO.puts("\n=== Value node (JSON map) ===")
      IO.inspect(value, pretty: true, limit: :infinity)
    end

    test "JSON array assignment: SERVERS=[\"a\",\"b\"]" do
      {:ok, ast_map} = BashParser.parse_bash("SERVERS=[\"a\",\"b\"]")
      ast = Types.from_map(ast_map)

      IO.puts("\n=== AST for: SERVERS=[\"a\",\"b\"] ===")
      IO.inspect(ast, pretty: true, limit: :infinity)

      assert %Types.Program{children: [assignment]} = ast
      assert %Types.VariableAssignment{value: value} = assignment

      IO.puts("\n=== Value node (JSON array) ===")
      IO.inspect(value, pretty: true, limit: :infinity)
    end

    test "assignment with variable expansion: Y=$X" do
      {:ok, ast_map} = BashParser.parse_bash("Y=$X")
      ast = Types.from_map(ast_map)

      IO.puts("\n=== AST for: Y=$X ===")
      IO.inspect(ast, pretty: true, limit: :infinity)

      assert %Types.Program{children: [assignment]} = ast
      assert %Types.VariableAssignment{value: value} = assignment

      IO.puts("\n=== Value node (variable expansion) ===")
      IO.inspect(value, pretty: true, limit: :infinity)
    end

    test "concatenated value: Z=prefix$X" do
      {:ok, ast_map} = BashParser.parse_bash("Z=prefix$X")
      ast = Types.from_map(ast_map)

      IO.puts("\n=== AST for: Z=prefix$X ===")
      IO.inspect(ast, pretty: true, limit: :infinity)

      assert %Types.Program{children: [assignment]} = ast
      assert %Types.VariableAssignment{value: value} = assignment

      IO.puts("\n=== Value node (concatenation) ===")
      IO.inspect(value, pretty: true, limit: :infinity)
    end
  end
end
