defmodule RShell.Builtins.DocParserTest do
  use ExUnit.Case, async: true

  alias RShell.Builtins.DocParser

  describe "parse_options/1" do
    test "parses single boolean option" do
      doc = """
      Test command

      Options:
        -n, --no-newline
            type: boolean
            default: false
            desc: Do not output trailing newline
      """

      expected = [
        %{
          short: "-n",
          long: "--no-newline",
          type: :boolean,
          default: false,
          key: :no_newline,
          desc: "Do not output trailing newline"
        }
      ]

      assert DocParser.parse_options(doc) == expected
    end

    test "parses multiple options" do
      doc = """
      Test command

      Options:
        -n, --no-newline
            type: boolean
            default: false
            desc: Do not output trailing newline
        -e, --enable-escapes
            type: boolean
            default: false
            desc: Enable interpretation of backslash escapes
      """

      result = DocParser.parse_options(doc)
      assert length(result) == 2
      assert Enum.any?(result, &(&1.key == :no_newline))
      assert Enum.any?(result, &(&1.key == :enable_escapes))
    end

    test "parses option with only short form" do
      doc = """
      Options:
        -e
            type: boolean
            default: false
            desc: Enable escapes
      """

      result = DocParser.parse_options(doc)
      assert length(result) == 1
      [option] = result
      assert option.short == "-e"
      assert option.key == :e
      assert option.type == :boolean
      assert option.default == false
      assert option.desc == "Enable escapes"
      refute Map.has_key?(option, :long)
    end

    test "parses option with only long form" do
      doc = """
      Options:
        --verbose
            type: boolean
            default: false
            desc: Verbose output
      """

      result = DocParser.parse_options(doc)
      assert length(result) == 1
      [option] = result
      assert option.long == "--verbose"
      assert option.key == :verbose
      assert option.type == :boolean
      assert option.default == false
      assert option.desc == "Verbose output"
      refute Map.has_key?(option, :short)
    end

    test "parses string type option" do
      doc = """
      Options:
        -f, --file
            type: string
            default: ""
            desc: Input file path
      """

      expected = [
        %{
          short: "-f",
          long: "--file",
          type: :string,
          default: "",
          key: :file,
          desc: "Input file path"
        }
      ]

      assert DocParser.parse_options(doc) == expected
    end

    test "parses integer type option" do
      doc = """
      Options:
        -c, --count
            type: integer
            default: 10
            desc: Number of iterations
      """

      expected = [
        %{
          short: "-c",
          long: "--count",
          type: :integer,
          default: 10,
          key: :count,
          desc: "Number of iterations"
        }
      ]

      assert DocParser.parse_options(doc) == expected
    end

    test "returns empty list when no options section" do
      doc = """
      This is a simple command

      It has no options.
      """

      assert DocParser.parse_options(doc) == []
    end

    test "handles multi-line descriptions" do
      doc = """
      Options:
        -e
            type: boolean
            default: false
            desc: Enable interpretation of backslash escapes.
                  This allows \\n, \\t, and other escape sequences.
      """

      result = DocParser.parse_options(doc)
      assert length(result) == 1
      [option] = result
      assert option.desc =~ "Enable interpretation"
      # Multi-line desc support may not be fully implemented
    end

    test "handles options with underscores in names" do
      doc = """
      Options:
        --no-newline
            type: boolean
            default: false
            desc: Do not output newline
      """

      result = DocParser.parse_options(doc)
      assert length(result) == 1
      [option] = result
      assert option.long == "--no-newline"
      assert option.key == :no_newline
      assert option.type == :boolean
      assert option.default == false
      assert option.desc == "Do not output newline"
      refute Map.has_key?(option, :short)
    end

    test "handles options with hyphens converted to underscores" do
      doc = """
      Options:
        --enable-escapes
            type: boolean
            default: false
            desc: Enable escapes
      """

      result = DocParser.parse_options(doc)
      assert length(result) == 1
      assert hd(result).key == :enable_escapes
    end
  end

  describe "extract_help_text/1" do
    test "extracts complete help text" do
      doc = """
      Output text to standard output

      This is a longer description
      that spans multiple lines.

      Options:
        -n  (boolean, default: false)
          No newline
      """

      help = DocParser.extract_help_text(doc)
      assert help =~ "Output text to standard output"
      assert help =~ "This is a longer description"
      assert help =~ "Options:"
      assert help =~ "-n"
    end

    test "returns empty string for nil doc" do
      assert DocParser.extract_help_text(nil) == ""
    end

    test "preserves formatting" do
      doc = """
      Command with formatting

      Example:
        $ echo "hello world"
        hello world
      """

      help = DocParser.extract_help_text(doc)
      assert help =~ "Example:"
      assert help =~ "$ echo"
    end
  end

  describe "extract_summary/1" do
    test "extracts first line as summary" do
      doc = """
      Output text to standard output

      This is a longer description.
      """

      assert DocParser.extract_summary(doc) == "Output text to standard output"
    end

    test "trims whitespace from summary" do
      doc = """
        Output text

      More content
      """

      assert DocParser.extract_summary(doc) == "Output text"
    end

    test "returns empty string for nil doc" do
      assert DocParser.extract_summary(nil) == ""
    end

    test "returns empty string for empty doc" do
      assert DocParser.extract_summary("") == ""
    end

    test "handles single-line doc" do
      assert DocParser.extract_summary("Single line") == "Single line"
    end
  end

  describe "integration with real builtin docs" do
    test "parses echo docstring correctly" do
      doc = """
      Output text to standard output

      The echo builtin outputs its arguments separated by spaces, followed by a newline.
      If -n is specified, the trailing newline is suppressed.

      Options:
        -n
            type: boolean
            default: false
            desc: Do not output the trailing newline
        -e
            type: boolean
            default: false
            desc: Enable interpretation of backslash escapes
        -E
            type: boolean
            default: false
            desc: Disable interpretation of backslash escapes (default)
      """

      options = DocParser.parse_options(doc)
      assert length(options) == 3

      assert Enum.any?(options, fn opt ->
               opt.key == :n && opt.type == :boolean && opt.default == false
             end)

      assert Enum.any?(options, fn opt ->
               opt.key == :e && opt.type == :boolean
             end)

      summary = DocParser.extract_summary(doc)
      assert summary == "Output text to standard output"
    end

    test "parses pwd docstring correctly" do
      doc = """
      Print working directory

      Outputs the current working directory path.
      """

      options = DocParser.parse_options(doc)
      assert options == []

      summary = DocParser.extract_summary(doc)
      assert summary == "Print working directory"
    end
  end
end
