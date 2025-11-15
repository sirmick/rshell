# RShell Test Guide

A comprehensive guide to RShell's test organization and preferred testing patterns.

---

## Quick Reference

**Where to put tests:**
- **Unit tests** → [`test/unit/`](test/unit/) - One module, isolated functionality
- **Integration tests** → [`test/integration/`](test/integration/) - Multiple modules, end-to-end flows
- **Test helpers** → [`test/support/`](test/support/) - Reusable utilities

**How to write tests:**
- **Preferred**: Use [`CLIHelper`](test/support/cli_test_helper.ex:1) with [`execute_string/2`](lib/r_shell/cli.ex:1) or [`execute_lines/2`](lib/r_shell/cli.ex:1)
- **Pattern**: Silent success, verbose failure
- **Verification**: Check AST, execution results, stdout, context

---

## Test Organization

### Directory Structure

```
test/
├── test_helper.exs              # Global config (2s timeout)
├── unit/                        # Unit tests (7 files, 169 tests)
│   ├── input_buffer_test.exs
│   ├── error_classifier_test.exs
│   ├── pubsub_test.exs
│   ├── env_json_test.exs
│   └── builtins/
│       ├── helpers_test.exs
│       ├── doc_parser_test.exs
│       └── option_parser_test.exs
├── integration/                 # Integration tests (5 files, 74+ tests)
│   ├── cli_test.exs
│   ├── control_flow_test.exs
│   ├── incremental_parser_pubsub_test.exs
│   ├── parser_runtime_integration_test.exs
│   └── pubsub_guarantees_test.exs
├── support/                     # Test helpers (2 files)
│   └── cli_test_helper.ex       # ⭐ Main helper (use this!)
└── .deprecated/                 # Archived tests (reference only)
```

### When to Use Each Directory

#### Unit Tests ([`test/unit/`](test/unit/))

**Use for:** Testing a single module in isolation

**Examples:**
- [`InputBuffer.ready_to_parse?/1`](lib/r_shell/input_buffer.ex:1) - Does it detect continuations?
- [`ErrorClassifier.classify/1`](lib/r_shell/error_classifier.ex:1) - Does it distinguish errors from incomplete?
- [`PubSub.broadcast/3`](lib/r_shell/pubsub.ex:1) - Does it deliver messages?

**Characteristics:**
- Fast (no spawned processes unless necessary)
- Most run `async: true`
- Direct function calls
- Focused on single-module behavior

#### Integration Tests ([`test/integration/`](test/integration/))

**Use for:** Testing multiple modules working together (⭐ **PREFERRED FOR NEW TESTS**)

**Examples:**
- CLI executing if statements (Parser + Runtime + Executor)
- Variable assignment and expansion (Parser + Runtime + Context)
- PubSub event guarantees (Parser + Runtime + PubSub)

**Characteristics:**
- Tests full execution pipeline
- Uses [`CLIHelper`](test/support/cli_test_helper.ex:1)
- Verifies AST, execution results, and output
- Most run `async: true`

---

## Preferred Testing Pattern: CLI Helper

### Why Use CLIHelper?

✅ **Tests the full stack** - Parser → AST → Runtime → Execution  
✅ **Silent on success** - No noise when passing  
✅ **Verbose on failure** - Full diagnostics (AST, stdout, metrics, context)  
✅ **Timeout protection** - Prevents hanging tests (5s default)  
✅ **Simple API** - One function call for most tests

### Basic Usage

```elixir
defmodule RShell.Integration.MyFeatureTest do
  use ExUnit.Case, async: true
  import RShell.TestSupport.CLIHelper

  test "executes simple command" do
    # Silent success - returns state if successful
    state = assert_cli_success("echo hello\n")
    
    # Access execution records
    record = List.last(state.history)
    assert record.exit_code == 0
    assert record.stdout == ["hello\n"]
  end

  test "verifies specific output" do
    # With assertions - fails verbosely if not met
    assert_cli_output("echo test\n", [
      stdout_contains: "test",
      exit_code: 0,
      record_count: 1
    ])
  end
end
```

### Core Functions

#### [`assert_cli_success/2`](test/support/cli_test_helper.ex:23)

Execute script and assert it completes successfully.

```elixir
state = assert_cli_success(script, opts \\ [])
```

**Options:**
- `:mode` - `:execute_string` (default for single-line) or `:execute_lines` (auto-detected for multi-line)
- `:timeout` - Milliseconds (default: 5000)

**Returns:** CLI state with execution history

**On Success:** Silent (no output)

