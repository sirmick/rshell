defmodule IncrementalParserNifTest do
  use ExUnit.Case

  @moduledoc """
  Low-level tests for the incremental parsing NIF functions.
  These test the Rust layer directly before building the GenServer.
  """

  describe "new_parser/0" do
    test "creates a new parser resource" do
      assert {:ok, resource} = BashParser.new_parser()
      assert is_reference(resource)
    end
  end

  describe "new_parser_with_size/1" do
    test "creates a parser with custom buffer size" do
      assert {:ok, resource} = BashParser.new_parser_with_size(1024)
      assert is_reference(resource)
    end
  end

  describe "parse_incremental/2" do
    test "parses a simple command incrementally" do
      {:ok, resource} = BashParser.new_parser()

      # Parse fragment
      {:ok, ast} = BashParser.parse_incremental(resource, "echo 'hello'\n")

      assert ast["type"] == "program"
      assert is_list(ast["children"])
    end

    test "accumulates fragments across multiple calls" do
      {:ok, resource} = BashParser.new_parser()

      # First fragment
      {:ok, ast1} = BashParser.parse_incremental(resource, "echo 'hello'\n")
      assert ast1["type"] == "program"
      assert length(ast1["children"]) == 1

      # Second fragment - accumulates with first
      {:ok, ast2} = BashParser.parse_incremental(resource, "echo 'world'\n")
      assert ast2["type"] == "program"

      # Should have both commands
      assert length(ast2["children"]) == 2

      # Verify accumulated input contains both
      input = BashParser.get_accumulated_input(resource)
      assert String.contains?(input, "hello")
      assert String.contains?(input, "world")
      assert input == "echo 'hello'\necho 'world'\n"
    end

    test "handles incomplete input gracefully" do
      {:ok, resource} = BashParser.new_parser()

      # Incomplete if statement
      {:ok, ast} = BashParser.parse_incremental(resource, "if [ -f file ]; then\n")

      # Should parse but may have errors
      assert ast["type"] == "program"
      assert Map.has_key?(ast, "has_errors") == false or ast["has_errors"] == true
    end

    test "completes incomplete input with more fragments" do
      {:ok, resource} = BashParser.new_parser()

      # Fragment 1: incomplete if
      {:ok, _ast1} = BashParser.parse_incremental(resource, "if [ -f file ]; then\n")

      # Fragment 2: body
      {:ok, _ast2} = BashParser.parse_incremental(resource, "  echo 'exists'\n")

      # Fragment 3: complete if
      {:ok, ast3} = BashParser.parse_incremental(resource, "fi\n")

      assert ast3["type"] == "program"
      # Should have exactly 1 complete if statement
      assert length(ast3["children"]) == 1,
             "Expected 1 complete if_statement, got #{length(ast3["children"])}"
    end

    test "enforces buffer size limit" do
      # Create parser with small buffer (100 bytes)
      {:ok, resource} = BashParser.new_parser_with_size(100)

      # Try to exceed buffer
      large_fragment = String.duplicate("echo 'test'\n", 20)

      result = BashParser.parse_incremental(resource, large_fragment)

      # Should get buffer overflow error
      assert {:error, error_map} = result
      assert error_map["reason"] == "buffer_overflow"
      assert is_integer(error_map["current_size"])
      assert is_integer(error_map["fragment_size"])
      assert is_integer(error_map["max_size"])
    end

    test "incremental parsing is efficient (uses old tree)" do
      {:ok, resource} = BashParser.new_parser()

      # Parse a moderately complex script
      script = """
      echo 'first'
      echo 'second'
      if [ -f file ]; then
        echo 'exists'
      fi
      """

      # Parse initial content
      {:ok, _ast1} = BashParser.parse_incremental(resource, script)

      # Add more content (tree-sitter should reuse previous parse tree)
      {:ok, ast2} = BashParser.parse_incremental(resource, "echo 'third'\n")

      # Should have all commands (if + 3 echo commands)
      assert ast2["type"] == "program"

      assert length(ast2["children"]) == 4,
             "Expected 4 children (1 if + 3 echo), got #{length(ast2["children"])}"

      # Verify third command is present
      input = BashParser.get_accumulated_input(resource)
      assert String.contains?(input, "third")
    end

    test "parses fragments without newlines incrementally" do
      {:ok, resource} = BashParser.new_parser()

      # Fragment 1: Command without newline (incomplete)
      {:ok, ast1} = BashParser.parse_incremental(resource, "echo \"yo\"")

      # At this point, tree-sitter sees incomplete input
      assert ast1["type"] == "program"
      # May have error nodes due to missing newline

      # Fragment 2: Add the newline to complete the command
      {:ok, ast2} = BashParser.parse_incremental(resource, "\n")

      # Now should be a complete, valid command
      assert ast2["type"] == "program"
      assert is_list(ast2["children"])

      assert length(ast2["children"]) == 1,
             "Expected 1 complete command, got #{length(ast2["children"])}"

      # Verify accumulated input
      input = BashParser.get_accumulated_input(resource)
      assert input == "echo \"yo\"\n"

      # Should have no errors after completion
      assert BashParser.has_errors(resource) == false
    end

    test "handles multi-line command split across fragments" do
      {:ok, resource} = BashParser.new_parser()

      # Fragment 1: Start of if statement
      {:ok, _ast1} = BashParser.parse_incremental(resource, "if [ -f file ]; then")

      # Fragment 2: Newline to complete condition line
      {:ok, _ast2} = BashParser.parse_incremental(resource, "\n")

      # Fragment 3: Body without newline
      {:ok, _ast3} = BashParser.parse_incremental(resource, "    echo \"exists\"")

      # Fragment 4: Newline after body
      {:ok, _ast4} = BashParser.parse_incremental(resource, "\n")

      # Fragment 5: Closing without newline
      {:ok, _ast5} = BashParser.parse_incremental(resource, "fi")

      # Fragment 6: Final newline
      {:ok, ast6} = BashParser.parse_incremental(resource, "\n")

      # Final AST should be complete
      assert ast6["type"] == "program"
      input = BashParser.get_accumulated_input(resource)
      assert String.contains?(input, "if [ -f file ]; then")
      assert String.contains?(input, "echo \"exists\"")
      assert String.contains?(input, "fi")
    end

    test "character-by-character incremental parsing" do
      {:ok, resource} = BashParser.new_parser()

      # Parse character by character
      command = "echo 'test'\n"

      Enum.reduce(String.graphemes(command), nil, fn char, _acc ->
        {:ok, ast} = BashParser.parse_incremental(resource, char)
        ast
      end)

      # Final accumulated input should match
      input = BashParser.get_accumulated_input(resource)
      assert input == command

      # Should have a valid program
      {:ok, final_ast} = BashParser.get_current_ast(resource)
      assert final_ast["type"] == "program"
    end

    test "sequential similar commands are all parsed" do
      {:ok, resource} = BashParser.new_parser()

      # First command
      {:ok, ast1} = BashParser.parse_incremental(resource, "echo yo\n")
      assert ast1["type"] == "program"
      assert length(ast1["children"]) == 1
      first_child = hd(ast1["children"])
      assert first_child["type"] == "command"
      assert String.contains?(first_child["text"], "echo yo")

      # Second similar command
      {:ok, ast2} = BashParser.parse_incremental(resource, "echo yo mama\n")
      assert ast2["type"] == "program"

      # Should have both commands now
      assert length(ast2["children"]) == 2

      # Verify accumulated input contains both commands
      input = BashParser.get_accumulated_input(resource)
      assert input == "echo yo\necho yo mama\n"
      assert String.contains?(input, "echo yo\n")
      assert String.contains?(input, "echo yo mama")

      # Verify both commands are in the AST
      children = ast2["children"] || []
      assert length(children) == 2
      assert Enum.at(children, 0)["text"] == "echo yo"
      assert Enum.at(children, 1)["text"] == "echo yo mama"
    end

    test "incremental for-loop shows node evolution" do
      {:ok, resource} = BashParser.new_parser()

      # Fragment 1: Start of for-loop (incomplete - should have error)
      {:ok, ast1} = BashParser.parse_incremental(resource, "for i in $a\n")
      assert ast1["type"] == "program"

      assert length(ast1["children"]) == 1,
             "Fragment 1: Expected 1 child, got #{length(ast1["children"])}"

      first_child = hd(ast1["children"])
      # First child should be an ERROR node or incomplete for_statement
      assert first_child["type"] in ["ERROR", "for_statement"],
             "Fragment 1: Expected ERROR or for_statement, got #{first_child["type"]}"

      assert Map.has_key?(ast1, "has_errors") == false or ast1["has_errors"] == true

      # Fragment 2: Add "do" (still incomplete)
      {:ok, ast2} = BashParser.parse_incremental(resource, "do\n")
      assert ast2["type"] == "program"

      assert length(ast2["children"]) == 1,
             "Fragment 2: Expected 1 child, got #{length(ast2["children"])}"

      # Fragment 3: Add body (still incomplete)
      {:ok, ast3} = BashParser.parse_incremental(resource, "echo $i\n")
      assert ast3["type"] == "program"

      assert length(ast3["children"]) == 1,
             "Fragment 3: Expected 1 child, got #{length(ast3["children"])}"

      # Fragment 4: Complete with "done" (should now be valid for_statement)
      {:ok, ast4} = BashParser.parse_incremental(resource, "done\n")
      assert ast4["type"] == "program"

      assert length(ast4["children"]) == 1,
             "Fragment 4: Expected 1 complete for_statement, got #{length(ast4["children"])}"

      # Final child should be a complete for_statement without errors
      final_child = hd(ast4["children"])

      assert final_child["type"] == "for_statement",
             "Expected for_statement, got #{final_child["type"]}"

      assert BashParser.has_errors(resource) == false,
             "Expected no errors in complete for-loop"

      # Verify the structure is complete
      assert is_map(final_child["body"]), "for_statement should have body map"
      assert is_map(final_child["value"]), "for_statement should have value map"
      assert is_map(final_child["variable"]), "for_statement should have variable map"

      # Verify accumulated input
      input = BashParser.get_accumulated_input(resource)

      assert input == "for i in $a\ndo\necho $i\ndone\n",
             "Accumulated input mismatch:\n#{inspect(input)}"
    end
  end

  describe "reset_parser/1" do
    test "clears accumulated input" do
      {:ok, resource} = BashParser.new_parser()

      # Parse something
      {:ok, _ast1} = BashParser.parse_incremental(resource, "echo 'first'\n")

      # Check buffer size
      size1 = BashParser.get_buffer_size(resource)
      assert size1 > 0

      # Reset
      :ok = BashParser.reset_parser(resource)

      # Buffer should be empty
      size2 = BashParser.get_buffer_size(resource)
      assert size2 == 0
    end

    test "allows fresh parsing after reset" do
      {:ok, resource} = BashParser.new_parser()

      # Parse something
      {:ok, _ast1} = BashParser.parse_incremental(resource, "echo 'first'\n")

      # Reset
      :ok = BashParser.reset_parser(resource)

      # Parse something new (should not include 'first')
      {:ok, ast2} = BashParser.parse_incremental(resource, "echo 'second'\n")

      # Should only have 'second' command
      assert ast2["type"] == "program"
      text = BashParser.get_accumulated_input(resource)
      assert text == "echo 'second'\n"
      refute String.contains?(text, "first")
    end
  end

  describe "get_current_ast/1" do
    test "returns last parsed AST without reparsing" do
      {:ok, resource} = BashParser.new_parser()

      # Parse something
      {:ok, ast1} = BashParser.parse_incremental(resource, "echo 'hello'\n")

      # Get current AST (should be same)
      {:ok, ast2} = BashParser.get_current_ast(resource)

      assert ast1["type"] == ast2["type"]
      assert ast1["children"] == ast2["children"]
    end

    test "returns error when no tree exists" do
      {:ok, resource} = BashParser.new_parser()

      # No parsing done yet
      result = BashParser.get_current_ast(resource)

      assert {:error, %{"reason" => "no_tree"}} = result
    end
  end

  describe "has_errors/1" do
    test "returns false for valid syntax" do
      {:ok, resource} = BashParser.new_parser()

      {:ok, _ast} = BashParser.parse_incremental(resource, "echo 'hello'\n")

      assert BashParser.has_errors(resource) == false
    end

    test "returns true for invalid syntax" do
      {:ok, resource} = BashParser.new_parser()

      # Invalid syntax
      {:ok, _ast} = BashParser.parse_incremental(resource, "if then fi\n")

      assert BashParser.has_errors(resource) == true
    end

    test "returns false when no tree exists" do
      {:ok, resource} = BashParser.new_parser()

      assert BashParser.has_errors(resource) == false
    end
  end

  describe "get_buffer_size/1" do
    test "returns size of accumulated input" do
      {:ok, resource} = BashParser.new_parser()

      # Initially empty
      assert BashParser.get_buffer_size(resource) == 0

      # After parsing
      fragment = "echo 'hello'\n"
      {:ok, _ast} = BashParser.parse_incremental(resource, fragment)

      assert BashParser.get_buffer_size(resource) == byte_size(fragment)
    end

    test "accumulates size across fragments" do
      {:ok, resource} = BashParser.new_parser()

      frag1 = "echo 'first'\n"
      frag2 = "echo 'second'\n"

      {:ok, _} = BashParser.parse_incremental(resource, frag1)
      size1 = BashParser.get_buffer_size(resource)
      assert size1 == byte_size(frag1)

      {:ok, _} = BashParser.parse_incremental(resource, frag2)
      size2 = BashParser.get_buffer_size(resource)
      assert size2 == byte_size(frag1) + byte_size(frag2)
    end
  end

  describe "get_accumulated_input/1" do
    test "returns accumulated script content" do
      {:ok, resource} = BashParser.new_parser()

      frag1 = "echo 'first'\n"
      frag2 = "echo 'second'\n"

      {:ok, _} = BashParser.parse_incremental(resource, frag1)
      {:ok, _} = BashParser.parse_incremental(resource, frag2)

      input = BashParser.get_accumulated_input(resource)
      assert input == frag1 <> frag2
    end
  end

  describe "memory management" do
    test "resource is cleaned up when process exits" do
      # This is a safety test - Rust ResourceArc should handle cleanup
      parent = self()

      ref = make_ref()

      spawn(fn ->
        {:ok, resource} = BashParser.new_parser()
        {:ok, _} = BashParser.parse_incremental(resource, "echo 'test'\n")
        send(parent, {:done, ref})
      end)

      assert_receive {:done, ^ref}, 1000

      # Process exited, resource should be cleaned up automatically
      # No way to verify directly, but this shouldn't leak memory
    end
  end

  describe "backward compatibility" do
    test "parse_bash/1 still works" do
      script = "echo 'hello'"

      assert {:ok, ast} = BashParser.parse_bash(script)
      assert ast["type"] == "program"
    end

    test "parse_bash/1 handles errors" do
      # Invalid syntax
      result = BashParser.parse_bash("if then fi")

      # Should return error (tree has errors)
      assert {:error, _} = result
    end
  end
end
