defmodule RShell.ExprEvaluatorTest do
  use ExUnit.Case, async: true

  alias RShell.ExprEvaluator
  alias BashParser.AST.RShellTypes, as: Types

  # Helper to create source_info
  defp source_info(text) do
    %Types.SourceInfo{
      start_line: 1,
      start_column: 0,
      end_line: 1,
      end_column: String.length(text),
      text: text
    }
  end

  # Helper to create a context with environment
  defp context(env \\ %{}) do
    %{env: env}
  end

  describe "number literals" do
    test "evaluates integer" do
      node = %Types.Number{source_info: source_info("42")}
      assert ExprEvaluator.evaluate(node, context()) == 42
    end

    test "evaluates negative integer" do
      node = %Types.Number{source_info: source_info("-15")}
      assert ExprEvaluator.evaluate(node, context()) == -15
    end

    test "evaluates float" do
      node = %Types.Number{source_info: source_info("3.14")}
      assert ExprEvaluator.evaluate(node, context()) == 3.14
    end

    test "evaluates negative float" do
      node = %Types.Number{source_info: source_info("-2.5")}
      assert ExprEvaluator.evaluate(node, context()) == -2.5
    end

    test "evaluates zero" do
      node = %Types.Number{source_info: source_info("0")}
      assert ExprEvaluator.evaluate(node, context()) == 0
    end
  end

  describe "string literals" do
    test "evaluates double-quoted string" do
      node = %Types.String{source_info: source_info("\"hello\"")}
      assert ExprEvaluator.evaluate(node, context()) == "hello"
    end

    test "evaluates single-quoted string" do
      node = %Types.String{source_info: source_info("'world'")}
      assert ExprEvaluator.evaluate(node, context()) == "world"
    end

    test "evaluates empty string" do
      node = %Types.String{source_info: source_info("\"\"")}
      assert ExprEvaluator.evaluate(node, context()) == ""
    end

    test "evaluates string with spaces" do
      node = %Types.String{source_info: source_info("\"hello world\"")}
      assert ExprEvaluator.evaluate(node, context()) == "hello world"
    end
  end

  describe "boolean literals" do
    test "evaluates true" do
      # Boolean removed from grammar - true is now an Identifier
      node = %Types.Identifier{source_info: source_info("true")}
      assert ExprEvaluator.evaluate(node, context()) == true
    end

    test "evaluates false" do
      # Boolean removed from grammar - false is now an Identifier
      node = %Types.Identifier{source_info: source_info("false")}
      assert ExprEvaluator.evaluate(node, context()) == false
    end
  end

  describe "array literals" do
    test "evaluates empty array" do
      node = %Types.Array{source_info: source_info("[]"), children: []}
      assert ExprEvaluator.evaluate(node, context()) == []
    end

    test "evaluates array of numbers" do
      node = %Types.Array{
        source_info: source_info("[1,2,3]"),
        children: [
          %Types.Number{source_info: source_info("1")},
          %Types.Number{source_info: source_info("2")},
          %Types.Number{source_info: source_info("3")}
        ]
      }
      assert ExprEvaluator.evaluate(node, context()) == [1, 2, 3]
    end

    test "evaluates array of strings" do
      node = %Types.Array{
        source_info: source_info("[\"a\",\"b\",\"c\"]"),
        children: [
          %Types.String{source_info: source_info("\"a\"")},
          %Types.String{source_info: source_info("\"b\"")},
          %Types.String{source_info: source_info("\"c\"")}
        ]
      }
      assert ExprEvaluator.evaluate(node, context()) == ["a", "b", "c"]
    end

    test "evaluates array of mixed types" do
      node = %Types.Array{
        source_info: source_info("[1,\"hello\",true]"),
        children: [
          %Types.Number{source_info: source_info("1")},
          %Types.String{source_info: source_info("\"hello\"")},
          %Types.Identifier{source_info: source_info("true")}
        ]
      }
      assert ExprEvaluator.evaluate(node, context()) == [1, "hello", true]
    end

    test "evaluates nested array" do
      inner = %Types.Array{
        source_info: source_info("[1,2]"),
        children: [
          %Types.Number{source_info: source_info("1")},
          %Types.Number{source_info: source_info("2")}
        ]
      }

      node = %Types.Array{
        source_info: source_info("[[1,2],3]"),
        children: [
          inner,
          %Types.Number{source_info: source_info("3")}
        ]
      }
      assert ExprEvaluator.evaluate(node, context()) == [[1, 2], 3]
    end
  end

  describe "object literals" do
    test "evaluates empty object" do
      node = %Types.Object{source_info: source_info("{}"), children: []}
      assert ExprEvaluator.evaluate(node, context()) == %{}
    end

    test "evaluates object with string key and number value" do
      node = %Types.Object{
        source_info: source_info("{\"x\":1}"),
        children: [
          %Types.ObjectEntry{
            source_info: source_info("\"x\":1"),
            key: %Types.String{source_info: source_info("\"x\"")},
            value: %Types.Number{source_info: source_info("1")}
          }
        ]
      }
      assert ExprEvaluator.evaluate(node, context()) == %{"x" => 1}
    end

    test "evaluates object with multiple entries" do
      node = %Types.Object{
        source_info: source_info("{\"a\":2,\"b\":\"test\"}"),
        children: [
          %Types.ObjectEntry{
            source_info: source_info("\"a\":2"),
            key: %Types.String{source_info: source_info("\"a\"")},
            value: %Types.Number{source_info: source_info("2")}
          },
          %Types.ObjectEntry{
            source_info: source_info("\"b\":\"test\""),
            key: %Types.String{source_info: source_info("\"b\"")},
            value: %Types.String{source_info: source_info("\"test\"")}
          }
        ]
      }
      assert ExprEvaluator.evaluate(node, context()) == %{"a" => 2, "b" => "test"}
    end

    test "evaluates object with nested array" do
      array = %Types.Array{
        source_info: source_info("[2,3,4]"),
        children: [
          %Types.Number{source_info: source_info("2")},
          %Types.Number{source_info: source_info("3")},
          %Types.Number{source_info: source_info("4")}
        ]
      }

      node = %Types.Object{
        source_info: source_info("{\"a\":2,\"b\":[2,3,4]}"),
        children: [
          %Types.ObjectEntry{
            source_info: source_info("\"a\":2"),
            key: %Types.String{source_info: source_info("\"a\"")},
            value: %Types.Number{source_info: source_info("2")}
          },
          %Types.ObjectEntry{
            source_info: source_info("\"b\":[2,3,4]"),
            key: %Types.String{source_info: source_info("\"b\"")},
            value: array
          }
        ]
      }
      assert ExprEvaluator.evaluate(node, context()) == %{"a" => 2, "b" => [2, 3, 4]}
    end

    test "evaluates nested object" do
      inner = %Types.Object{
        source_info: source_info("{\"port\":5432}"),
        children: [
          %Types.ObjectEntry{
            source_info: source_info("\"port\":5432"),
            key: %Types.String{source_info: source_info("\"port\"")},
            value: %Types.Number{source_info: source_info("5432")}
          }
        ]
      }

      node = %Types.Object{
        source_info: source_info("{\"db\":{\"port\":5432}}"),
        children: [
          %Types.ObjectEntry{
            source_info: source_info("\"db\":{\"port\":5432}"),
            key: %Types.String{source_info: source_info("\"db\"")},
            value: inner
          }
        ]
      }
      assert ExprEvaluator.evaluate(node, context()) == %{"db" => %{"port" => 5432}}
    end
  end

  describe "binary expressions" do
    test "evaluates addition" do
      node = %Types.BinaryExpression{
        source_info: source_info("5+3"),
        left: %Types.Number{source_info: source_info("5")},
        operator: %{source_info: source_info("+")},
        right: %Types.Number{source_info: source_info("3")}
      }
      assert ExprEvaluator.evaluate(node, context()) == 8
    end

    test "evaluates subtraction" do
      node = %Types.BinaryExpression{
        source_info: source_info("10-3"),
        left: %Types.Number{source_info: source_info("10")},
        operator: %{source_info: source_info("-")},
        right: %Types.Number{source_info: source_info("3")}
      }
      assert ExprEvaluator.evaluate(node, context()) == 7
    end

    test "evaluates multiplication" do
      node = %Types.BinaryExpression{
        source_info: source_info("4*5"),
        left: %Types.Number{source_info: source_info("4")},
        operator: %{source_info: source_info("*")},
        right: %Types.Number{source_info: source_info("5")}
      }
      assert ExprEvaluator.evaluate(node, context()) == 20
    end

    test "evaluates division" do
      node = %Types.BinaryExpression{
        source_info: source_info("15/3"),
        left: %Types.Number{source_info: source_info("15")},
        operator: %{source_info: source_info("/")},
        right: %Types.Number{source_info: source_info("3")}
      }
      assert ExprEvaluator.evaluate(node, context()) == 5.0
    end

    test "evaluates modulo" do
      node = %Types.BinaryExpression{
        source_info: source_info("17%5"),
        left: %Types.Number{source_info: source_info("17")},
        operator: %{source_info: source_info("%")},
        right: %Types.Number{source_info: source_info("5")}
      }
      assert ExprEvaluator.evaluate(node, context()) == 2
    end

    test "evaluates equality comparison" do
      node = %Types.BinaryExpression{
        source_info: source_info("5==5"),
        left: %Types.Number{source_info: source_info("5")},
        operator: %{source_info: source_info("==")},
        right: %Types.Number{source_info: source_info("5")}
      }
      assert ExprEvaluator.evaluate(node, context()) == true
    end

    test "evaluates inequality comparison" do
      node = %Types.BinaryExpression{
        source_info: source_info("5!=3"),
        left: %Types.Number{source_info: source_info("5")},
        operator: %{source_info: source_info("!=")},
        right: %Types.Number{source_info: source_info("3")}
      }
      assert ExprEvaluator.evaluate(node, context()) == true
    end

    test "evaluates less than" do
      node = %Types.BinaryExpression{
        source_info: source_info("3<5"),
        left: %Types.Number{source_info: source_info("3")},
        operator: %{source_info: source_info("<")},
        right: %Types.Number{source_info: source_info("5")}
      }
      assert ExprEvaluator.evaluate(node, context()) == true
    end

    test "evaluates string concatenation" do
      node = %Types.BinaryExpression{
        source_info: source_info("\"hello\"+\" \"+\"world\""),
        left: %Types.String{source_info: source_info("\"hello\"")},
        operator: %{source_info: source_info("+")},
        right: %Types.String{source_info: source_info("\" world\"")}
      }
      assert ExprEvaluator.evaluate(node, context()) == "hello world"
    end

    test "evaluates logical AND" do
      node = %Types.BinaryExpression{
        source_info: source_info("true&&false"),
        left: %Types.Identifier{source_info: source_info("true")},
        operator: %{source_info: source_info("&&")},
        right: %Types.Identifier{source_info: source_info("false")}
      }
      assert ExprEvaluator.evaluate(node, context()) == false
    end

    test "evaluates logical OR" do
      node = %Types.BinaryExpression{
        source_info: source_info("false||true"),
        left: %Types.Identifier{source_info: source_info("false")},
        operator: %{source_info: source_info("||")},
        right: %Types.Identifier{source_info: source_info("true")}
      }
      assert ExprEvaluator.evaluate(node, context()) == true
    end
  end

  describe "unary expressions" do
    test "evaluates negation" do
      node = %Types.UnaryExpression{
        source_info: source_info("-5"),
        operator: %{source_info: source_info("-")},
        argument: %Types.Number{source_info: source_info("5")}
      }
      assert ExprEvaluator.evaluate(node, context()) == -5
    end

    test "evaluates logical NOT" do
      node = %Types.UnaryExpression{
        source_info: source_info("!true"),
        operator: %{source_info: source_info("!")},
        argument: %Types.Identifier{source_info: source_info("true")}
      }
      assert ExprEvaluator.evaluate(node, context()) == false
    end
  end

  describe "variable references" do
    test "evaluates identifier to variable value" do
      ctx = context(%{"X" => 42})
      node = %Types.Identifier{source_info: source_info("X")}
      assert ExprEvaluator.evaluate(node, ctx) == 42
    end

    test "evaluates identifier to nil for undefined variable" do
      node = %Types.Identifier{source_info: source_info("UNDEFINED")}
      assert ExprEvaluator.evaluate(node, context()) == nil
    end

    test "evaluates variable reference with native map" do
      ctx = context(%{"CONFIG" => %{"host" => "localhost", "port" => 5432}})
      node = %Types.Identifier{source_info: source_info("CONFIG")}
      assert ExprEvaluator.evaluate(node, ctx) == %{"host" => "localhost", "port" => 5432}
    end

    test "evaluates variable reference with native list" do
      ctx = context(%{"SERVERS" => ["web1", "web2", "db1"]})
      node = %Types.Identifier{source_info: source_info("SERVERS")}
      assert ExprEvaluator.evaluate(node, ctx) == ["web1", "web2", "db1"]
    end
  end

  describe "complex expressions" do
    test "evaluates expression with variable" do
      ctx = context(%{"X" => 5})
      node = %Types.BinaryExpression{
        source_info: source_info("X+3"),
        left: %Types.Identifier{source_info: source_info("X")},
        operator: %{source_info: source_info("+")},
        right: %Types.Number{source_info: source_info("3")}
      }
      assert ExprEvaluator.evaluate(node, ctx) == 8
    end

    test "evaluates nested expressions" do
      # (5 + 3) * 2
      inner = %Types.BinaryExpression{
        source_info: source_info("5+3"),
        left: %Types.Number{source_info: source_info("5")},
        operator: %{source_info: source_info("+")},
        right: %Types.Number{source_info: source_info("3")}
      }

      node = %Types.BinaryExpression{
        source_info: source_info("(5+3)*2"),
        left: inner,
        operator: %{source_info: source_info("*")},
        right: %Types.Number{source_info: source_info("2")}
      }
      assert ExprEvaluator.evaluate(node, context()) == 16
    end

    test "evaluates complex object with expressions" do
      # {"a": 5+3, "b": [1,2,3]}
      sum_expr = %Types.BinaryExpression{
        source_info: source_info("5+3"),
        left: %Types.Number{source_info: source_info("5")},
        operator: %{source_info: source_info("+")},
        right: %Types.Number{source_info: source_info("3")}
      }

      array = %Types.Array{
        source_info: source_info("[1,2,3]"),
        children: [
          %Types.Number{source_info: source_info("1")},
          %Types.Number{source_info: source_info("2")},
          %Types.Number{source_info: source_info("3")}
        ]
      }

      node = %Types.Object{
        source_info: source_info("{\"a\":5+3,\"b\":[1,2,3]}"),
        children: [
          %Types.ObjectEntry{
            source_info: source_info("\"a\":5+3"),
            key: %Types.String{source_info: source_info("\"a\"")},
            value: sum_expr
          },
          %Types.ObjectEntry{
            source_info: source_info("\"b\":[1,2,3]"),
            key: %Types.String{source_info: source_info("\"b\"")},
            value: array
          }
        ]
      }
      assert ExprEvaluator.evaluate(node, context()) == %{"a" => 8, "b" => [1, 2, 3]}
    end
  end

  describe "wrapper nodes" do
    test "evaluates Expression wrapper" do
      node = %Types.Expression{
        source_info: source_info("42"),
        children: [%Types.Number{source_info: source_info("42")}]
      }
      assert ExprEvaluator.evaluate(node, context()) == 42
    end

    test "evaluates Literal wrapper" do
      node = %Types.Literal{
        source_info: source_info("\"test\""),
        children: [%Types.String{source_info: source_info("\"test\"")}]
      }
      assert ExprEvaluator.evaluate(node, context()) == "test"
    end

    test "evaluates ParenthesizedExpression" do
      node = %Types.ParenthesizedExpression{
        source_info: source_info("(42)"),
        children: [%Types.Number{source_info: source_info("42")}]
      }
      assert ExprEvaluator.evaluate(node, context()) == 42
    end
  end
end
