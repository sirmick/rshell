defmodule RShell.Builtins.OptionParserTest do
  use ExUnit.Case, async: true

  alias RShell.Builtins.OptionParser

  describe "parse/2 with boolean options" do
    test "parses short boolean flag" do
      specs = [
        %{
          short: "-n",
          type: :boolean,
          default: false,
          key: :no_newline,
          description: "No newline"
        }
      ]

      assert {:ok, %{no_newline: true}, ["hello"]} = OptionParser.parse(["-n", "hello"], specs)
    end

    test "parses long boolean flag" do
      specs = [
        %{
          long: "--no-newline",
          type: :boolean,
          default: false,
          key: :no_newline,
          description: "No newline"
        }
      ]

      assert {:ok, %{no_newline: true}, ["hello"]} =
               OptionParser.parse(["--no-newline", "hello"], specs)
    end

    test "uses defaults when flag not provided" do
      specs = [
        %{
          short: "-n",
          type: :boolean,
          default: false,
          key: :no_newline,
          description: "No newline"
        }
      ]

      assert {:ok, %{no_newline: false}, ["hello"]} = OptionParser.parse(["hello"], specs)
    end

    test "stops parsing at first non-option (POSIX style)" do
      specs = [
        %{
          short: "-n",
          type: :boolean,
          default: false,
          key: :no_newline,
          description: "No newline"
        }
      ]

      assert {:ok, %{no_newline: false}, ["hello", "-n", "world"]} =
               OptionParser.parse(["hello", "-n", "world"], specs)
    end

    test "handles multiple flags" do
      specs = [
        %{
          short: "-n",
          type: :boolean,
          default: false,
          key: :no_newline,
          description: "No newline"
        },
        %{
          short: "-e",
          type: :boolean,
          default: false,
          key: :enable_escapes,
          description: "Enable escapes"
        }
      ]

      assert {:ok, %{no_newline: true, enable_escapes: true}, ["hello"]} =
               OptionParser.parse(["-n", "-e", "hello"], specs)
    end
  end

  describe "parse/2 with string options" do
    test "parses string value after flag" do
      specs = [
        %{short: "-f", type: :string, default: "", key: :file, description: "File path"}
      ]

      assert {:ok, %{file: "test.txt"}, []} = OptionParser.parse(["-f", "test.txt"], specs)
    end

    test "returns error when string option missing value" do
      specs = [
        %{short: "-f", type: :string, default: "", key: :file, description: "File path"}
      ]

      assert {:error, "Option -f requires a value"} = OptionParser.parse(["-f"], specs)
    end

    test "handles long option with equals syntax" do
      specs = [
        %{long: "--file", type: :string, default: "", key: :file, description: "File path"}
      ]

      assert {:ok, %{file: "test.txt"}, []} = OptionParser.parse(["--file=test.txt"], specs)
    end
  end

  describe "parse/2 with integer options" do
    test "parses integer value" do
      specs = [
        %{short: "-c", type: :integer, default: 0, key: :count, description: "Count"}
      ]

      assert {:ok, %{count: 42}, []} = OptionParser.parse(["-c", "42"], specs)
    end

    test "returns error for invalid integer" do
      specs = [
        %{short: "-c", type: :integer, default: 0, key: :count, description: "Count"}
      ]

      assert {:error, "Option -c requires an integer value"} =
               OptionParser.parse(["-c", "abc"], specs)
    end
  end

  describe "parse/2 with mixed short and long options" do
    test "handles both short and long names for same option" do
      specs = [
        %{
          short: "-n",
          long: "--no-newline",
          type: :boolean,
          default: false,
          key: :no_newline,
          description: "No newline"
        }
      ]

      assert {:ok, %{no_newline: true}, ["hello"]} = OptionParser.parse(["-n", "hello"], specs)

      assert {:ok, %{no_newline: true}, ["hello"]} =
               OptionParser.parse(["--no-newline", "hello"], specs)
    end
  end

  describe "parse/2 with -- separator" do
    test "stops parsing after --" do
      specs = [
        %{
          short: "-n",
          type: :boolean,
          default: false,
          key: :no_newline,
          description: "No newline"
        }
      ]

      assert {:ok, %{no_newline: false}, ["-n", "hello"]} =
               OptionParser.parse(["--", "-n", "hello"], specs)
    end
  end

  describe "parse/2 with unknown options" do
    test "treats unknown options as regular arguments" do
      specs = [
        %{
          short: "-n",
          type: :boolean,
          default: false,
          key: :no_newline,
          description: "No newline"
        }
      ]

      assert {:ok, %{no_newline: false}, ["-x", "hello"]} =
               OptionParser.parse(["-x", "hello"], specs)
    end
  end

  describe "format_help/4" do
    test "formats help text with options" do
      specs = [
        %{
          short: "-n",
          long: "--no-newline",
          type: :boolean,
          default: false,
          key: :no_newline,
          description: "No newline"
        },
        %{
          short: "-e",
          type: :boolean,
          default: false,
          key: :enable_escapes,
          description: "Enable escapes"
        }
      ]

      help = OptionParser.format_help("echo", "Output text", specs, "echo [OPTIONS] [STRING]...")

      assert help =~ "echo - Output text"
      assert help =~ "Usage: echo [OPTIONS] [STRING]..."
      assert help =~ "Options:"
      assert help =~ "-n, --no-newline"
      assert help =~ "No newline"
      assert help =~ "-e"
      assert help =~ "Enable escapes"
    end

    test "formats help text without options" do
      help = OptionParser.format_help("true", "Do nothing successfully", [], "true")

      assert help =~ "true - Do nothing successfully"
      assert help =~ "Usage: true"
      refute help =~ "Options:"
    end
  end
end
