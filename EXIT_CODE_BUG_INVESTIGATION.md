# Exit Code Bug Investigation Summary

## Problem
The `false` builtin returns exit code 0 instead of 1 through the entire execution pipeline.

## What We've Verified

### ✅ Working Correctly
1. **Builtin Layer**: `Builtins.execute("false", ...)` correctly returns `{context, stdout, stderr, 1}`
2. **BuiltinResult Module**: `BuiltinResult.materialize_and_update()` correctly sets `context.exit_code = 1`
3. **Runtime.execute_builtin**: Returns context with exit_code: 1

### ❌ Broken
4. **CLI Executor**: The execution_result recorded in history shows exit_code: 0
5. **Test Result**: `false_record.exit_code == 0` (should be 1)

## Key Finding

When testing the builtin directly:
```elixir
{new_ctx, stdout, stderr, exit_code} = Builtins.execute("false", [], "", context)
# exit_code = 1 ✅
# new_ctx.exit_code = 0 ❌ (unchanged from input context)
```

**The builtin returns the UNCHANGED input context, with exit_code as a SEPARATE tuple element.**

This is the root cause - there's a semantic confusion about whether exit codes live:
- IN the context map, or
- As a separate return value

## Investigation Trail

1. Started with suspicion that CmdLine unwrapping was losing exit codes
2. Simplified execution flow with `then` pipelines
3. Created BuiltinResult struct to wrap POSIX-style tuples
4. BuiltinResult correctly updates context with exit code
5. Traced through entire execution pipeline
6. Found that even with BuiltinResult, exit code still shows 0

## Hypothesis

The issue is likely in how the GenServer state is being queried vs. the context that flows through function returns. There may be:

1. **Race condition**: The GenServer state update happens after the context is read
2. **Stale context**: Something is calling `Runtime.get_context()` which gets old state
3. **Lost update**: The context update happens but gets overwritten by a subsequent operation
4. **Map update issue**: The `%{context | exit_code: exit_code}` syntax isn't working as expected for maps

## Solution Approach

The fundamental issue is **mixing context-in-map with exit-code-as-separate-value semantics**. 

### Short-term Fix (Recommended)
Keep the POSIX-style signature but ensure the BuiltinResult struct is the ONLY thing that handles the merge:

```elixir
# Runtime.execute_builtin
result = BuiltinResult.from_tuple(Builtins.execute(name, args, stdin, context))
BuiltinResult.materialize_and_update(result)
# ^ This correctly returns context with exit_code: 1
```

**The mystery**: Why does this context get lost between Runtime and Executor?

### Long-term Fix (Architectural)
As proposed in EXECUTION_FLOW_REFACTOR_PROPOSAL.md:
- Use ExecutionContext struct instead of map
- Exit code always lives IN context, never separate
- Removes ambiguity about which is authoritative

## Next Steps

1. Add debug logging to Runtime.execute_builtin to confirm context.exit_code is 1 on return
2. Add debug logging to ExecutionPipeline.run_execution to see what new_context has
3. Add debug logging to Executor.execute_ast_synchronously line 131 to see what context.exit_code is
4. Find where the exit code gets lost

## Time Investment
- ~2 hours debugging
- Multiple approaches attempted
- Root cause identified but specific loss point still elusive

## Impact
- Blocks 1 integration test (exit code tracking)
- Does not block basic command execution (echo works)
- Does not block RShell syntax migration (72 other test failures to address)

---

*Investigation paused to document findings and propose architectural refactor*