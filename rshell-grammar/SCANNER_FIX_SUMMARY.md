# Scanner Fix Summary

## Problem Analysis

The current scanner (382 lines) has 8+ token types and complex mode tracking that fails in these scenarios:
1. Property access after `$rsh()`: `$rsh(whoami).exit_code` 
2. Chained assignments: `user = $rsh(whoami) and host = $rsh(hostname)`
3. Pipeline support within cross-mode constructs

The root cause: Scanner doesn't properly signal mode return after `$rsh()` closes.

## Failed Approach: Simplified Scanner

We attempted to create a simplified scanner with only 4 tokens (CMD_START/END, EXPR_START/END) that would only emit mode boundary tokens. However, this approach:
- Required complete grammar rewrite
- Broke compatibility with existing tests
- Introduced more complexity than it solved

## Recommended Solution

Fix the existing scanner.c by:

1. **Mode Stack Fix**: Ensure the scanner properly tracks nested modes
2. **Closing Delimiter Detection**: When `)` closes a `$rsh()`, ensure mode returns to EXPR
3. **Property Access**: After CMD_END token, allow EXPR mode tokens like `.`
4. **Operator Access**: After CMD_END, allow EXPR operators like `and`, `or`

## Key Insight

The scanner already has all the necessary infrastructure. The issue is in the `handle_close_paren()` function around line 260 of scanner.c. It needs to:
1. Check if we're in CMD mode due to `$rsh()`
2. Pop the mode back to EXPR
3. Emit CMD_END token
4. Allow subsequent EXPR tokens (property access, operators)

## Test Coverage Status

Current: 19/23 passing (82.6%)
Failing tests all related to post-$rsh() mode restoration:
- Property access after $rsh()
- Chained assignments with $rsh()
- Complex expressions involving $rsh()

## Next Steps

1. Fix the `handle_close_paren()` function in scanner.c
2. Ensure mode stack properly tracks $rsh() depth
3. Test that `.exit_code` and `and` operators work after $rsh()
4. Achieve 100% test coverage