**On Failure:** Verbose diagnostic with:
- Script content
- Error reason or timeout info
- Full execution context

#### [`assert_cli_output/3`](test/support/cli_test_helper.ex:72)

Execute script and assert specific conditions.

```elixir
state = assert_cli_output(script, assertions, opts \\ [])
```

**Assertions:**
- `{:stdout_contains, pattern}` - Assert stdout contains string/regex
- `{:exit_code, code}` - Assert exit code matches
- `{:record_count, count}` - Assert number of execution records
- `{:variable, name, value}` - Assert environment variable value
- `{:no_timeout, true}` - Just verify completion

**Options:** Same as `assert_cli_success/2`

**On Failure:** Shows:
- Expected vs actual values
- Script content
- Full execution history with outputs
- Parse/exec metrics
- Environment variables

---

## Writing New Tests: Step-by-Step

### 1. Choose Test Type

**New feature or bug fix?** → Integration test (use CLIHelper)

**Testing a single utility function?** → Unit test (direct function call)

### 2. Create Test File

**Integration test example:**

```elixir
defmodule RShell.Integration.MyFeatureTest do
  use ExUnit.Case, async: true
  import RShell.TestSupport.CLIHelper

  describe "my feature" do
    test "basic behavior" do
      script = """
      # Your bash script here
      echo "test"
      """

      state = assert_cli_success(script)
      
      # Assertions on state
      record = List.last(state.history)
      assert record.exit_code == 0
    end
  end
end
```

### 3. Verify Multiple Aspects

The CLIHelper approach lets you verify:

#### **AST Structure**

```elixir
test "parses control structure correctly" do
  state = assert_cli_success("if true; then echo hi; fi\n")
  
  record = List.last(state.history)
  # Full AST from complete parse
  assert record.full_ast != nil
  # Incremental AST from parser
  assert record.incremental_ast != nil
end
```

#### **Execution Results**

```elixir
test "executes command successfully" do
  state = assert_cli_success("pwd\n")
  
  record = List.last(state.history)
  assert record.execution_result.status == :success
  assert record.execution_result.node_type == "Command"
end
```

#### **Output Streams**

```elixir
test "produces expected output" do
  assert_cli_output("echo hello\n", [
    stdout_contains: "hello"
  ])
end

test "produces no output" do
  state = assert_cli_success("true\n")
  
  record = List.last(state.history)
  assert record.stdout == []
end
```

#### **Context Changes**

```elixir
test "sets environment variable" do
  state = assert_cli_success("X=5\n")
  
  record = List.last(state.history)
  assert record.context.env["X"] == 5
end

test "changes working directory" do
  state = assert_cli_success("cd /tmp\n")
  
  record = List.last(state.history)
  assert record.context.cwd =~ "/tmp"
end
```

#### **Metrics**

```elixir
test "tracks performance metrics" do
  state = assert_cli_success("echo test\n")
  
  record = List.last(state.history)
  assert record.parse_metrics.duration_us > 0
  assert record.exec_metrics.duration_us > 0
  assert is_integer(record.parse_metrics.memory_delta)
end
```

### 4. Test Multi-Line Scripts

```elixir
test "executes multi-line script" do
  script = """
  X=5
  if test $X = 5; then
    echo "X is 5"
  fi
  """

  state = assert_cli_output(script, [
    stdout_contains: "X is 5",
    exit_code: 0,
    record_count: 2  # env + if statement
  ])
end
```

**Mode auto-detection:** CLIHelper uses `:execute_lines` for multi-line scripts automatically.

### 5. Handle Edge Cases

```elixir
test "handles nested control structures" do
  script = """
  if true; then
    for i in 1 2; do
      echo "nested"
    done
  fi
  """

  state = assert_cli_success(script)
  
  # Verify we got outputs from for loop
  outputs = Enum.flat_map(state.history, & &1.stdout)
  assert Enum.count(outputs, &(&1 =~ "nested")) >= 1
end
```

---

## Test Pattern Examples

### Example 1: Simple Command

```elixir
test "basic echo command" do
  state = assert_cli_output("echo hello\n", [
    stdout_contains: "hello",
    exit_code: 0,
    record_count: 1
  ])

  record = List.last(state.history)
  assert record.fragment == "echo hello\n"
  assert is_struct(record, ExecutionRecord)
end
```

### Example 2: Variable Assignment

