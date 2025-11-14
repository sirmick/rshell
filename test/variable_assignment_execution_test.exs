defmodule VariableAssignmentExecutionTest do
  use ExUnit.Case, async: true

  alias RShell.Runtime
  alias RShell.PubSub

  setup do
    session_id = "test_#{:erlang.unique_integer([:positive])}"

    # Start runtime
    {:ok, runtime} = Runtime.start_link(
      session_id: session_id,
      auto_execute: false,  # Manual execution for testing
      env: %{}
    )

    %{runtime: runtime, session_id: session_id}
  end

  describe "simple variable assignment" do
    test "string assignment: X=hello", %{runtime: runtime} do
      {:ok, ast_map} = BashParser.parse_bash("X=hello")
      ast = BashParser.AST.Types.from_map(ast_map)

      # Get the assignment node
      %BashParser.AST.Types.Program{children: [assignment]} = ast

      # Execute assignment
      {:ok, result} = Runtime.execute_node(runtime, assignment)

      # Check variable was set
      assert Runtime.get_variable(runtime, "X") == "hello"
    end

    test "numeric assignment: COUNT=0", %{runtime: runtime} do
      {:ok, ast_map} = BashParser.parse_bash("COUNT=0")
      ast = BashParser.AST.Types.from_map(ast_map)

      %BashParser.AST.Types.Program{children: [assignment]} = ast
      {:ok, _result} = Runtime.execute_node(runtime, assignment)

      # Numbers are parsed as integers
      assert Runtime.get_variable(runtime, "COUNT") == 0
    end

    test "quoted string: Y=\"hello world\"", %{runtime: runtime} do
      {:ok, ast_map} = BashParser.parse_bash("Y=\"hello world\"")
      ast = BashParser.AST.Types.from_map(ast_map)

      %BashParser.AST.Types.Program{children: [assignment]} = ast
      {:ok, _result} = Runtime.execute_node(runtime, assignment)

      assert Runtime.get_variable(runtime, "Y") == "hello world"
    end
  end

  describe "JSON value assignment" do
    test "JSON map: CONFIG={\"x\":1}", %{runtime: runtime} do
      {:ok, ast_map} = BashParser.parse_bash("CONFIG={\"x\":1}")
      ast = BashParser.AST.Types.from_map(ast_map)

      %BashParser.AST.Types.Program{children: [assignment]} = ast
      {:ok, _result} = Runtime.execute_node(runtime, assignment)

      # Should parse as map
      assert Runtime.get_variable(runtime, "CONFIG") == %{"x" => 1}
    end

    test "JSON array: SERVERS=[\"a\",\"b\"]", %{runtime: runtime} do
      {:ok, ast_map} = BashParser.parse_bash("SERVERS=[\"a\",\"b\"]")
      ast = BashParser.AST.Types.from_map(ast_map)

      %BashParser.AST.Types.Program{children: [assignment]} = ast
      {:ok, _result} = Runtime.execute_node(runtime, assignment)

      # Should parse as list
      assert Runtime.get_variable(runtime, "SERVERS") == ["a", "b"]
    end

    test "nested structure", %{runtime: runtime} do
      {:ok, ast_map} = BashParser.parse_bash("DATA={\"apps\":[{\"name\":\"app1\"},{\"name\":\"app2\"}]}")
      ast = BashParser.AST.Types.from_map(ast_map)

      %BashParser.AST.Types.Program{children: [assignment]} = ast
      {:ok, _result} = Runtime.execute_node(runtime, assignment)

      expected = %{"apps" => [%{"name" => "app1"}, %{"name" => "app2"}]}
      assert Runtime.get_variable(runtime, "DATA") == expected
    end
  end

  describe "variable expansion in assignment" do
    test "copy variable: Y=$X", %{runtime: runtime} do
      # First set X
      {:ok, ast1_map} = BashParser.parse_bash("X=hello")
      ast1 = BashParser.AST.Types.from_map(ast1_map)
      %BashParser.AST.Types.Program{children: [assignment1]} = ast1
      {:ok, _} = Runtime.execute_node(runtime, assignment1)

      # Then copy to Y
      {:ok, ast2_map} = BashParser.parse_bash("Y=$X")
      ast2 = BashParser.AST.Types.from_map(ast2_map)
      %BashParser.AST.Types.Program{children: [assignment2]} = ast2
      {:ok, _} = Runtime.execute_node(runtime, assignment2)

      assert Runtime.get_variable(runtime, "Y") == "hello"
    end

    test "concatenation: Z=prefix$X", %{runtime: runtime} do
      # Set X first
      {:ok, ast1_map} = BashParser.parse_bash("X=suffix")
      ast1 = BashParser.AST.Types.from_map(ast1_map)
      %BashParser.AST.Types.Program{children: [assignment1]} = ast1
      {:ok, _} = Runtime.execute_node(runtime, assignment1)

      # Concatenate
      {:ok, ast2_map} = BashParser.parse_bash("Z=prefix$X")
      ast2 = BashParser.AST.Types.from_map(ast2_map)
      %BashParser.AST.Types.Program{children: [assignment2]} = ast2
      {:ok, _} = Runtime.execute_node(runtime, assignment2)

      assert Runtime.get_variable(runtime, "Z") == "prefixsuffix"
    end
  end

  describe "assignment persistence" do
    test "variable persists across multiple assignments", %{runtime: runtime} do
      # First assignment
      {:ok, ast1_map} = BashParser.parse_bash("X=1")
      ast1 = BashParser.AST.Types.from_map(ast1_map)
      %BashParser.AST.Types.Program{children: [assignment1]} = ast1
      {:ok, _} = Runtime.execute_node(runtime, assignment1)
      assert Runtime.get_variable(runtime, "X") == 1

      # Second assignment (overwrites)
      {:ok, ast2_map} = BashParser.parse_bash("X=2")
      ast2 = BashParser.AST.Types.from_map(ast2_map)
      %BashParser.AST.Types.Program{children: [assignment2]} = ast2
      {:ok, _} = Runtime.execute_node(runtime, assignment2)
      assert Runtime.get_variable(runtime, "X") == 2

      # Different variable
      {:ok, ast3_map} = BashParser.parse_bash("Y=3")
      ast3 = BashParser.AST.Types.from_map(ast3_map)
      %BashParser.AST.Types.Program{children: [assignment3]} = ast3
      {:ok, _} = Runtime.execute_node(runtime, assignment3)

      # Both should exist
      assert Runtime.get_variable(runtime, "X") == 2
      assert Runtime.get_variable(runtime, "Y") == 3
    end
  end
end
