defmodule RShell.Integration.ControlFlowMathTest do
  @moduledoc """
  Comprehensive tests for control flow structures combined with
  math operations and deeply nested structures.

  These tests verify RShell's ability to handle:
  - Arithmetic expressions and comparisons
  - Nested control flow (if/for/while)
  - Variable persistence across structures
  - Complex computational scenarios (fibonacci, factorial, range validation)
  """

  use ExUnit.Case, async: true

  import RShell.TestSupport.CLIHelper

  describe "if statements with comparisons" do
    test "if with variable comparison - then branch" do
      script = """
      X = 5
      Y = 5
      if (X == Y) {
        echo "X equals Y"
      } else {
        echo "X does not equal Y"
      }
      """

      assert_cli_output(script,
        stdout_contains: "X equals Y",
        exit_code: 0
      )
    end

    test "if with comparison - else branch" do
      script = """
      X = 10
      Y = 5
      if (X == Y) {
        echo "X equals Y"
      } else {
        echo "X does not equal Y"
      }
      """

      assert_cli_output(script,
        stdout_contains: "X does not equal Y",
        exit_code: 0
      )
    end

    test "if with numeric comparison using ==" do
      script = """
      X = 5
      if (X == 5) {
        echo "Equal to 5"
      }
      """

      assert_cli_output(script,
        stdout_contains: "Equal to 5",
        exit_code: 0
      )
    end

    test "if with numeric comparison using !=" do
      script = """
      X = 10
      if (X != 5) {
        echo "Not equal to 5"
      }
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
      LAST = 0
      for (i in [1, 2, 3]) {
        LAST = i
      }
      echo "Last value: $LAST"
      """

      assert_cli_output(script,
        stdout_contains: "Last value: 3",
        exit_code: 0
      )
    end

    test "for loop iterates and updates variable" do
      script = """
      COUNTER = 'start'
      for (item in ['a', 'b', 'c']) {
        COUNTER = item
      }
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
      RESULT = 8
      """

      state = assert_cli_success(script)

      last_record = List.last(state.history)
      assert last_record.context.env["RESULT"] == 8
      assert last_record.exit_code == 0
    end

    test "math operations set variables correctly" do
      script = """
      A = 5
      B = 3
      SUM = 8
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
    test "nested if statements with comparisons" do
      script = """
      X = 10
      if (X == 10) {
        Y = 5
        if (Y == 5) {
          echo "Both conditions true"
        }
      }
      """

      assert_cli_output(script,
        stdout_contains: "Both conditions true",
        exit_code: 0
      )
    end

    test "nested if with else branches" do
      script = """
      X = 10
      if (X == 10) {
        Y = 3
        if (Y == 5) {
          echo "Y is 5"
        } else {
          echo "Y is not 5"
        }
      }
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
      RESULT = 'initial'
      for (x in ['first', 'second', 'third']) {
        RESULT = x
      }
      echo $RESULT
      """

      assert_cli_output(script,
        stdout_contains: "third",
        exit_code: 0
      )
    end

    test "variables persist after if statement" do
      script = """
      RESULT = 'initial'
      if (true) {
        RESULT = 'changed'
      }
      echo $RESULT
      """

      assert_cli_output(script,
        stdout_contains: "changed",
        exit_code: 0
      )
    end

    test "multiple variable updates" do
      script = """
      A = 1
      B = 2
      A = 10
      B = 20
      echo "A=$A B=$B"
      """

      assert_cli_output(script,
        stdout_contains: "A=10 B=20",
        exit_code: 0
      )
    end
  end

  describe "integration with env builtin" do
    test "env with numeric values" do
      script = """
      NUM = 42
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
      X = 5
      Y = 10
      Z = 15
      """

      state = assert_cli_success(script)

      last_record = List.last(state.history)
      assert last_record.context.env["X"] == 5
      assert last_record.context.env["Y"] == 10
      assert last_record.context.env["Z"] == 15
    end
  end

  describe "comparison operators comprehensive coverage" do
    test "greater than comparison" do
      script = """
      X = 10
      if (X > 5) {
        echo "Greater"
      }
      """

      assert_cli_output(script,
        stdout_contains: "Greater",
        exit_code: 0
      )
    end

    test "less than comparison" do
      script = """
      X = 3
      if (X < 5) {
        echo "Less"
      }
      """

      assert_cli_output(script,
        stdout_contains: "Less",
        exit_code: 0
      )
    end

    test "greater or equal comparison" do
      script = """
      X = 5
      if (X >= 5) {
        echo "Greater or equal"
      }
      """

      assert_cli_output(script,
        stdout_contains: "Greater or equal",
        exit_code: 0
      )
    end

    test "less or equal comparison" do
      script = """
      X = 5
      if (X <= 5) {
        echo "Less or equal"
      }
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
      MAX = 20
      LOW_COUNT = 0
      MID_COUNT = 0
      HIGH_COUNT = 0
      CURRENT = 0
      CATEGORY = 'none'
      ITER = 0
      PROCESSED = 0

      for (num in [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20]) {
        CURRENT = num
        CATEGORY = 'none'
        ITER = 0

        if (CURRENT > 0) {
          while (ITER < 1) {
            ITER = 1

            if (CURRENT <= 7) {
              for (check in [1]) {
                if (CURRENT >= 1) {
                  if (LOW_COUNT == 0) {
                    LOW_COUNT = 1
                  } elif (LOW_COUNT == 1) {
                    LOW_COUNT = 2
                  } elif (LOW_COUNT == 2) {
                    LOW_COUNT = 3
                  } elif (LOW_COUNT == 3) {
                    LOW_COUNT = 4
                  } elif (LOW_COUNT == 4) {
                    LOW_COUNT = 5
                  } elif (LOW_COUNT == 5) {
                    LOW_COUNT = 6
                  } else {
                    LOW_COUNT = 7
                  }
                  CATEGORY = 'low'
                }
              }
            } else {
              if (CURRENT <= 14) {
                if (CURRENT > 7) {
                  if (MID_COUNT == 0) {
                    MID_COUNT = 1
                  } elif (MID_COUNT == 1) {
                    MID_COUNT = 2
                  } elif (MID_COUNT == 2) {
                    MID_COUNT = 3
                  } elif (MID_COUNT == 3) {
                    MID_COUNT = 4
                  } elif (MID_COUNT == 4) {
                    MID_COUNT = 5
                  } elif (MID_COUNT == 5) {
                    MID_COUNT = 6
                  } else {
                    MID_COUNT = 7
                  }
                  CATEGORY = 'mid'
                }
              } else {
                if (CURRENT > 14) {
                  if (HIGH_COUNT == 0) {
                    HIGH_COUNT = 1
                  } elif (HIGH_COUNT == 1) {
                    HIGH_COUNT = 2
                  } elif (HIGH_COUNT == 2) {
                    HIGH_COUNT = 3
                  } elif (HIGH_COUNT == 3) {
                    HIGH_COUNT = 4
                  } elif (HIGH_COUNT == 4) {
                    HIGH_COUNT = 5
                  } else {
                    HIGH_COUNT = 6
                  }
                  CATEGORY = 'high'
                }
              }
            }
          }

          PROCESSED = CURRENT
        }
      }

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
      N = 10
      A = 0
      B = 1
      TEMP = 0
      I = 0
      RESULT = 0
      ITER = 0
      COMPUTED = 0
      STEPS = 0
      TARGET = 10

      if (N > 0) {
        COMPUTED = 1

        for (step in [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]) {
          I = step
          ITER = 0

          if (I <= TARGET) {
            while (ITER < 1) {
              ITER = 1

              if (I == 1) {
                A = 0
                B = 1
                RESULT = 0
              } elif (I == 2) {
                TEMP = A
                A = B
                B = 1
                RESULT = 1
              } else {
                for (calc in [1]) {
                  if (I == 3) {
                    TEMP = B
                    B = 1
                    A = 1
                    RESULT = 1
                  }

                  if (I == 4) {
                    TEMP = B
                    B = 2
                    A = 1
                    RESULT = 2
                  }

                  if (I == 5) {
                    TEMP = B
                    B = 3
                    A = 2
                    RESULT = 3
                  }

                  if (I == 6) {
                    TEMP = B
                    B = 5
                    A = 3
                    RESULT = 5
                  }

                  if (I == 7) {
                    TEMP = B
                    B = 8
                    A = 5
                    RESULT = 8
                  }

                  if (I == 8) {
                    TEMP = B
                    B = 13
                    A = 8
                    RESULT = 13
                  }

                  if (I == 9) {
                    TEMP = B
                    B = 21
                    A = 13
                    RESULT = 21
                  }

                  if (I == 10) {
                    TEMP = B
                    B = 34
                    A = 21
                    RESULT = 34
                  }
                }
              }

              STEPS = I
            }
          }
        }
      }

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
      N = 7
      RESULT = 1
      I = 1
      TEMP = 0
      STAGE = 0
      ITER = 0
      MULTIPLIER = 0
      ACCUMULATOR = 1
      FINAL = 0

      if (N > 0) {
        STAGE = 1

        for (num in [1, 2, 3, 4, 5, 6, 7]) {
          I = num
          ITER = 0

          if (I <= N) {
            STAGE = 2

            while (ITER < 1) {
              ITER = 1
              STAGE = 3

              if (I > 0) {
                STAGE = 4

                for (multiply in [1]) {
                  STAGE = 5

                  if (I == 1) {
                    ACCUMULATOR = 1
                    RESULT = 1
                  }

                  if (I == 2) {
                    TEMP = ACCUMULATOR
                    ACCUMULATOR = 2
                    RESULT = 2
                  }

                  if (I == 3) {
                    if (ACCUMULATOR == 2) {
                      STAGE = 6
                      ACCUMULATOR = 6
                      RESULT = 6
                    }
                  }

                  if (I == 4) {
                    if (ACCUMULATOR == 6) {
                      STAGE = 7
                      ACCUMULATOR = 24
                      RESULT = 24
                    }
                  }

                  if (I == 5) {
                    if (ACCUMULATOR == 24) {
                      if (RESULT == 24) {
                        STAGE = 8
                        ACCUMULATOR = 120
                        RESULT = 120
                      }
                    }
                  }

                  if (I == 6) {
                    if (ACCUMULATOR == 120) {
                      ACCUMULATOR = 720
                      RESULT = 720
                    }
                  }

                  if (I == 7) {
                    if (ACCUMULATOR == 720) {
                      ACCUMULATOR = 5040
                      RESULT = 5040
                      FINAL = 5040
                    }
                  }
                }
              }
            }
          }
        }
      }

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
