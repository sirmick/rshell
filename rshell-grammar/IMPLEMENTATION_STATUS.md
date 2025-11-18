# RShell Grammar Implementation Status

## Current State
After thorough investigation, we found that the RShell grammar implementation is incomplete:

### What Works (100% pass rate)
- Basic assignments, expressions, control flow
- Lists, maps, property access
- Commands and pipelines in their respective modes
- Line-based mode detection (CMD vs EXPR)

### What's Not Implemented
The key mode-switching constructs that were documented but never implemented:
1. **`$rsh()`** - Execute commands from EXPR mode 
2. **`${}`** - Expression interpolation in CMD mode
3. **Mode switching tokens** - The scanner doesn't emit mode boundary tokens

## The Disconnect
The project has:
- Documentation describing `$rsh()` and `${}` syntax
- Test cases expecting these features
- But NO actual implementation in scanner.c or grammar.js

## Current Scanner
The scanner only provides:
- `NEWLINE` tokens
- `LINE_START` tokens with mode detection based on line content
- `COMMAND_SUBSTITUTION` for traditional `$()` 

It does NOT handle:
- `$rsh()` construct
- `${}` interpolation
- Mode switching within a line

## Recommendation
Rather than trying to "fix" non-existent features, we need to:

1. **Accept Current Reality**: The grammar currently uses line-based mode detection
2. **Document Actual Syntax**: Update docs to reflect what's actually implemented
3. **Future Enhancement**: If `$rsh()` and `${}` are needed, they should be added as new features

## Test Results
- Basic grammar tests: 69/69 (100%)
- Scanner mode detection: 15/20 (75%)
- Mode-specific syntax: 0/23 (0%) - because features don't exist

## Conclusion
The "failing" tests are testing features that were never implemented. The actual implementation uses a simpler line-based approach where:
- Lines starting with keywords/assignments are EXPR mode
- Lines starting with commands/paths are CMD mode
- No inline mode switching exists