```elixir
test "variable assignment and expansion" do
  script = """
  X=5
  Y=10
  echo $X $Y
  """

  state = assert_cli_output(script, [
    stdout_contains: "5 10",
    record_count: 3
  ])

  # Verify variables persist
  last_context = List.last(state.history).context
  assert last_context.env["X"] == 5
  assert last_context.env["Y"] == 10
end
```

### Example 3: Control Flow

```elixir
test "if-else branches correctly" do
  script = """
  if false; then
    echo "then branch"
  else
    echo "else branch"
  fi
  """

  state = assert_cli_output(script, [
    stdout_contains: "else branch"
  ])

  # Verify "then branch" does NOT appear
  outputs = Enum.flat_map(state.history, & &1.stdout)
  refute Enum.any?(outputs, &(&1 =~ "then branch"))
end
```

### Example 4: Error Handling

```elixir
test "handles syntax errors gracefully" do
  # This should fail to parse, not crash
  # Note: Current behavior may vary, adjust based on actual implementation
  {:error, reason} = CLI.execute_string("if then fi\n")
  assert reason =~ "syntax"
end
```

### Example 5: State Accumulation

```elixir
test "accumulates state across executions" do
  {:ok, state1} = CLI.execute_string("X=5\n")
  {:ok, state2} = CLI.execute_string("echo $X\n", state: state1)

  assert length(state2.history) == 2
  assert List.last(state2.history).stdout == ["5\n"]
end
```

---

## Execution Record Structure

When using CLIHelper, you get access to [`ExecutionRecord`](lib/r_shell/cli/execution_record.ex:1) structs:

```elixir
%ExecutionRecord{
  fragment: "echo hello\n",           # Original input
  full_ast: %{...},                   # Complete parsed AST
  incremental_ast: %{...},            # Incremental parser AST
  execution_result: %{                # Execution outcome
    status: :success,
    node_type: "Command",
    ...
  },
  stdout: ["hello\n"],                # Output lines
  stderr: [],                         # Error lines
  exit_code: 0,                       # Command exit code
  context: %{                         # Runtime context
    env: %{"X" => 5, ...},
    cwd: "/path",
    exit_code: 0
  },
  parse_metrics: %{                   # Performance data
    duration_us: 1234,
    memory_delta: 5678
  },
  exec_metrics: %{...},
  timestamp: ~U[2025-01-01 00:00:00Z]
}
```

---

## Common Patterns

### Pattern 1: Check for Output

```elixir
# Simple
assert_cli_output(script, [stdout_contains: "expected"])

# Multiple checks
state = assert_cli_success(script)
outputs = Enum.flat_map(state.history, & &1.stdout)
assert Enum.any?(outputs, &(&1 =~ "pattern1"))
assert Enum.any?(outputs, &(&1 =~ "pattern2"))
```

### Pattern 2: Check Execution Count

```elixir
# For loops: verify iterations
script = """
for i in 1 2 3; do
  echo $i
done
"""

state = assert_cli_success(script)

# Count echo executions
echo_records = Enum.filter(state.history, fn r ->
  r.stdout != [] and r.stdout != [""]
end)

assert length(echo_records) == 3
```

### Pattern 3: Verify No Output

```elixir
# False condition: verify branch not taken
script = """
if false; then
  echo "should not print"
fi
"""

state = assert_cli_success(script)

echo_records = Enum.filter(state.history, fn r ->
  Enum.any?(r.stdout, &(&1 =~ "should not print"))
end)

assert length(echo_records) == 0
```

### Pattern 4: Multi-Record Scripts

```elixir
script = """
echo first
echo second
echo third
"""

state = assert_cli_output(script, [
  record_count: 3
])

# Access specific records
[r1, r2, r3] = state.history
assert r1.stdout == ["first\n"]
assert r2.stdout == ["second\n"]
assert r3.stdout == ["third\n"]
```

---

## Async Safety

### When to Use `async: true` (Preferred)

Most tests should run in parallel:

```elixir
defmodule RShell.Integration.MyTest do
  use ExUnit.Case, async: true  # ✅ Prefer this
  import RShell.TestSupport.CLIHelper
  
  # Tests here run in parallel
end
```

### When to Use `async: false`

Only when tests share global state:

```elixir
defmodule RShell.SomeTest do
  use ExUnit.Case, async: false  # ⚠️ Only if necessary
  
  # Examples:
  # - Testing actual compiled module with docstrings
  # - Shared GenServer instances
  # - File system operations on same files
end
```

