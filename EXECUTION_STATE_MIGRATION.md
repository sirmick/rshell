# ExecutionState Migration Plan

## Goal
Migrate all execution functions from passing `(context, session_id)` to passing unified `ExecutionState` struct.

## Current State (10 commits completed)
- ✅ Frame and FrameStack infrastructure (34 tests)
- ✅ ExecutionState struct created
- ✅ Loops use frame-based accumulation pattern
- ✅ No regressions (396 tests, 4 baseline failures)

## Migration Strategy

### Phase 1: Core Entry Point
File: `lib/r_shell/runtime.ex`

Change `execute_node_internal` to use ExecutionState:
```elixir
# Before
defp execute_node_internal(node, context, session_id) do
  new_context = RShell.Runtime.ExecutionPipeline.execute(node, context, session_id)
  {{:ok, new_context}, new_context}
end

# After
defp execute_node_internal(node, context, session_id) do
  state = ExecutionState.from_runtime_state(%{
    context: context,
    frame_stack: frame_stack, # Need to pass this somehow
    session_id: session_id
  })
  new_state = do_execute_node(node, state)
  {{:ok, new_state.context}, new_state.context}
end
```

### Phase 2: Control Flow Functions
Migrate in this order (test after each):

1. `execute_while_statement/3` → `execute_while_statement/2`
2. `execute_for_statement/3` → `execute_for_statement/2`
3. `execute_if_statement/3` → `execute_if_statement/2`

Each change:
- Update function signature
- Access via `state.context`, `state.frame_stack`, `state.session_id`
- Return updated state

### Phase 3: Block & Command Execution
4. `execute_block/4` → `execute_block/2`
5. `execute_command_list/4` → `execute_command_list/2`
6. `execute_body_nodes/4` → `execute_body_nodes/2`

### Phase 4: Command Execution
7. `execute_command/3` → `execute_command/2`
8. `execute_builtin/5` → Update to extract from state
9. `simple_execute/3` → `simple_execute/2`

### Phase 5: Helpers
10. All condition evaluation functions
11. All helper functions (extract_*, evaluate_*)

### Phase 6: Use FrameStack
Replace `context.last_output` with actual FrameStack operations:
- `FrameStack.push_frame` for loops
- `FrameStack.add_output` for commands
- `FrameStack.pop_frame` at end of loops
- `FrameStack.get_output` to retrieve accumulated output

## Estimated Effort
- Phase 1-2: 2-3 hours
- Phase 3-4: 3-4 hours  
- Phase 5-6: 3-4 hours
- **Total: 8-11 hours**

## Testing Strategy
- Run `mix test` after each phase
- Ensure 396 tests, 4 failures (baseline) maintained
- Add ExecutionState-specific tests

## Current Branch
`feature/execution-frame-stack` (10 commits)

## Next Commit
Start Phase 1: Update core entry point to create ExecutionState