# RShell Simplified Scanner Implementation

## Overview
The simplified scanner uses only 4 external tokens for clean mode boundary detection:
- `CMD_START` - Entering command mode (via `$rsh()`)
- `CMD_END` - Exiting command mode (closing `)`)
- `EXPR_START` - Entering expression mode (via `${}`)
- `EXPR_END` - Exiting expression mode (closing `}`)

## Key Features

### Mode Switching Constructs

#### `$rsh()` - Command Execution in Expression Mode
```javascript
// In EXPR mode, execute a command
result = $rsh(ls -la)
exit_code = $rsh(grep pattern file.txt).exit_code
```

#### `${}` - Expression Interpolation in Command Mode  
```bash
# In CMD mode, interpolate expressions
echo ${user.name}
ls ${path + "/bin"}
```

## Scanner Implementation
The scanner (`scanner_simple.c`) only emits tokens at mode boundaries:
- Detects `$rsh(` → emits `CMD_START`, pushes CMD mode
- Detects `)` in CMD mode → emits `CMD_END`, pops to EXPR mode
- Detects `${` → emits `EXPR_START`, pushes EXPR mode  
- Detects `}` in EXPR mode → emits `EXPR_END`, pops to CMD mode

## Grammar Implementation
The grammar (`grammar_simple.js`) is context-free:
- All parsing logic is in the grammar rules
- Scanner only signals mode transitions
- Clean separation of concerns

## Benefits
1. **Simplicity**: Only 4 tokens instead of complex mode tracking
2. **Correctness**: Mode stack properly maintained
3. **Extensibility**: Easy to add new cross-mode constructs
4. **Performance**: Minimal scanner overhead

## Usage Examples

### Property Access After Command
```javascript
user = $rsh(whoami).stdout
// Scanner: [EXPR] → CMD_START → [CMD] → CMD_END → [EXPR]
```

### Chained Assignments
```javascript
user = $rsh(whoami) and host = $rsh(hostname)
// Proper mode restoration allows 'and' operator
```

### Command with Expression Interpolation
```bash
echo Hello ${user.name}, your home is ${env.HOME}
// Scanner handles nested mode switches cleanly
```

## Testing
The simplified implementation should:
- Pass all basic grammar tests
- Handle `$rsh()` with property access
- Support chained assignments with `$rsh()`
- Allow `${}` interpolation in commands