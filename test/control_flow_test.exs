defmodule RShell.ControlFlowTest do
  use ExUnit.Case, async: false

  alias RShell.{Runtime, PubSub, IncrementalParser}
  alias BashParser.AST.Types

  setup do
    session_id = "control_flow_test_#{:rand.uniform(1000000)}"

    {:ok, parser} = IncrementalParser.start_link(session_id: session_id)
    {:ok, runtime} = Runtime.start_link(
      session_id: session_id,
      auto_execute: true
    )

    PubSub.subscribe(session_id, :all)

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

      # Wait for execution to complete
      assert_receive {:stdout, output}, 1000
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

      # Give it time to potentially execute (but shouldn't)
      refute_receive {:stdout, _}, 500

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

      assert_receive {:stdout, output}, 1000
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

      assert_receive {:stdout, output}, 1000
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

      assert_receive {:stdout, output}, 1000
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

      assert_receive {:stdout, output}, 1000
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

      # Should receive three outputs
      assert_receive {:stdout, output1}, 1000
      assert_receive {:stdout, output2}, 1000
      assert_receive {:stdout, output3}, 1000

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

      # Should not execute body
      refute_receive {:stdout, _}, 500
    end

    test "expands variables in iteration values", %{parser: parser, runtime: runtime} do
      # First set a variable, then use it in for loop
      script = """
      export ITEMS="a b c"
      for item in $ITEMS; do
        echo $item
      done
      """

      IncrementalParser.append_fragment(parser, script)

      # Should iterate over expanded values
      assert_receive {:stdout, output1}, 1000
      assert_receive {:stdout, output2}, 1000
      assert_receive {:stdout, output3}, 1000

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

      assert_receive {:stdout, in_loop}, 1000
      assert_receive {:stdout, after_loop}, 1000

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

      # Should get 4 outputs (2x2)
      outputs = for _ <- 1..4 do
        assert_receive {:stdout, output}, 1000
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
      export COUNT=0
      while test $COUNT -lt 3; do
        echo "iteration $COUNT"
        export COUNT=$((COUNT + 1))
      done
      """

      IncrementalParser.append_fragment(parser, script)

      # Should iterate 3 times
      assert_receive {:stdout, output1}, 1000
      assert_receive {:stdout, output2}, 1000
      assert_receive {:stdout, output3}, 1000

      # Should not iterate more
      refute_receive {:stdout, _}, 500
    end

    test "does not execute body when condition is initially false", %{parser: parser, runtime: runtime} do
      script = """
      while false; do
        echo "should not print"
      done
      """

      IncrementalParser.append_fragment(parser, script)

      refute_receive {:stdout, _}, 500
    end

    test "exits loop when condition becomes false", %{parser: parser, runtime: runtime} do
      script = """
      export CONTINUE=true
      while $CONTINUE; do
        echo "running"
        export CONTINUE=false
      done
      echo "after loop"
      """

      IncrementalParser.append_fragment(parser, script)

      assert_receive {:stdout, running}, 1000
      assert running =~ "running"

      assert_receive {:stdout, after_output}, 1000
      assert after_output =~ "after loop"

      # Should only run once
      refute_receive {:stdout, _msg}, 500
    end

    test "nested while loops", %{parser: parser, runtime: runtime} do
      script = """
      export OUTER=0
      while test $OUTER -lt 2; do
        export INNER=0
        while test $INNER -lt 2; do
          echo "$OUTER-$INNER"
          export INNER=$((INNER + 1))
        done
        export OUTER=$((OUTER + 1))
      done
      """

      IncrementalParser.append_fragment(parser, script)

      # Should get 4 outputs (2x2)
      outputs = for _ <- 1..4 do
        assert_receive {:stdout, output}, 1000
        String.trim(output)
      end

      assert "0-0" in outputs
      assert "0-1" in outputs
      assert "1-0" in outputs
      assert "1-1" in outputs
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

      assert_receive {:stdout, output}, 1000
      assert output =~ "found two"

      # Should only print once (for n=2)
      refute_receive {:stdout, _}, 500
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

      assert_receive {:stdout, output1}, 1000
      assert_receive {:stdout, output2}, 1000

      outputs = [output1, output2] |> Enum.map(&String.trim/1)
      assert "1" in outputs
      assert "2" in outputs
    end

    test "while inside if statement", %{parser: parser, runtime: runtime} do
      script = """
      export CHECK=true
      if $CHECK; then
        export COUNT=0
        while test $COUNT -lt 2; do
          echo $COUNT
          export COUNT=$((COUNT + 1))
        done
      fi
      """

      IncrementalParser.append_fragment(parser, script)

      assert_receive {:stdout, output1}, 1000
      assert_receive {:stdout, output2}, 1000

      outputs = [output1, output2] |> Enum.map(&String.trim/1)
      assert "0" in outputs
      assert "1" in outputs
    end
  end
end
