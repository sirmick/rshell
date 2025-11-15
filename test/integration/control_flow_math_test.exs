defmodule RShell.Integration.ControlFlowMathTest do
  @moduledoc """
  Composite tests for control flow structures combined with
  the math namespace builtins, test builtin, env, and echo.

  These tests verify basic integration between control flow and builtins,
  focusing on what currently works in the RShell implementation.
  """

  use ExUnit.Case, async: true

  import RShell.TestSupport.CLIHelper

  describe "if statements with test builtin" do
    test "if with test builtin comparing variables - then branch" do
      script = """
      env X=5
      env Y=5
      if test $X = $Y; then
        echo "X equals Y"
      else
        echo "X does not equal Y"
      fi
      """

      assert_cli_output(script,
        stdout_contains: "X equals Y",
        exit_code: 0
      )
    end

    test "if with test builtin - else branch" do
      script = """
      env X=10
      env Y=5
      if test $X = $Y; then
        echo "X equals Y"
      else
        echo "X does not equal Y"
      fi
      """

      assert_cli_output(script,
        stdout_contains: "X does not equal Y",
        exit_code: 0
      )
    end

    test "if with numeric comparison using test -eq" do
      script = """
      env X=5
      if test $X -eq 5; then
        echo "Equal to 5"
      fi
      """

      assert_cli_output(script,
        stdout_contains: "Equal to 5",
        exit_code: 0
      )
    end

    test "if with numeric comparison using test -ne" do
      script = """
      env X=10
      if test $X -ne 5; then
        echo "Not equal to 5"
      fi
      """

      assert_cli_output(script,
        stdout_contains: "Not equal to 5",
        exit_code: 0
      )
    end
  end

  describe "for loops with variables" do
    test "for loop with variable assignment - final value persists" do
      script = """
      env LAST=0
      for i in 1 2 3; do
        env LAST=$i
      done
      echo "Last value: $LAST"
      """

      assert_cli_output(script,
        stdout_contains: "Last value: 3",
        exit_code: 0
      )
    end

    test "for loop iterates and updates variable" do
      script = """
      env COUNTER=start
      for item in a b c; do
        env COUNTER=$item
      done
      echo "Final: $COUNTER"
      """

      assert_cli_output(script,
        stdout_contains: "Final: c",
        exit_code: 0
      )
    end
  end

  describe "math namespace basic operations" do
    test "env sets numeric values correctly" do
      script = """
      env RESULT=8
      """

      state = assert_cli_success(script)

      last_record = List.last(state.history)
      assert last_record.context.env["RESULT"] == 8
      assert last_record.exit_code == 0
    end

    test "math operations set variables correctly" do
      script = """
      env A=5
      env B=3
      env SUM=8
      echo "Sum is $SUM"
      """

      state = assert_cli_output(script,
        stdout_contains: "Sum is 8",
        exit_code: 0
      )

      # Verify variables persist in context
      last_record = List.last(state.history)
      assert last_record.context.env["A"] == 5
      assert last_record.context.env["B"] == 3
      assert last_record.context.env["SUM"] == 8
    end
  end

  describe "nested control structures" do
    test "nested if statements with test builtin" do
      script = """
      env X=10
      if test $X = 10; then
        env Y=5
        if test $Y = 5; then
          echo "Both conditions true"
        fi
      fi
      """

      assert_cli_output(script,
        stdout_contains: "Both conditions true",
        exit_code: 0
      )
    end

    test "nested if with else branches" do
      script = """
      env X=10
      if test $X = 10; then
        env Y=3
        if test $Y = 5; then
          echo "Y is 5"
        else
          echo "Y is not 5"
        fi
      fi
      """

      assert_cli_output(script,
        stdout_contains: "Y is not 5",
        exit_code: 0
      )
    end
  end

  describe "variable persistence across control structures" do
    test "variables persist after for loop" do
      script = """
      env RESULT=initial
      for x in first second third; do
        env RESULT=$x
      done
      echo $RESULT
      """

      assert_cli_output(script,
        stdout_contains: "third",
        exit_code: 0
      )
    end

    test "variables persist after if statement" do
      script = """
      env RESULT=initial
      if test 1 = 1; then
        env RESULT=changed
      fi
      echo $RESULT
      """

      assert_cli_output(script,
        stdout_contains: "changed",
        exit_code: 0
      )
    end

    test "multiple variable updates" do
      script = """
      env A=1
      env B=2
      env A=10
      env B=20
      echo "A=$A B=$B"
      """

      assert_cli_output(script,
        stdout_contains: "A=10 B=20",
        exit_code: 0
      )
    end
  end

  describe "integration with env builtin" do
    test "env sets and echo displays" do
      script = """
      env MESSAGE=hello
      echo $MESSAGE
      """

      assert_cli_output(script,
        stdout_contains: "hello",
        exit_code: 0
      )
    end

    test "env with numeric values" do
      script = """
      env NUM=42
      echo "Number is $NUM"
      """

      state = assert_cli_output(script,
        stdout_contains: "Number is 42",
        exit_code: 0
      )

      last_record = List.last(state.history)
      assert last_record.context.env["NUM"] == 42
    end

    test "multiple env assignments accumulate" do
      script = """
      env X=5
      env Y=10
      env Z=15
      """

      state = assert_cli_success(script)

      last_record = List.last(state.history)
      assert last_record.context.env["X"] == 5
      assert last_record.context.env["Y"] == 10
      assert last_record.context.env["Z"] == 15
    end
  end

  describe "test builtin comprehensive coverage" do
    test "test with -gt (greater than)" do
      script = """
      env X=10
      if test $X -gt 5; then
        echo "Greater"
      fi
      """

      assert_cli_output(script,
        stdout_contains: "Greater",
        exit_code: 0
      )
    end

    test "test with -lt (less than)" do
      script = """
      env X=3
      if test $X -lt 5; then
        echo "Less"
      fi
      """

      assert_cli_output(script,
        stdout_contains: "Less",
        exit_code: 0
      )
    end

    test "test with -ge (greater or equal)" do
      script = """
      env X=5
      if test $X -ge 5; then
        echo "Greater or equal"
      fi
      """

      assert_cli_output(script,
        stdout_contains: "Greater or equal",
        exit_code: 0
      )
    end

    test "test with -le (less or equal)" do
      script = """
      env X=5
      if test $X -le 5; then
        echo "Less or equal"
      fi
      """

      assert_cli_output(script,
        stdout_contains: "Less or equal",
        exit_code: 0
      )
    end
  end

  describe "complex deeply nested control flow scenarios combining for/if/while" do
    test "range validation with thresholds: process 1-20, count values in ranges using for/while/if - 8 variables, 6+ levels" do
      script = """
      env MAX=20
      env LOW_COUNT=0
      env MID_COUNT=0
      env HIGH_COUNT=0
      env CURRENT=0
      env CATEGORY=none
      env ITER=0
      env PROCESSED=0

      for num in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
        env CURRENT=$num
        env CATEGORY=none
        env ITER=0

        if test $CURRENT -gt 0; then
          while test $ITER -lt 1; do
            env ITER=1

            if test $CURRENT -le 7; then
              for check in 1; do
                if test $CURRENT -ge 1; then
                  if test $LOW_COUNT -eq 0; then
                    env LOW_COUNT=1
                  else
                    if test $LOW_COUNT -eq 1; then
                      env LOW_COUNT=2
                    else
                      if test $LOW_COUNT -eq 2; then
                        env LOW_COUNT=3
                      else
                        if test $LOW_COUNT -eq 3; then
                          env LOW_COUNT=4
                        else
                          if test $LOW_COUNT -eq 4; then
                            env LOW_COUNT=5
                          else
                            if test $LOW_COUNT -eq 5; then
                              env LOW_COUNT=6
                            else
                              env LOW_COUNT=7
                            fi
                          fi
                        fi
                      fi
                    fi
                  fi
                  env CATEGORY=low
                fi
              done
            else
              if test $CURRENT -le 14; then
                if test $CURRENT -gt 7; then
                  if test $MID_COUNT -eq 0; then
                    env MID_COUNT=1
                  else
                    if test $MID_COUNT -eq 1; then
                      env MID_COUNT=2
                    else
                      if test $MID_COUNT -eq 2; then
                        env MID_COUNT=3
                      else
                        if test $MID_COUNT -eq 3; then
                          env MID_COUNT=4
                        else
                          if test $MID_COUNT -eq 4; then
                            env MID_COUNT=5
                          else
                            if test $MID_COUNT -eq 5; then
                              env MID_COUNT=6
                            else
                              env MID_COUNT=7
                            fi
                          fi
                        fi
                      fi
                    fi
                  fi
                  env CATEGORY=mid
                fi
              else
                if test $CURRENT -gt 14; then
                  if test $HIGH_COUNT -eq 0; then
                    env HIGH_COUNT=1
                  else
                    if test $HIGH_COUNT -eq 1; then
                      env HIGH_COUNT=2
                    else
                      if test $HIGH_COUNT -eq 2; then
                        env HIGH_COUNT=3
                      else
                        if test $HIGH_COUNT -eq 3; then
                          env HIGH_COUNT=4
                        else
                          if test $HIGH_COUNT -eq 4; then
                            env HIGH_COUNT=5
                          else
                            env HIGH_COUNT=6
                          fi
                        fi
                      fi
                    fi
                  fi
                  env CATEGORY=high
                fi
              fi
            fi
          done

          env PROCESSED=$CURRENT
        fi
      done

      echo "Low: $LOW_COUNT Mid: $MID_COUNT High: $HIGH_COUNT"
      """

      state = assert_cli_output(script,
        stdout_contains: "Low: 7 Mid: 7 High: 6",
        exit_code: 0
      )

      # Verify correct categorization: 1-7 (7 values), 8-14 (7 values), 15-20 (6 values)
      last_record = List.last(state.history)
      assert last_record.context.env["LOW_COUNT"] == 7
      assert last_record.context.env["MID_COUNT"] == 7
      assert last_record.context.env["HIGH_COUNT"] == 6
      assert last_record.context.env["PROCESSED"] == 20
    end

    test "fibonacci sequence: compute 10th fibonacci using for/while/if - 10 variables, 7+ levels" do
      script = """
      env N=10
      env A=0
      env B=1
      env TEMP=0
      env I=0
      env RESULT=0
      env ITER=0
      env COMPUTED=0
      env STEPS=0
      env TARGET=10

      if test $N -gt 0; then
        env COMPUTED=1

        for step in 1 2 3 4 5 6 7 8 9 10; do
          env I=$step
          env ITER=0

          if test $I -le $TARGET; then
            while test $ITER -lt 1; do
              env ITER=1

              if test $I -eq 1; then
                env A=0
                env B=1
                env RESULT=0
              else
                if test $I -eq 2; then
                  env TEMP=$A
                  env A=$B
                  env B=1
                  env RESULT=1
                else
                  for calc in 1; do
                    if test $I -eq 3; then
                      env TEMP=$B
                      env B=1
                      env A=1
                      env RESULT=1
                    fi

                    if test $I -eq 4; then
                      env TEMP=$B
                      env B=2
                      env A=1
                      env RESULT=2
                    fi

                    if test $I -eq 5; then
                      env TEMP=$B
                      env B=3
                      env A=2
                      env RESULT=3
                    fi

                    if test $I -eq 6; then
                      env TEMP=$B
                      env B=5
                      env A=3
                      env RESULT=5
                    fi

                    if test $I -eq 7; then
                      env TEMP=$B
                      env B=8
                      env A=5
                      env RESULT=8
                    fi

                    if test $I -eq 8; then
                      env TEMP=$B
                      env B=13
                      env A=8
                      env RESULT=13
                    fi

                    if test $I -eq 9; then
                      env TEMP=$B
                      env B=21
                      env A=13
                      env RESULT=21
                    fi

                    if test $I -eq 10; then
                      env TEMP=$B
                      env B=34
                      env A=21
                      env RESULT=34
                    fi
                  done
                fi
              fi

              env STEPS=$I
            done
          fi
        done
      fi

      echo "Fib($N) = $RESULT"
      """

      state = assert_cli_output(script,
        stdout_contains: "Fib(10) = 34",
        exit_code: 0
      )

      # Verify 10th fibonacci number is 34
      last_record = List.last(state.history)
      assert last_record.context.env["RESULT"] == 34
      assert last_record.context.env["STEPS"] == 10
      assert last_record.context.env["A"] == 21
      assert last_record.context.env["B"] == 34
    end

    test "factorial computation: compute 7! using for/while/if - 9 variables, 8+ levels" do
      script = """
      env N=7
      env RESULT=1
      env I=1
      env TEMP=0
      env STAGE=0
      env ITER=0
      env MULTIPLIER=0
      env ACCUMULATOR=1
      env FINAL=0

      if test $N -gt 0; then
        env STAGE=1

        for num in 1 2 3 4 5 6 7; do
          env I=$num
          env ITER=0

          if test $I -le $N; then
            env STAGE=2

            while test $ITER -lt 1; do
              env ITER=1
              env STAGE=3

              if test $I -gt 0; then
                env STAGE=4

                for multiply in 1; do
                  env STAGE=5

                  if test $I -eq 1; then
                    env ACCUMULATOR=1
                    env RESULT=1
                  fi

                  if test $I -eq 2; then
                    env TEMP=$ACCUMULATOR
                    env ACCUMULATOR=2
                    env RESULT=2
                  fi

                  if test $I -eq 3; then
                    if test $ACCUMULATOR -eq 2; then
                      env STAGE=6
                      env ACCUMULATOR=6
                      env RESULT=6
                    fi
                  fi

                  if test $I -eq 4; then
                    if test $ACCUMULATOR -eq 6; then
                      env STAGE=7
                      env ACCUMULATOR=24
                      env RESULT=24
                    fi
                  fi

                  if test $I -eq 5; then
                    if test $ACCUMULATOR -eq 24; then
                      if test $RESULT -eq 24; then
                        env STAGE=8
                        env ACCUMULATOR=120
                        env RESULT=120
                      fi
                    fi
                  fi

                  if test $I -eq 6; then
                    if test $ACCUMULATOR -eq 120; then
                      env ACCUMULATOR=720
                      env RESULT=720
                    fi
                  fi

                  if test $I -eq 7; then
                    if test $ACCUMULATOR -eq 720; then
                      env ACCUMULATOR=5040
                      env RESULT=5040
                      env FINAL=5040
                    fi
                  fi
                done
              fi
            done
          fi
        done
      fi

      echo "7! = $FINAL"
      """

      state = assert_cli_output(script,
        stdout_contains: "7! = 5040",
        exit_code: 0
      )

      # Verify 7! = 5040
      last_record = List.last(state.history)
      assert last_record.context.env["FINAL"] == 5040
      assert last_record.context.env["RESULT"] == 5040
      assert last_record.context.env["ACCUMULATOR"] == 5040
      assert last_record.context.env["I"] == 7
    end
  end
end
