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

  describe "ready_to_parse?/1 - for loops" do
    test "incomplete for loop without do" do
      refute InputBuffer.ready_to_parse?("for i in 1 2 3")
    end

    test "incomplete for loop with semicolon but no do" do
      refute InputBuffer.ready_to_parse?("for i in 1 2 3;")
    end

    test "complete for loop with do and done" do
      assert InputBuffer.ready_to_parse?("for i in 1 2 3; do echo $i; done")
    end

    test "incomplete for loop with do but no done" do
      refute InputBuffer.ready_to_parse?("for i in 1 2 3; do echo $i")
    end

    test "complete multi-line for loop" do
      input = """
      for i in 1 2 3
      do
        echo $i
      done
      """
      assert InputBuffer.ready_to_parse?(input)
    end
  end

  describe "ready_to_parse?/1 - while loops" do
    test "incomplete while loop without do" do
      refute InputBuffer.ready_to_parse?("while true")
    end

    test "complete while loop with do and done" do
      assert InputBuffer.ready_to_parse?("while true; do echo hi; done")
    end

    test "incomplete while loop with do but no done" do
      refute InputBuffer.ready_to_parse?("while true; do echo hi")
    end
  end

  describe "ready_to_parse?/1 - until loops" do
    test "incomplete until loop without do" do
      refute InputBuffer.ready_to_parse?("until false")
    end

    test "complete until loop with do and done" do
      assert InputBuffer.ready_to_parse?("until false; do echo hi; done")
    end
  end

  describe "ready_to_parse?/1 - if statements" do
    test "incomplete if without then" do
      refute InputBuffer.ready_to_parse?("if true")
    end

    test "incomplete if with then but no fi" do
      refute InputBuffer.ready_to_parse?("if true; then echo hi")
    end

    test "complete if statement with then and fi" do
      assert InputBuffer.ready_to_parse?("if true; then echo hi; fi")
    end

    test "complete multi-line if statement" do
      input = """
      if [ -f file ]; then
        echo exists
      fi
      """
      assert InputBuffer.ready_to_parse?(input)
    end

    test "complete if-else statement" do
      input = """
      if [ -f file ]; then
        echo exists
      else
        echo missing
      fi
      """
      assert InputBuffer.ready_to_parse?(input)
    end

    test "complete if-elif-else statement" do
      input = """
      if [ -f file ]; then
        echo file
      elif [ -d file ]; then
        echo dir
      else
        echo missing
      fi
      """
      assert InputBuffer.ready_to_parse?(input)
    end
  end

  describe "ready_to_parse?/1 - case statements" do
    test "incomplete case without esac" do
      refute InputBuffer.ready_to_parse?("case $var in")
    end

    test "complete case statement with esac" do
      assert InputBuffer.ready_to_parse?("case $var in a) echo a ;; esac")
    end

    test "complete multi-line case statement" do
      input = """
      case $var in
        a)
          echo a
          ;;
        b)
          echo b
          ;;
      esac
      """
      assert InputBuffer.ready_to_parse?(input)
    end
  end

  describe "ready_to_parse?/1 - nested structures" do
    test "nested for loops - incomplete inner" do
      refute InputBuffer.ready_to_parse?("for i in 1; do for j in 2")
    end

    test "nested for loops - complete" do
      assert InputBuffer.ready_to_parse?("for i in 1; do for j in 2; do echo $i$j; done; done")
    end

    test "for loop inside if - incomplete" do
      refute InputBuffer.ready_to_parse?("if true; then for i in 1")
    end

    test "for loop inside if - complete" do
      assert InputBuffer.ready_to_parse?("if true; then for i in 1; do echo $i; done; fi")
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

    test "returns :structure_continuation for open for loop" do
      assert InputBuffer.continuation_type("for i in 1 2 3") == :structure_continuation
    end

    test "returns :structure_continuation for open if" do
      assert InputBuffer.continuation_type("if true") == :structure_continuation
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
  end
end
