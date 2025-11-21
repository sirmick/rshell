defmodule RShell.InputBufferTest do
  use ExUnit.Case
  doctest RShell.InputBuffer

  alias RShell.InputBuffer

  describe "ready_to_parse?/1 - line continuations" do
    test "complete command without backslash" do
      assert InputBuffer.ready_to_parse?("echo hello")
    end

    test "incomplete command with trailing backslash" do
      refute InputBuffer.ready_to_parse?("echo hello\\")
    end

    test "incomplete command with backslash-newline" do
      refute InputBuffer.ready_to_parse?("echo hello\\\n")
    end

    test "complete multi-line with backslash continuation resolved" do
      assert InputBuffer.ready_to_parse?("echo hello\\\nworld")
    end
  end

  describe "ready_to_parse?/1 - quote handling" do
    test "complete command with balanced single quotes" do
      assert InputBuffer.ready_to_parse?("echo 'hello world'")
    end

    test "complete command with balanced double quotes" do
      assert InputBuffer.ready_to_parse?("echo \"hello world\"")
    end

    test "incomplete command with unclosed single quote" do
      refute InputBuffer.ready_to_parse?("echo 'hello")
    end

    test "incomplete command with unclosed double quote" do
      refute InputBuffer.ready_to_parse?("echo \"hello")
    end

    test "complete command with escaped quote" do
      assert InputBuffer.ready_to_parse?("echo \"hello \\\" world\"")
    end

    test "incomplete with nested quotes of different types" do
      refute InputBuffer.ready_to_parse?("echo \"hello 'world")
    end

    test "complete with nested quotes properly closed" do
      assert InputBuffer.ready_to_parse?("echo \"hello 'world'\"")
    end
  end

  describe "ready_to_parse?/1 - heredoc handling" do
    test "complete command without heredoc" do
      assert InputBuffer.ready_to_parse?("cat file.txt")
    end

    test "incomplete heredoc without end marker" do
      refute InputBuffer.ready_to_parse?("cat <<EOF\nsome content")
    end

    test "complete heredoc with end marker" do
      assert InputBuffer.ready_to_parse?("cat <<EOF\nsome content\nEOF")
    end

    test "incomplete heredoc with dash syntax" do
      refute InputBuffer.ready_to_parse?("cat <<-EOF\nsome content")
    end

    test "complete heredoc with dash syntax and end marker" do
      assert InputBuffer.ready_to_parse?("cat <<-EOF\nsome content\nEOF")
    end
  end

  describe "ready_to_parse?/1 - for loops (RShell syntax)" do
    test "for loop without braces is syntactically complete (will be caught as parser error)" do
      # InputBuffer only checks brace balance, not RShell syntax semantics
      # The parser will catch this as a syntax error (missing required braces)
      assert InputBuffer.ready_to_parse?("for (i in items)")
    end

    test "incomplete for loop with opening brace but no closing brace" do
      refute InputBuffer.ready_to_parse?("for (i in items) {")
    end

    test "complete for loop with braces" do
      assert InputBuffer.ready_to_parse?("for (i in items) { echo $i }")
    end

    test "incomplete for loop with body but no closing brace" do
      refute InputBuffer.ready_to_parse?("for (i in items) { echo $i")
    end

    test "complete multi-line for loop" do
      input = """
      for (i in items) {
        echo $i
      }
      """

      assert InputBuffer.ready_to_parse?(input)
    end
  end

  describe "ready_to_parse?/1 - while loops (RShell syntax)" do
    test "while loop without braces is syntactically complete (will be caught as parser error)" do
      # InputBuffer only checks brace balance, not RShell syntax semantics
      assert InputBuffer.ready_to_parse?("while (true)")
    end

    test "complete while loop with braces" do
      assert InputBuffer.ready_to_parse?("while (true) { echo hi }")
    end

    test "incomplete while loop with opening brace but no closing" do
      refute InputBuffer.ready_to_parse?("while (true) { echo hi")
    end
  end

  describe "ready_to_parse?/1 - if statements (RShell syntax)" do
    test "if without braces is syntactically complete (will be caught as parser error)" do
      # InputBuffer only checks brace balance, not RShell syntax semantics
      assert InputBuffer.ready_to_parse?("if (true)")
    end

    test "incomplete if with opening brace but no closing" do
      refute InputBuffer.ready_to_parse?("if (true) { echo hi")
    end

    test "complete if statement with braces" do
      assert InputBuffer.ready_to_parse?("if (true) { echo hi }")
    end

    test "complete multi-line if statement" do
      input = """
      if (condition) {
        echo exists
      }
      """

      assert InputBuffer.ready_to_parse?(input)
    end

    test "complete if-else statement" do
      input = """
      if (condition) {
        echo exists
      } else {
        echo missing
      }
      """

      assert InputBuffer.ready_to_parse?(input)
    end

    test "complete if-elif-else statement" do
      input = """
      if (cond1) {
        echo first
      } elif (cond2) {
        echo second
      } else {
        echo third
      }
      """

      assert InputBuffer.ready_to_parse?(input)
    end
  end

  describe "ready_to_parse?/1 - nested structures (RShell syntax)" do
    test "nested for loops - incomplete inner" do
      refute InputBuffer.ready_to_parse?("for (i in a) { for (j in b) {")
    end

    test "nested for loops - complete" do
      assert InputBuffer.ready_to_parse?("for (i in a) { for (j in b) { echo $i$j } }")
    end

    test "for loop inside if - incomplete" do
      refute InputBuffer.ready_to_parse?("if (true) { for (i in items) {")
    end

    test "for loop inside if - complete" do
      assert InputBuffer.ready_to_parse?("if (true) { for (i in items) { echo $i } }")
    end
  end

  describe "ready_to_parse?/1 - object literals (RShell syntax)" do
    test "complete object literal" do
      assert InputBuffer.ready_to_parse?("X = { y: 1, z: 2 }")
    end

    test "incomplete object literal - missing closing brace" do
      refute InputBuffer.ready_to_parse?("X = { y: 1")
    end

    test "nested object literals - complete" do
      assert InputBuffer.ready_to_parse?("X = { a: { b: 1 } }")
    end

    test "nested object literals - incomplete" do
      refute InputBuffer.ready_to_parse?("X = { a: { b: 1 }")
    end
  end

  describe "continuation_type/1" do
    test "returns :complete for complete command" do
      assert InputBuffer.continuation_type("echo hello") == :complete
    end

    test "returns :line_continuation for backslash" do
      assert InputBuffer.continuation_type("echo hello\\") == :line_continuation
    end

    test "returns :quote_continuation for unclosed quote" do
      assert InputBuffer.continuation_type("echo \"hello") == :quote_continuation
    end

    test "returns :heredoc_continuation for unclosed heredoc" do
      assert InputBuffer.continuation_type("cat <<EOF\ndata") == :heredoc_continuation
    end

    test "returns :structure_continuation for open brace" do
      assert InputBuffer.continuation_type("if (true) {") == :structure_continuation
    end

    test "returns :structure_continuation for incomplete for loop" do
      assert InputBuffer.continuation_type("for (i in items) {") == :structure_continuation
    end
  end

  describe "edge cases" do
    test "empty string is complete" do
      assert InputBuffer.ready_to_parse?("")
    end

    test "whitespace only is complete" do
      assert InputBuffer.ready_to_parse?("   \n  \n  ")
    end

    test "comment is complete" do
      assert InputBuffer.ready_to_parse?("# this is a comment")
    end

    test "command with comment is complete" do
      assert InputBuffer.ready_to_parse?("echo hello # comment")
    end

    test "backslash in single quotes doesn't escape" do
      assert InputBuffer.ready_to_parse?("echo 'hello \\\\ world'")
    end

    test "multiple commands on one line are complete" do
      assert InputBuffer.ready_to_parse?("echo a; echo b; echo c")
    end

    test "braces inside quotes don't affect brace counting" do
      assert InputBuffer.ready_to_parse?("echo '{ not a brace }'")
    end

    test "braces inside double quotes don't affect brace counting" do
      assert InputBuffer.ready_to_parse?("echo \"{ also not a brace }\"")
    end
  end
end