**Current async: false tests:**
- [`error_classifier_test.exs`](test/unit/error_classifier_test.exs:2) - Shared IncrementalParser GenServer
- [`pubsub_test.exs`](test/unit/pubsub_test.exs:2) - Shared PubSub instance
- [`helpers_test.exs`](test/unit/builtins/helpers_test.exs:2) - Tests compiled module

---

## Timeout Protection

### Global Timeout

Set in [`test/test_helper.exs`](test/test_helper.exs:1):

```elixir
ExUnit.configure(timeout: 2000)  # 2 seconds per test
```

### CLI Helper Timeout

Default: **5 seconds** (configurable per test)

```elixir
# Default 5s timeout
assert_cli_success(script)

# Custom timeout
assert_cli_success(script, timeout: 10_000)  # 10 seconds
```

**Timeout means:**
- Infinite loop in control structure
- Waiting for input that never arrives
- Deadlock in parser/runtime communication

---

## Running Tests

```bash
# All tests
mix test

# Specific directory
mix test test/unit/
mix test test/integration/

# Specific file
mix test test/integration/cli_test.exs

# Specific test by line
mix test test/integration/cli_test.exs:10

# Verbose output (shows all test names)
mix test --trace

# Include skipped tests
mix test --include skip

# Run only integration tests
mix test test/integration/
```

---

## Migration Guide: Old → New Pattern

### Old Pattern (Deprecated)

```elixir
# Direct parser/runtime calls
{:ok, parser} = IncrementalParser.start_link(session_id: "test")
{:ok, _} = IncrementalParser.append_fragment(parser, "echo hello\n")
{:ok, ast} = IncrementalParser.get_current_ast(parser)
# ... manual verification
```

### New Pattern (Preferred)

```elixir
# CLI helper - tests full stack
state = assert_cli_success("echo hello\n")

# Verify AST
record = List.last(state.history)
assert record.full_ast != nil
assert record.incremental_ast != nil

# Verify execution
assert record.exit_code == 0
assert record.stdout == ["hello\n"]
```

**Benefits:**
- Tests complete pipeline (parser + runtime + executor)
- Less boilerplate
- Better failure diagnostics
- Automatic timeout protection
- Silent success pattern

---

## Best Practices

### ✅ Do

1. **Use CLIHelper for new tests** - Tests the full stack
2. **Test behavior, not implementation** - Verify AST + output, not internal state
3. **Keep tests focused** - One behavior per test
4. **Use descriptive names** - "executes then-branch when condition is true"
5. **Verify multiple aspects** - AST, output, context, metrics
6. **Use `async: true`** - Unless sharing global state
7. **Add comments for stub behavior** - "Variable expansion not yet implemented"

### ❌ Don't

1. **Don't test internal implementation details** - Focus on observable behavior
2. **Don't skip timeout protection** - Always use CLIHelper or add manual timeout
3. **Don't use absolute paths** - Tests run in different environments
4. **Don't leave TODOs in tests** - Either implement or skip with reason
5. **Don't test deprecated modules** - Move to `.deprecated/` instead

---

## Troubleshooting

### Test Hangs (Timeout)

**Cause:** Infinite loop, waiting for input, or deadlock

**Solution:**
```elixir
# Check timeout is set
assert_cli_success(script, timeout: 10_000)

# Add debug output in test
IO.inspect(state.history, label: "History so far")
```

### Verbose Failure Output Unclear

**Cause:** Need more context

**Solution:**
```elixir
# Access full state
state = assert_cli_success(script)
IO.inspect(state, label: "Full State")

# Check specific record
record = List.last(state.history)
IO.inspect(record.execution_result, label: "Execution")
IO.inspect(record.context, label: "Context")
```

### Test Passes Locally, Fails in CI

**Cause:** Race condition or timing issue

**Solution:**
- Change `async: true` to `async: false`
- Increase timeout
- Add synchronization via PubSub events

---

## Related Documentation

- [Unit Tests Documentation](UNIT_TESTS.md) - Detailed unit test coverage
- [Integration Tests](test/integration/) - Cross-module test examples
- [CLI Helper Source](test/support/cli_test_helper.ex) - Helper implementation
- [START_HERE.md](START_HERE.md) - Project overview
- [ARCHITECTURE_DESIGN.md](ARCHITECTURE_DESIGN.md) - System architecture

---

**Summary:** For most new tests, use [`CLIHelper`](test/support/cli_test_helper.ex:1) with [`assert_cli_success/2`](test/support/cli_test_helper.ex:23) or [`assert_cli_output/3`](test/support/cli_test_helper.ex:72). This tests the full stack (Parser → AST → Runtime → Execution) with silent success and verbose failure diagnostics.