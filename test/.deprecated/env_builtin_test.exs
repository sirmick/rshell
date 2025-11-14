defmodule RShell.EnvBuiltinTest do
  use ExUnit.Case, async: true

  alias RShell.Builtins

  describe "env with no arguments" do
    test "lists all environment variables" do
      context = %{env: %{"PATH" => "/usr/bin", "USER" => "test"}}

      {_ctx, stdout, stderr, exit_code} = Builtins.execute("env", [], "", context)

      output = Enum.join(stdout, "")
      assert output =~ "PATH=/usr/bin"
      assert output =~ "USER=test"
      assert Enum.join(stderr, "") == ""
      assert exit_code == 0
    end

    test "returns empty output for empty env" do
      context = %{env: %{}}

      {_ctx, stdout, _stderr, exit_code} = Builtins.execute("env", [], "", context)

      assert Enum.join(stdout, "") == ""
      assert exit_code == 0
    end

    test "sorts variables alphabetically" do
      context = %{env: %{"ZEBRA" => "z", "ALPHA" => "a", "BETA" => "b"}}

      {_ctx, stdout, _stderr, _code} = Builtins.execute("env", [], "", context)

      output = Enum.join(stdout, "")
      lines = String.split(output, "\n", trim: true)
      assert lines == ["ALPHA=a", "BETA=b", "ZEBRA=z"]
    end
  end

  describe "env with variable lookup" do
    test "retrieves single variable" do
      context = %{env: %{"FOO" => "bar"}}

      {_ctx, stdout, _stderr, exit_code} = Builtins.execute("env", ["FOO"], "", context)

      assert Enum.join(stdout, "") == "bar\n"
      assert exit_code == 0
    end

    test "retrieves multiple variables" do
      context = %{env: %{"A" => "1", "B" => "2", "C" => "3"}}

      {_ctx, stdout, _stderr, exit_code} = Builtins.execute("env", ["A", "C"], "", context)

      output = Enum.join(stdout, "")
      assert output == "1\n3\n"
      assert exit_code == 0
    end

    test "returns empty for undefined variable" do
      context = %{env: %{}}

      {_ctx, stdout, _stderr, exit_code} = Builtins.execute("env", ["UNDEFINED"], "", context)

      # Undefined variables return empty string (no newline when value is empty)
      assert Enum.join(stdout, "") == ""
      assert exit_code == 0
    end

    test "formats map values as pretty JSON" do
      context = %{env: %{"CONFIG" => %{"host" => "localhost", "port" => 5432}}}

      {_ctx, stdout, _stderr, _code} = Builtins.execute("env", ["CONFIG"], "", context)

      output = Enum.join(stdout, "")
      assert output =~ "\"host\""
      assert output =~ "\"localhost\""
      assert output =~ "\"port\""
    end

    test "formats list values as pretty JSON" do
      context = %{env: %{"SERVERS" => ["web1", "web2", "db1"]}}

      {_ctx, stdout, _stderr, _code} = Builtins.execute("env", ["SERVERS"], "", context)

      output = Enum.join(stdout, "")
      assert output =~ "["
      assert output =~ "\"web1\""
      assert output =~ "\"web2\""
    end
  end

  describe "env with variable assignment" do
    test "sets simple string variable" do
      context = %{env: %{}}

      {new_ctx, stdout, _stderr, exit_code} =
        Builtins.execute("env", ["FOO=\"bar\""], "", context)

      assert new_ctx.env["FOO"] == "bar"
      assert Enum.join(stdout, "") == ""
      assert exit_code == 0
    end

    test "sets map variable from JSON" do
      context = %{env: %{}}

      {new_ctx, _stdout, _stderr, _code} =
        Builtins.execute("env", ["CONFIG={\"host\":\"localhost\"}"], "", context)

      assert new_ctx.env["CONFIG"] == %{"host" => "localhost"}
    end

    test "sets list variable from JSON" do
      context = %{env: %{}}

      {new_ctx, _stdout, _stderr, _code} =
        Builtins.execute("env", ["SERVERS=[\"web1\",\"web2\"]"], "", context)

      assert new_ctx.env["SERVERS"] == ["web1", "web2"]
    end

    test "sets number variable" do
      context = %{env: %{}}

      {new_ctx, _stdout, _stderr, _code} =
        Builtins.execute("env", ["COUNT=42"], "", context)

      assert new_ctx.env["COUNT"] == 42
    end

    test "sets boolean variable" do
      context = %{env: %{}}

      {new_ctx, _stdout, _stderr, _code} =
        Builtins.execute("env", ["DEBUG=true"], "", context)

      assert new_ctx.env["DEBUG"] == true
    end

    test "sets multiple variables at once" do
      context = %{env: %{}}

      {new_ctx, _stdout, _stderr, exit_code} =
        Builtins.execute("env", ["A=1", "B=\"hello\"", "C=[1,2,3]"], "", context)

      assert new_ctx.env["A"] == 1
      assert new_ctx.env["B"] == "hello"
      assert new_ctx.env["C"] == [1, 2, 3]
      assert exit_code == 0
    end

    test "overwrites existing variable" do
      context = %{env: %{"FOO" => "old"}}

      {new_ctx, _stdout, _stderr, _code} =
        Builtins.execute("env", ["FOO=\"new\""], "", context)

      assert new_ctx.env["FOO"] == "new"
    end

    test "handles complex nested structure" do
      context = %{env: %{}}
      json = ~s(CONFIG={"db":{"host":"localhost","port":5432},"cache":{"ttl":3600}})

      {new_ctx, _stdout, _stderr, _code} =
        Builtins.execute("env", [json], "", context)

      expected = %{
        "db" => %{"host" => "localhost", "port" => 5432},
        "cache" => %{"ttl" => 3600}
      }

      assert new_ctx.env["CONFIG"] == expected
    end
  end

  describe "env with mixed operations" do
    test "sets and retrieves in same call" do
      context = %{env: %{"OLD" => "value"}}

      {new_ctx, stdout, _stderr, _code} =
        Builtins.execute("env", ["NEW=42", "OLD"], "", context)

      assert new_ctx.env["NEW"] == 42
      output = Enum.join(stdout, "")
      assert output == "value\n"
    end

    test "processes assignments before lookups" do
      context = %{env: %{}}

      # Set A, then look it up
      {new_ctx, stdout, _stderr, _code} =
        Builtins.execute("env", ["A=123", "A"], "", context)

      assert new_ctx.env["A"] == 123
      # Lookup happens after assignment
      output = Enum.join(stdout, "")
      assert output == "123\n"
    end
  end

  describe "env error handling" do
    test "handles invalid JSON gracefully" do
      context = %{env: %{}}

      # Capture warnings
      import ExUnit.CaptureIO

      _output =
        capture_io(:stderr, fn ->
          result = Builtins.execute("env", ["BAD={invalid}"], "", context)
          send(self(), {:result, result})
          :timer.sleep(10)
        end)

      receive do
        {:result, {new_ctx, _stdout, _stderr, _code}} ->
          # Should fall back to string
          assert is_binary(new_ctx.env["BAD"])
      end
    end
  end

  describe "env with nil context.env" do
    test "handles nil env gracefully" do
      context = %{env: nil}

      {_ctx, stdout, _stderr, exit_code} = Builtins.execute("env", [], "", context)

      assert Enum.join(stdout, "") == ""
      assert exit_code == 0
    end

    test "creates env when setting variable with nil env" do
      context = %{env: nil}

      {new_ctx, _stdout, _stderr, _code} =
        Builtins.execute("env", ["FOO=\"bar\""], "", context)

      assert new_ctx.env["FOO"] == "bar"
    end
  end
end
