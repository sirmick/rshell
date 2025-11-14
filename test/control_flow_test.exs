defmodule RShell.ControlFlowTest do
  use ExUnit.Case, async: false

  # Control flow execution is still under development
  # Tests disabled until implementation is complete
  @moduletag :skip

  alias RShell.{Runtime, PubSub, IncrementalParser}
  alias BashParser.AST.Types

  setup do
    session_id = "control_flow_test_#{:rand.uniform(1000000)}"

    {:ok, parser} = IncrementalParser.start_link(session_id: session_id)
    {:ok, runtime} = Runtime.start_link(
      session_id: session_id,
      auto_execute: true
    )

    # Subscribe only to runtime events to avoid receiving executable_node messages
    PubSub.subscribe(session_id, [:runtime])

    on_exit(fn ->
      if Process.alive?(parser), do: GenServer.stop(parser)
      if Process.alive?(runtime), do: GenServer.stop(runtime)
    end)

    {:ok, parser: parser, runtime: runtime, session_id: session_id}
  end

  describe "if statement execution" do
    test "executes then-branch when condition is true", %{parser: parser, runtime: runtime} do
      # Simple if-then with true condition
      script = """
      if true; then
        echo "condition was true"
      fi
      """

      IncrementalParser.append_fragment(parser, script)

      # Wait for execution results
      assert_receive {:execution_result, %{status: :success, stdout: output}}, 1000
      assert output =~ "condition was true"

      # Verify exit code is from echo (0)
      context = Runtime.get_context(runtime)
      assert context.exit_code == 0
    end

    test "skips then-branch when condition is false", %{parser: parser, runtime: runtime} do
      # If-then with false condition - should not execute echo
      script = """
      if false; then
        echo "should not print"
      fi
      """

      IncrementalParser.append_fragment(parser, script)

      # Will get execution results but no stdout output
      assert_receive {:execution_result, result}, 1000
      assert result.stdout == ""

      # Exit code should be from the false command (non-zero)
      context = Runtime.get_context(runtime)
      assert context.exit_code != 0
    end

    test "executes else-branch when condition is false", %{parser: parser, runtime: runtime} do
      script = """
      if false; then
        echo "then branch"
      else
        echo "else branch"
      fi
      """

      IncrementalParser.append_fragment(parser, script)

      assert_receive {:execution_result, %{status: :success, stdout: output}}, 1000
      assert output =~ "else branch"
      refute output =~ "then branch"
    end

    test "handles if-elif-else chain", %{parser: parser, runtime: runtime} do
      # Test elif branch
      script = """
      if false; then
        echo "first"
      elif true; then
        echo "second"
      else
        echo "third"
      fi
      """

      IncrementalParser.append_fragment(parser, script)

      assert_receive {:execution_result, %{status: :success, stdout: output}}, 1000
      assert output =~ "second"
      refute output =~ "first"
      refute output =~ "third"
    end

    test "handles nested if statements", %{parser: parser, runtime: runtime} do
      script = """
      if true; then
        if true; then
          echo "nested"
        fi
      fi
      """

      IncrementalParser.append_fragment(parser, script)

      assert_receive {:execution_result, %{status: :success, stdout: output}}, 1000
      assert output =~ "nested"
    end

    test "uses last command exit code in condition", %{parser: parser, runtime: runtime} do
      # Multiple commands in condition - last one determines result
      script = """
      if true; false; then
        echo "should not print"
      else
        echo "last was false"
      fi
      """

      IncrementalParser.append_fragment(parser, script)

      assert_receive {:execution_result, %{status: :success, stdout: output}}, 1000
      assert output =~ "last was false"
    end
  end

  describe "for statement execution" do
    test "iterates over explicit values", %{parser: parser, runtime: runtime} do
      script = """
      for i in one two three; do
        echo $i
      done
      """

      IncrementalParser.append_fragment(parser, script)

      # Should receive three execution results
      assert_receive {:execution_result, %{status: :success, stdout: output1}}, 1000
      assert_receive {:execution_result, %{status: :success, stdout: output2}}, 1000
      assert_receive {:execution_result, %{status: :success, stdout: output3}}, 1000

      outputs = [output1, output2, output3] |> Enum.map(&String.trim/1)
      assert "one" in outputs
      assert "two" in outputs
      assert "three" in outputs
    end

    test "handles empty iteration list", %{parser: parser, runtime: runtime} do
      script = """
      for i in; do
        echo "should not print"
      done
      """

      IncrementalParser.append_fragment(parser, script)

      # For loop completes with no iterations - gets one result for the for statement
      assert_receive {:execution_result, _}, 1000
      # No additional echo results
      refute_receive {:execution_result, _}, 500
    end

    test "expands variables in iteration values", %{parser: parser, runtime: runtime} do
      # First set a variable, then use it in for loop
      script = """
      env ITEMS="a b c"
      for item in $ITEMS; do
        echo $item
      done
      """

      IncrementalParser.append_fragment(parser, script)

      # Get env result first, then 3 echo results
      assert_receive {:execution_result, %{status: :success}}, 1000  # env command
      assert_receive {:execution_result, %{status: :success, stdout: output1}}, 1000
      assert_receive {:execution_result, %{status: :success, stdout: output2}}, 1000
      assert_receive {:execution_result, %{status: :success, stdout: output3}}, 1000

      outputs = [output1, output2, output3] |> Enum.map(&String.trim/1)
      assert "a" in outputs
      assert "b" in outputs
      assert "c" in outputs
    end

    test "loop variable persists after loop", %{parser: parser, runtime: runtime} do
      script = """
      for x in final; do
        echo "in loop: $x"
      done
      echo "after loop: $x"
      """

      IncrementalParser.append_fragment(parser, script)

      assert_receive {:execution_result, %{status: :success, stdout: in_loop}}, 1000
      assert_receive {:execution_result, %{status: :success, stdout: after_loop}}, 1000

      assert in_loop =~ "in loop: final"
      assert after_loop =~ "after loop: final"
    end

    test "nested for loops", %{parser: parser, runtime: runtime} do
      script = """
      for i in 1 2; do
        for j in a b; do
          echo "$i$j"
        done
      done
      """

      IncrementalParser.append_fragment(parser, script)

      # Should get 4 execution results (2x2)
      outputs = for _ <- 1..4 do
        assert_receive {:execution_result, %{status: :success, stdout: output}}, 1000
        String.trim(output)
      end

      assert "1a" in outputs
      assert "1b" in outputs
      assert "2a" in outputs
      assert "2b" in outputs
    end
  end

  describe "while statement execution" do
    test "executes body while condition is true", %{parser: parser, runtime: runtime} do
      # Use a counter to limit iterations
      script = """
      env COUNT=0
      while test $COUNT -lt 3; do
        echo "iteration $COUNT"
        env COUNT=$((COUNT + 1))
      done
      """

      IncrementalParser.append_fragment(parser, script)

      # Collect all results - includes env commands
      all_results = for _ <- 1..20 do
        receive do
          {:execution_result, result} -> result
        after
          100 -> nil
        end
      end |> Enum.reject(&is_nil/1)

      # Filter to echo outputs
      echo_results = all_results |> Enum.filter(fn r -> r.stdout != "" and r.stdout =~ "iteration" end)

      # Should have 3 iterations
      assert length(echo_results) == 3
    end

    test "does not execute body when condition is initially false", %{parser: parser, runtime: runtime} do
      script = """
      while false; do
        echo "should not print"
      done
      """

      IncrementalParser.append_fragment(parser, script)

      # Gets result but no stdout
      assert_receive {:execution_result, result}, 1000
      # No echo output - collect remaining and check none have stdout
      remaining = for _ <- 1..5 do
        receive do
          {:execution_result, r} -> r
        after
          100 -> nil
        end
      end |> Enum.reject(&is_nil/1)

      # All remaining should have empty stdout
      assert Enum.all?(remaining, fn r -> r.stdout == "" end)
    end

    test "exits loop when condition becomes false", %{parser: parser, runtime: runtime} do
      script = """
      env CONTINUE=true
      while $CONTINUE; do
        echo "running"
        env CONTINUE=false
      done
      echo "after loop"
      """

      IncrementalParser.append_fragment(parser, script)

      # Collect all results
      all_results = for _ <- 1..10 do
        receive do
          {:execution_result, result} -> result
        after
          100 -> nil
        end
      end |> Enum.reject(&is_nil/1)

      # Filter to outputs with text
      text_outputs = all_results |> Enum.filter(fn r -> r.stdout != "" end)

      # Should have 2 text outputs
      assert length(text_outputs) == 2
      assert Enum.any?(text_outputs, fn r -> r.stdout =~ "running" end)
      assert Enum.any?(text_outputs, fn r -> r.stdout =~ "after loop" end)
    end

    test "nested while loops", %{parser: parser, runtime: runtime} do
      script = """
      env OUTER=0
      while test $OUTER -lt 2; do
        env INNER=0
        while test $INNER -lt 2; do
          echo "$OUTER-$INNER"
          env INNER=$((INNER + 1))
        done
        env OUTER=$((OUTER + 1))
      done
      """

      IncrementalParser.append_fragment(parser, script)

      # Collect many results (nested loops + env commands)
      all_results = for _ <- 1..30 do
        receive do
          {:execution_result, result} -> result
        after
          100 -> nil
        end
      end |> Enum.reject(&is_nil/1)

      # Filter to echo outputs
      echo_outputs = all_results
        |> Enum.filter(fn r -> r.stdout != "" end)
        |> Enum.map(fn r -> String.trim(r.stdout) end)

      # Should get 4 outputs (2x2)
      assert length(echo_outputs) == 4
      assert "0-0" in echo_outputs
      assert "0-1" in echo_outputs
      assert "1-0" in echo_outputs
      assert "1-1" in echo_outputs
    end
  end

  describe "mixed control flow" do
    test "if inside for loop", %{parser: parser, runtime: runtime} do
      script = """
      for n in 1 2 3; do
        if test $n -eq 2; then
          echo "found two"
        fi
      done
      """

      IncrementalParser.append_fragment(parser, script)

      # Collect results
      all_results = for _ <- 1..10 do
        receive do
          {:execution_result, result} -> result
        after
          100 -> nil
        end
      end |> Enum.reject(&is_nil/1)

      # Filter to echo outputs
      echo_results = all_results |> Enum.filter(fn r -> r.stdout != "" end)

      # Should only print once
      assert length(echo_results) == 1
      assert hd(echo_results).stdout =~ "found two"
    end

    test "for inside if statement", %{parser: parser, runtime: runtime} do
      script = """
      if true; then
        for i in 1 2; do
          echo $i
        done
      fi
      """

      IncrementalParser.append_fragment(parser, script)

      assert_receive {:execution_result, %{status: :success, stdout: output1}}, 1000
      assert_receive {:execution_result, %{status: :success, stdout: output2}}, 1000

      outputs = [output1, output2] |> Enum.map(&String.trim/1)
      assert "1" in outputs
      assert "2" in outputs
    end

    test "while inside if statement", %{parser: parser, runtime: runtime} do
      script = """
      env CHECK=true
      if $CHECK; then
        env COUNT=0
        while test $COUNT -lt 2; do
          echo $COUNT
          env COUNT=$((COUNT + 1))
        done
      fi
      """

      IncrementalParser.append_fragment(parser, script)

      # Collect all results (includes env commands)
      all_results = for _ <- 1..20 do
        receive do
          {:execution_result, result} -> result
        after
          100 -> nil
        end
      end |> Enum.reject(&is_nil/1)

      # Filter to echo outputs
      echo_outputs = all_results
        |> Enum.filter(fn r -> r.stdout != "" end)
        |> Enum.map(fn r -> String.trim(r.stdout) end)

      # Should have 2 echo outputs
      assert length(echo_outputs) == 2
      assert "0" in echo_outputs
      assert "1" in echo_outputs
    end
  end
end
