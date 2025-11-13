defmodule RShell.EnvJSONTest do
  use ExUnit.Case, async: true

  alias RShell.EnvJSON

  doctest RShell.EnvJSON

  describe "parse/1" do
    test "parses JSON object" do
      assert {:ok, %{"host" => "localhost", "port" => 5432}} =
        EnvJSON.parse("{\"host\":\"localhost\",\"port\":5432}")
    end

    test "parses nested JSON object" do
      assert {:ok, %{"db" => %{"host" => "localhost"}}} =
        EnvJSON.parse("{\"db\":{\"host\":\"localhost\"}}")
    end

    test "parses JSON array" do
      assert {:ok, ["web1", "web2", "db1"]} =
        EnvJSON.parse("[\"web1\",\"web2\",\"db1\"]")
    end

    test "parses mixed array" do
      assert {:ok, [1, "two", %{"three" => 3}]} =
        EnvJSON.parse("[1,\"two\",{\"three\":3}]")
    end

    test "parses integer" do
      assert {:ok, 42} = EnvJSON.parse("42")
    end

    test "parses float" do
      assert {:ok, 3.14} = EnvJSON.parse("3.14")
    end

    test "parses boolean true" do
      assert {:ok, true} = EnvJSON.parse("true")
    end

    test "parses boolean false" do
      assert {:ok, false} = EnvJSON.parse("false")
    end

    test "parses null as nil" do
      assert {:ok, nil} = EnvJSON.parse("null")
    end

    test "parses quoted string" do
      assert {:ok, "hello world"} = EnvJSON.parse("\"hello world\"")
    end

    test "errors on unquoted string" do
      assert {:error, error_msg} = EnvJSON.parse("hello")
      assert error_msg =~ "unexpected byte"
    end

    test "errors on invalid JSON" do
      assert {:error, _} = EnvJSON.parse("{invalid}")
    end

    test "errors on malformed JSON" do
      assert {:error, _} = EnvJSON.parse("{\"x\":}")
    end

    test "passes through non-string values" do
      assert {:ok, %{"already" => "native"}} = EnvJSON.parse(%{"already" => "native"})
      assert {:ok, [1, 2, 3]} = EnvJSON.parse([1, 2, 3])
      assert {:ok, 42} = EnvJSON.parse(42)
    end
  end

  describe "encode/1" do
    test "encodes map to JSON" do
      assert "{\"host\":\"localhost\"}" = EnvJSON.encode(%{"host" => "localhost"})
    end

    test "encodes list to JSON" do
      assert "[1,2,3]" = EnvJSON.encode([1, 2, 3])
    end

    test "encodes nested structure" do
      result = EnvJSON.encode(%{"db" => %{"host" => "localhost"}})
      assert result =~ "\"db\""
      assert result =~ "\"host\""
    end

    test "passes through string unchanged" do
      assert "hello" = EnvJSON.encode("hello")
    end

    test "converts integer to string" do
      assert "42" = EnvJSON.encode(42)
    end

    test "converts float to string" do
      assert "3.14" = EnvJSON.encode(3.14)
    end

    test "converts true to string" do
      assert "true" = EnvJSON.encode(true)
    end

    test "converts false to string" do
      assert "false" = EnvJSON.encode(false)
    end

    test "converts nil to empty string" do
      assert "" = EnvJSON.encode(nil)
    end

    test "converts atom to string" do
      assert "test" = EnvJSON.encode(:test)
    end

    test "handles charlist by converting to string" do
      assert "hello" = EnvJSON.encode('hello')
    end
  end

  describe "format/1" do
    test "pretty-prints map" do
      result = EnvJSON.format(%{"host" => "localhost", "port" => 5432})
      assert result =~ "\"host\""
      assert result =~ "\"localhost\""
      assert result =~ "\n"  # Contains newlines for pretty-printing
    end

    test "pretty-prints list" do
      result = EnvJSON.format([1, 2, 3])
      assert result =~ "[\n"  # Pretty-printed array
    end

    test "passes through string unchanged" do
      assert "hello" = EnvJSON.format("hello")
    end

    test "formats numbers" do
      assert "42" = EnvJSON.format(42)
    end

    test "handles charlist" do
      assert "hello" = EnvJSON.format('hello')
    end
  end

  describe "round-trip" do
    test "map round-trips correctly" do
      original = %{"host" => "localhost", "port" => 5432}
      encoded = EnvJSON.encode(original)
      assert {:ok, ^original} = EnvJSON.parse(encoded)
    end

    test "list round-trips correctly" do
      original = [1, 2, 3]
      encoded = EnvJSON.encode(original)
      assert {:ok, ^original} = EnvJSON.parse(encoded)
    end

    test "nested structure round-trips correctly" do
      original = %{"servers" => ["web1", "web2"], "count" => 2}
      encoded = EnvJSON.encode(original)
      assert {:ok, ^original} = EnvJSON.parse(encoded)
    end
  end
end
