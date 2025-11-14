defmodule RecursiveASTTest do
  use ExUnit.Case

  describe "recursive AST generation" do
    test "simple variable assignment" do
      script = "NAME=\"test\""

      {:ok, ast} = RShell.parse(script)

      # Verify the root node
      assert ast.__struct__ == BashParser.AST.Types.Program
      assert ast.source_info.start_line == 0
      assert ast.source_info.end_line == 0
      assert ast.source_info.text == "NAME=\"test\""

      # Test recursive node finding
      variable_assignments = RShell.find_nodes(ast, "variable_assignment")
      assert length(variable_assignments) == 1

      assignment = List.first(variable_assignments)
      assert assignment.__struct__ == BashParser.AST.Types.VariableAssignment
      assert assignment.source_info.text == "NAME=\"test\""

      # Test field extraction
      assert Map.has_key?(assignment, :name)
      assert Map.has_key?(assignment, :value)
    end

    test "nested command structure" do
      script = "echo 'hello world'"

      {:ok, ast} = RShell.parse(script)

      # Verify root node
      assert ast.__struct__ == BashParser.AST.Types.Program

      # Test recursive node finding
      commands = RShell.find_nodes(ast, "command")
      assert length(commands) == 1

      command = List.first(commands)
      assert command.__struct__ == BashParser.AST.Types.Command
      assert command.source_info.text == "echo 'hello world'"

      # Test field extraction
      assert Map.has_key?(command, :name)
      assert Map.has_key?(command, :argument)
    end

    test "multi-level nested structure" do
      script = """
      if [ "$USER" = "admin" ]; then
        echo "admin"
      else
        echo "user"
      fi
      """

      {:ok, ast} = RShell.parse(script)

      # Verify root node
      assert ast.__struct__ == BashParser.AST.Types.Program

      # Test recursive node finding for different types
      if_statements = RShell.find_nodes(ast, "if_statement")
      assert length(if_statements) == 1

      commands = RShell.find_nodes(ast, "command")
      assert length(commands) == 2

      # Test field extraction in nested structures
      if_statement = List.first(if_statements)
      assert Map.has_key?(if_statement, :condition)
      assert Map.has_key?(if_statement, :children)
    end

    test "function definition with body" do
      script = """
      function greet() {
        echo "Hello $1"
      }
      """

      {:ok, ast} = RShell.parse(script)

      # Test function definition extraction
      functions = RShell.find_nodes(ast, "function_definition")
      assert length(functions) == 1

      func = List.first(functions)
      assert func.__struct__ == BashParser.AST.Types.FunctionDefinition
      assert Map.has_key?(func, :name)
      assert Map.has_key?(func, :body)
    end

    test "binary expression with operators" do
      script = "(( 5 + 3 ))"

      {:ok, ast} = RShell.parse(script)

      # Test binary expression extraction
      binary_exprs = RShell.find_nodes(ast, "binary_expression")

      assert length(binary_exprs) == 1,
             "Expected exactly 1 binary_expression, got #{length(binary_exprs)}"

      # Test field extraction
      binary_expr = List.first(binary_exprs)
      assert Map.has_key?(binary_expr, :left)
      assert Map.has_key?(binary_expr, :operator)
      assert Map.has_key?(binary_expr, :right)
    end

    test "source position tracking" do
      script = """
      # Multi-line script
      USER="admin"
      if [ "$USER" = "admin" ]; then
        echo "Welcome"
      fi
      """

      {:ok, ast} = RShell.parse(script)

      # Verify source text is preserved
      assert String.length(ast.source_info.text) > 50

      # Test that nodes have correct positions
      variable_assignments = RShell.find_nodes(ast, "variable_assignment")
      assert length(variable_assignments) == 1

      assignment = List.first(variable_assignments)
      # Second line (0-indexed)
      assert assignment.source_info.start_line == 1
      assert assignment.source_info.text == "USER=\"admin\""
    end

    test "field extraction for various node types" do
      scripts_and_checks = [
        {"NAME=\"value\"", "variable_assignment", [:name, :value]},
        {"echo 'hello'", "command", [:name, :argument]},
        {"function test() { echo 'test'; }", "function_definition", [:name, :body]},
        {"(( 1 + 2 ))", "binary_expression", [:left, :right]},
        {"for i in 1 2 3; do echo $i; done", "for_statement", [:variable, :value, :body]}
      ]

      for {script, node_type, expected_fields} <- scripts_and_checks do
        {:ok, ast} = RShell.parse(script)
        nodes = RShell.find_nodes(ast, node_type)

        assert length(nodes) == 1, "Expected exactly 1 #{node_type} in: #{script}"

        node = List.first(nodes)

        for field <- expected_fields do
          assert Map.has_key?(node, field),
                 "Expected field #{field} in #{node_type} for script: #{script}"
        end
      end
    end

    test "recursive traversal with field extraction" do
      script = """
      if [ "$DEBUG" = "true" ]; then
        echo "Debug mode"
        export LOG_LEVEL="debug"
      else
        echo "Production mode"
      fi
      """

      {:ok, ast} = RShell.parse(script)

      # Test multiple node types in one traversal
      node_types = ["if_statement", "command", "variable_assignment"]

      for node_type <- node_types do
        nodes = RShell.find_nodes(ast, node_type)

        case node_type do
          "command" ->
            assert length(nodes) == 2, "Expected 2 commands, got #{length(nodes)}"

          "variable_assignment" ->
            assert length(nodes) == 1, "Expected 1 variable_assignment, got #{length(nodes)}"

          "if_statement" ->
            assert length(nodes) == 1, "Expected 1 if_statement, got #{length(nodes)}"
        end

        # Verify each node has the expected structure
        for node <- nodes do
          assert node.__struct__.node_type() == node_type
          assert Map.has_key?(node, :source_info)
          assert is_struct(node.source_info)
        end
      end
    end
  end

  describe "AST analysis functions" do
    test "variable_assignments function" do
      script = "NAME=\"test\""
      {:ok, ast} = RShell.parse(script)

      assignments = RShell.variable_assignments(ast)
      assert length(assignments) == 1

      assignment = List.first(assignments)
      assert assignment.__struct__ == BashParser.AST.Types.VariableAssignment
      assert Map.has_key?(assignment, :name)
      assert Map.has_key?(assignment, :value)
      assert Map.has_key?(assignment, :source_info)
    end

    test "commands function" do
      script = "echo 'hello'"
      {:ok, ast} = RShell.parse(script)

      commands = RShell.commands(ast)
      assert length(commands) == 1

      command = List.first(commands)
      assert command.__struct__ == BashParser.AST.Types.Command
      assert Map.has_key?(command, :name)
      assert Map.has_key?(command, :argument)
      assert Map.has_key?(command, :source_info)
    end

    test "function_definitions function" do
      script = "function test() { echo 'test'; }"
      {:ok, ast} = RShell.parse(script)

      functions = RShell.function_definitions(ast)
      assert length(functions) == 1

      func = List.first(functions)
      assert func.__struct__ == BashParser.AST.Types.FunctionDefinition
      assert Map.has_key?(func, :name)
      assert Map.has_key?(func, :body)
      assert Map.has_key?(func, :source_info)
    end

    test "analyze_types function" do
      script = """
      NAME="test"
      echo "$NAME"
      """

      {:ok, ast} = RShell.parse(script)

      analysis = RShell.analyze_types(ast)
      assert is_map(analysis)
      assert Map.has_key?(analysis, :node_types)
      assert Map.has_key?(analysis, :type_summary)
      assert Map.has_key?(analysis, :total_diverse_types)

      assert analysis.total_diverse_types > 0
      assert length(analysis.node_types) == analysis.total_diverse_types
    end
  end
end
