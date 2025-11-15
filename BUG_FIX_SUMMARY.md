# Bug Fix Summary - Output Leakage in Interactive Mode

## The Bug Report

**User Report**: When typing `X=12` (a variable assignment) in interactive mode, the output from the previous `man` command was being displayed.

## Root Cause Analysis

### Initial Hypothesis (Incorrect)
Initially suspected that **PubSub events were leaking** between commands due to missing event draining after the refactor to use `Executor.execute_fragment`.

### Actual Root Cause (Correct)
The bug was in **`Runtime.execute_variable_assignment/3`** at line 303-304 in [`lib/r_shell/runtime.ex`](lib/r_shell/runtime.ex:273).

Variable assignments were updating the environment but **not clearing `context.last_output`**, causing them to inherit stdout/stderr from the previous command.

## The Fixes

### Fix 1: Clear Output in Variable Assignments (PRIMARY FIX)
**File**: [`lib/r_shell/runtime.ex`](lib/r_shell/runtime.ex:303)

```elixir
# BEFORE
new_env = Map.put(context.env, var_name, parsed_value)
%{context | env: new_env}

# AFTER
new_env = Map.put(context.env, var_name, parsed_value)
# Variable assignments produce NO output - clear last_output
%{context | env: new_env, last_output: %{stdout: [], stderr: []}}
```

**Why**: Variable assignments in Bash produce no output. The Runtime was carrying forward output from previous commands.

### Fix 2: Drain PubSub Events in Executor (SECONDARY FIX)
**File**: [`lib/r_shell/cli/executor.ex`](lib/r_shell/cli/executor.ex:70)

Added `drain_pubsub_events/1` function to consume stale PubSub messages after each execution:

```elixir
# Add to history
new_state = %{state | history: state.history ++ [record]}

# Drain any remaining PubSub events to prevent stale messages
drain_pubsub_events(state.session_id)

{:ok, new_state}
```

**Why**: While not the primary cause of the bug, PubSub events were accumulating in the mailbox and could cause issues in the future.

### Fix 3: Event Draining Already in Interactive Loop
**File**: [`lib/r_shell/cli.ex`](lib/r_shell/cli.ex:780)

The interactive loop already had `drain_pubsub_events/1` call at line 780, which is good practice to prevent stale messages between interactive commands.

### Fix 4: `.last` Command Metadata Format
**File**: [`lib/r_shell/cli.ex`](lib/r_shell/cli.ex:796)

The `.last` command was not working because the incremental AST metadata was being stored incorrectly:

```elixir
# BEFORE
last_ast_metadata: last_record && last_record.incremental_ast,

# AFTER
last_ast_metadata = if last_record && last_record.incremental_ast do
  %{changed_nodes: last_record.incremental_ast}
else
  nil
end
```

**Why**: The `.last` command expects `%{changed_nodes: [nodes]}` but we were storing just the list directly.

## Testing Strategy

Created comprehensive test suite to prevent regression:

### New Test File: `test/integration/interactive_mode_test.exs`
- **18 new tests** covering:
  - Command output isolation
  - Variable assignment behavior
  - PubSub event draining
  - State accumulation
  - Multi-line input handling
  - Edge cases and error handling

### Key Test Cases
1. **Variable assignment produces no output** - Core bug test
2. **Builtin → variable → builtin sequence** - Exact bug scenario
3. **PubSub event draining** - Ensures mailbox is clean
4. **Multiple commands maintain isolation** - No cross-contamination

### Documentation: `INTERACTIVE_TESTING_STRATEGY.md`
- Comprehensive testing strategy document
- 446 lines covering all aspects of interactive mode
- Test patterns and helper functions
- Coverage goals and success metrics

## Impact

### Before Fix
- **7 test failures** out of 18 new tests
- Variable assignments showed output from previous commands
- PubSub events accumulated in mailbox

### After Fix
- ✅ **All 335 tests passing** (16 doctests + 319 unit/integration tests)
- ✅ **Zero compiler warnings**
- ✅ Variable assignments produce no output
- ✅ PubSub events properly drained
- ✅ Clean command isolation

## Files Modified

1. **`lib/r_shell/runtime.ex`** - Clear output in variable assignments (PRIMARY FIX)
2. **`lib/r_shell/cli/executor.ex`** - Add PubSub event draining (SECONDARY FIX)
3. **`lib/r_shell/cli.ex`** - Fix `.last` command metadata format
4. **`test/integration/interactive_mode_test.exs`** - New comprehensive tests (18 tests)
5. **`INTERACTIVE_TESTING_STRATEGY.md`** - New testing documentation (446 lines)
6. **`BUG_FIX_SUMMARY.md`** - This document

## Lessons Learned

1. **State Management**: Always clear output fields when operations produce no output
2. **Testing**: Comprehensive tests caught the bug immediately
3. **Root Cause**: Don't assume the first hypothesis is correct - investigate thoroughly
4. **Event Systems**: PubSub events can accumulate; always drain after operations
5. **Context Immutability**: Ensure all context updates are complete and correct

## Prevention

To prevent similar bugs in the future:

1. **Run new test suite** on every commit: `mix test test/integration/interactive_mode_test.exs`
2. **Test command sequences** when adding new node types
3. **Always clear `last_output`** when operations produce no output
4. **Verify output isolation** between commands
5. **Check PubSub mailbox** after async operations

## Related Issues

None currently, but this pattern could affect other node types:

- If/else statements
- For/while loops (currently only capture last iteration - documented in tests)
- Function definitions (when implemented)

## Credits

- Bug discovered by user during interactive testing
- Fixed by systematically testing the execution pipeline
- Comprehensive test suite ensures no regression