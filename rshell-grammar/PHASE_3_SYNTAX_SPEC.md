# Phase 3 Syntax Specification

## Overview
Phase 3 adds advanced features to bridge the gap between expression mode (EXPR) and command mode (CMD), allowing for more flexible scripting.

## 1. Command Interpolation in CMD Mode: `{expression}`

**Purpose:** Insert the value of any expression into a command

**Syntax:** `{EXPR}` where EXPR is any valid RShell expression

**Examples:**
```rshell
# Simple variable interpolation
NAME = "world"
echo Hello {NAME}  # Output: Hello world

# Property access
SERVER = {"host": "example.com", "port": 8080}
ssh {SERVER.host} -p {SERVER.port}

# Arithmetic expressions
COUNT = 5
echo You have {COUNT + 1} items  # Output: You have 6 items

# Complex expressions
USERS = ["alice", "bob"]
echo First user is {USERS[0]}
```

**Key Points:**
- The `{}` syntax only works in CMD mode
- Any valid expression can go inside the braces
- The expression result is converted to string and inserted into the command

## 2. Shell Function in EXPR Mode: `shell(command)`

**Purpose:** Execute shell commands from within expression mode and capture results

**Syntax:** `shell(STRING)` where STRING is a quoted command

**Returns:** An object with:
- `.success` - boolean, true if exit code was 0
- `.stdout` - string, the standard output
- `.stderr` - string, the standard error  
- `.exit_code` - number, the exit code

**Examples:**
```rshell
# Basic usage with string literal
result = shell("ls -la")
if (result.success) {
    echo "Directory listed successfully"
}

# Using template strings with interpolation
DIR = "/tmp"
files = shell(`ls ${DIR}`)

# Using variables
CMD = "ps aux | grep python"
processes = shell(CMD)

# Using identifier (variable without $)
command = "date +%Y-%m-%d"
today = shell(command)

# Checking command success
if (shell("test -f config.json").success) {
    config = shell("cat config.json").stdout
}

# Using in complex expressions
for SERVER in SERVERS {
    uptime = shell(`ssh ${SERVER} uptime`)
    if (uptime.success) {
        echo {SERVER} is up: {uptime.stdout}
    }
}
```

**Key Points:**
- The command MUST be quoted (string literal) or a variable
- Cannot use raw unquoted commands like `shell(ls -la)` - too complex to parse
- Returns an object, not just stdout
- Useful for conditional logic based on command success

## 3. Template Strings: `` `string ${expression}` ``

**Purpose:** JavaScript-style template literals with embedded expressions

**Syntax:** `` `text ${EXPR} more text` ``

**Examples:**
```rshell
# Simple interpolation
NAME = "Alice"
greeting = `Hello, ${NAME}!`

# Multiple interpolations
USER = "Bob"
COUNT = 42
message = `User ${USER} has ${COUNT} items`

# Expressions in templates
X = 10
result = `The answer is ${X * 2}`

# Use with shell() function
DIR = "/home/user"
PORT = 8080
output = shell(`netstat -an | grep ${PORT}`)
```

## 4. Path Literals

**Purpose:** Allow file paths as command names without quoting

**Syntax:** Paths starting with `/`, `./`, `../`, or `~/`

**Examples:**
```rshell
# Absolute paths
/usr/bin/python3 script.py
/bin/ls -la

# Relative paths
./build.sh --production
../scripts/deploy.sh

# Home paths  
~/bin/my-tool --help

# With interpolation
/usr/bin/python3 {SCRIPT_NAME} --config {CONFIG_FILE}
```

## 5. Generic Function Calls

**Purpose:** Support for built-in functions (for future expansion)

**Syntax:** `function_name(arg1, arg2, ...)`

**Examples:**
```rshell
# Future built-in functions
value = random()
upper = uppercase(NAME)
result = join(LIST, ", ")
value = max(min(X, 100), 0)
```

## Design Philosophy

The key design principle is **context-aware parsing**:

1. **In CMD mode:** Commands are primary, use `{}` to embed expressions
2. **In EXPR mode:** Expressions are primary, use `shell()` to run commands
3. **Clear boundaries:** Commands in `shell()` must be quoted to avoid parsing ambiguity
4. **Predictable behavior:** The parser always knows what mode it's in

## Why These Choices?

1. **`{}` for CMD interpolation:** Familiar from many template languages, clear visual distinction from `${}` in templates

2. **`shell()` requires quotes:** Parsing raw shell commands inside function calls is extremely complex due to:
   - Shell special characters (pipes, redirects, quotes)
   - Ambiguity with expression syntax
   - Need to handle all shell constructs

3. **Template strings with `${}`:** Industry standard (JavaScript, many other languages)

4. **Path literals:** Common use case that shouldn't require quoting

## Summary

- **CMD mode:** Write commands naturally, use `{expr}` to insert values
- **EXPR mode:** Write expressions naturally, use `shell("cmd")` to run commands
- Both modes can achieve the same results, choose based on primary task
- Clear, unambiguous syntax that the parser can handle reliably