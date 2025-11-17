# RShell Enhanced Syntax Design

**Status**: ✅ Phase 2 Complete - Mode Detection + Control Flow + Expressions
**Last Updated**: 2025-11-17
**Goal**: Clean, purpose-built shell with structured data support

---

## Table of Contents

1. [Design Principles](#design-principles)
2. [Mode Switching Rules](#mode-switching-rules)
3. [Core Syntax](#core-syntax)
4. [Expression Mode Features](#expression-mode-features)
5. [Command Mode Features](#command-mode-features)
6. [Complete Examples](#complete-examples)
7. [Implementation Phases](#implementation-phases)

---

## Design Principles

### 1. Line-Based Mode Detection

**The mode is determined by how each line STARTS:**

- **Expression Mode**: Line starts with `IDENTIFIER =`, `if`, `for`, `while`, `else`, `elif`
- **Command Mode**: Everything else

### 2. Clear Mode Boundaries

```bash
# Expression mode (starts with assignment)
SERVERS = [{'fqdn':'a.b.c', 'port':8000}]

# Expression mode (starts with 'for')
for S in SERVERS {
  # Expression mode (starts with assignment)
  result = shell(ssh $S.fqdn -p $S.port)
  
  # Expression mode (starts with 'if')
  if (not result.success) {FAILED += S}
}

# Command mode (doesn't start with keyword or assignment)
ssh server.com -p 8080 -c uname -a
```

### 3. Cross-Mode Features

**Expression Mode → Command Mode:**
- `shell(COMMAND)` - Explicit command execution from expression mode
- Returns result object with `.success`, `.stdout`, `.stderr`, `.exit_code`

**Command Mode → Expression Mode:**
- `{expression}` - Expression interpolation within commands
- Evaluates to string and injects into command

---

## Mode Switching Rules

### Expression Mode Triggers

A line enters **Expression Mode** if it starts with:

1. **Assignment**: `IDENTIFIER = ...`
2. **Control flow**: `if`, `for`, `while`, `elif`, `else`

### Expression Mode Features

```bash
# Assignments
X = 42
SERVERS = [{'fqdn':'a.b.c', 'port':8000}]
FAILED = []

# Compound assignment
SERVERS += {'fqdn':'n.m.j', 'port':8002}
SUCCESS += S
COUNT += 1

# Control flow
for S in SERVERS {
  # Block content
}

if (not result.success) {
  FAILED += S
} else {
  SUCCESS += S
}

# Explicit command execution
result = shell(ssh $S.fqdn -p $S.port)
output = shell(uname -a)
```

### Command Mode Triggers

A line enters **Command Mode** if it starts with anything else:

```bash
# Direct commands
ssh server.com -p 8080
echo Hello World
ls -la

# Commands with expression interpolation
ssh {S.fqdn} -p {S.port} -c uname -a
echo Server {S.fqdn} succeeded! Total: {SUCCESS.length}
cat {filename}
```

---

## Core Syntax

### Comments

```bash
# Single line comment
X = 42  # Inline comment
```

### Data Types

#### Numbers
```bash
COUNT = 42
PI = 3.14159
NEGATIVE = -10
```

#### Strings
```bash
NAME = 'production'
MESSAGE = "Hello $USER"
MULTILINE = """
Line 1
Line 2
"""
```

#### Booleans
```bash
DEBUG = true
ENABLED = false
```

#### Lists
```bash
# Simple lists
NUMBERS = [1, 2, 3, 4, 5]
NAMES = ['Alice', 'Bob', 'Charlie']

# Lists of objects
SERVERS = [
  {'fqdn':'a.b.c', 'port':8000},
  {'fqdn':'q.y.z', 'port':8001}
]

# Empty list
FAILED = []
```

#### Maps/Objects
```bash
# Simple map
CONFIG = {'host': 'localhost', 'port': 8080}

# Nested map
SERVER = {
  'fqdn': 'a.b.c',
  'port': 8000,
  'config': {
    'ssl': true,
    'timeout': 30
  }
}
```

### Variable References

```bash
# Simple reference
echo $NAME

# Property access (dot notation)
$S.fqdn
$SERVER.config.ssl
$RESULT.stdout

# Array/list indexing
$SERVERS[0]
$ITEMS[-1]  # Last item

# Length property
$SUCCESS.length
$SERVERS.length
```

---

## Expression Mode Features

### Assignments

```bash
# Basic assignment
X = 42
NAME = 'production'

# List/map assignment
SERVERS = [{'fqdn':'a.b.c', 'port':8000}]
CONFIG = {'debug': true}

# Compound assignments
SERVERS += {'fqdn':'n.m.j', 'port':8002}  # Append to list
COUNT += 1                                 # Add to number
FAILED += S                                # Append item
```

### Operators

```bash
# Arithmetic
SUM = 10 + 5
DIFF = 20 - 8
PRODUCT = 6 * 7
QUOTIENT = 15 / 3

# Comparison
X > 10
Y < 5
Z == 100
A != 0

# Logical
BOTH = A and B
EITHER = X or Y
NEGATED = not VALUE
COMPLEX = (A and B) or not C

# String concatenation
FULL = FIRST + ' ' + LAST
```

### Control Flow

#### If Statements

```bash
if (condition) {
  # statements
}

if (not result.success) {
  FAILED += S
} else {
  SUCCESS += S
}

if (COUNT > 10) {
  echo 'Large'
} elif (COUNT > 5) {
  echo 'Medium'
} else {
  echo 'Small'
}
```

#### For Loops

```bash
# Iterate over list
for S in SERVERS {
  result = shell(ssh $S.fqdn -p $S.port)
}

# Iterate with index (future)
for (i, S) in enumerate(SERVERS) {
  echo "Server {i}: {S.fqdn}"
}
```

#### While Loops

```bash
# Counter loop
COUNT = 0
while (COUNT < 10) {
  COUNT += 1
}

# Condition-based
while (not ready) {
  result = shell(check_status)
  ready = result.success
}
```

### The shell() Function

Execute commands from expression mode:

```bash
# Basic execution
result = shell(ls -la)
result = shell(ssh $S.fqdn -p $S.port)

# Result object has:
result.success    # Boolean: exit_code == 0
result.stdout     # String: captured output
result.stderr     # String: captured errors
result.exit_code  # Number: command exit code

# Usage
result = shell(ssh server.com uname -a)
if (result.success) {
  echo $result.stdout
} else {
  log.write('Error: ' + $result.stderr)
}
```

---

## Command Mode Features

### Direct Commands

```bash
# Simple commands
ls
pwd
date

# Commands with arguments
ls -la
echo Hello World
git commit -m 'message'

# Pipelines
cat file.txt | grep pattern | wc -l
ps aux | grep python | awk '{print $2}'
```

### Expression Interpolation with {}

Inject expression values into commands:

```bash
# Property access
ssh {S.fqdn} -p {S.port} -c uname -a
cat {CONFIG.logfile}
mkdir {BASE_PATH}/subdir

# String expressions
echo Server {S.fqdn} succeeded!
echo Total successful: {SUCCESS.length}
curl https://{HOST}:{PORT}/api

# Complex expressions
echo Processing item {i+1} of {ITEMS.length}
ssh {SERVERS[0].fqdn} whoami
```

### Variable References

```bash
# $ syntax for variable references
echo $NAME
ssh $HOST -p $PORT
cat $FILENAME

# {} syntax for expressions
echo {S.fqdn}
ssh {S.fqdn} -p {S.port}
```

---

## Complete Examples

### Example 1: Server Health Check

```bash
#!/usr/bin/env rshell

# Expression mode - setup
SERVERS = [
  {'fqdn':'web1.example.com', 'port':22},
  {'fqdn':'web2.example.com', 'port':22},
  {'fqdn':'db1.example.com', 'port':22}
]
FAILED = []
SUCCESS = []

# Expression mode - add a server
SERVERS += {'fqdn':'api1.example.com', 'port':22}

# Expression mode - check each server
for S in SERVERS {
  result = shell(ssh $S.fqdn -p $S.port echo ok)
  
  if (not result.success) {
    FAILED += S
  } else {
    SUCCESS += S
    log.write(S, 'success')
  }
}

# Expression mode - report successes
for S in SUCCESS {
  # Command mode - direct command with interpolation
  echo {S.fqdn} succeeded! Total: {SUCCESS.length} of {SERVERS.length}
  
  # Command mode - SSH command
  ssh {S.fqdn} -p {S.port} -c uname -a
}

# Expression mode - report failures
if (FAILED.length > 0) {
  for S in FAILED {
    # Command mode
    echo FAILED: {S.fqdn}
  }
}
```

### Example 2: Log Processing

```bash
#!/usr/bin/env rshell

# Expression mode - setup
LOGFILE = '/var/log/app.log'
ERROR_COUNT = 0
WARNING_COUNT = 0
ERRORS = []

# Expression mode - read log (shell command)
LINES = shell(cat $LOGFILE).stdout.split('\n')

# Expression mode - process lines
for LINE in LINES {
  if (LINE.contains('ERROR')) {
    ERROR_COUNT += 1
    ERRORS += LINE
  } elif (LINE.contains('WARNING')) {
    WARNING_COUNT += 1
  }
}

# Command mode - report
echo Total errors: {ERROR_COUNT}
echo Total warnings: {WARNING_COUNT}

# Expression mode - show details
if (ERROR_COUNT > 0) {
  for ERR in ERRORS {
    # Command mode
    echo ERROR: {ERR}
  }
}
```

### Example 3: Deployment Script

```bash
#!/usr/bin/env rshell

# Expression mode - configuration
ENV = 'production'
VERSION = '1.2.3'
SERVERS = [
  {'fqdn':'web1.prod.com', 'port':22, 'role':'web'},
  {'fqdn':'web2.prod.com', 'port':22, 'role':'web'},
  {'fqdn':'api1.prod.com', 'port':22, 'role':'api'}
]

# Expression mode - deploy to each server
for S in SERVERS {
  # Command mode - show progress
  echo Deploying {VERSION} to {S.fqdn} ({S.role})
  
  # Expression mode - copy files
  result = shell(rsync -avz ./dist/ {S.fqdn}:/app/)
  
  if (not result.success) {
    # Command mode
    echo FAILED to copy files to {S.fqdn}
    continue
  }
  
  # Expression mode - restart service
  restart_result = shell(ssh {S.fqdn} systemctl restart app)
  
  if (restart_result.success) {
    # Command mode
    echo SUCCESS: {S.fqdn} deployed and restarted
  } else {
    # Command mode
    echo FAILED: {S.fqdn} restart failed
  }
}

# Command mode - final message
echo Deployment complete for version {VERSION}
```

---

## Implementation Phases

### Phase 1: Core Shell (Week 1)

**Goal**: Basic mode switching and data structures

**Grammar Features**:
- Line-based mode detection (`IDENTIFIER =` vs everything else)
- Basic data types (numbers, strings, booleans, lists, maps)
- Simple assignments
- Direct commands
- Comments

**Checklist**:
- [ ] Assignment detection: `X = 42`
- [ ] Commands parse: `ls`, `echo hello`
- [ ] Lists work: `[1, 2, 3]`
- [ ] Maps work: `{'key': 'value'}`
- [ ] Variable references: `$X`, `$S.fqdn`

**Test Cases**:
```bash
X = 42
SERVERS = [{'fqdn':'a.b.c', 'port':8000}]
echo Hello
ls -la
```

### Phase 2: Control Flow (Week 2)

**Goal**: If/for/while statements

**Grammar Features**:
- `if (condition) { ... }` with `elif` and `else`
- `for item in list { ... }`
- `while (condition) { ... }`
- Comparison operators (`>`, `<`, `==`, `!=`)
- Logical operators (`and`, `or`, `not`)

**Checklist**:
- [ ] If statements work
- [ ] For loops iterate
- [ ] While loops work
- [ ] Comparisons evaluate
- [ ] Logical ops work

**Test Cases**:
```bash
for S in SERVERS {
  if (S.port > 8000) {
    echo High port
  }
}
```

### Phase 3: Cross-Mode Features (Week 3)

**Goal**: shell() and {} interpolation

**Grammar Features**:
- `shell(command)` function in expression mode
- `{expression}` interpolation in command mode
- Result object (`.success`, `.stdout`, `.stderr`, `.exit_code`)
- String methods (`.contains()`, `.split()`, `.length`)

**Checklist**:
- [ ] shell() executes commands
- [ ] Result object works
- [ ] {} interpolation in commands
- [ ] Property access works
- [ ] Method calls work

**Test Cases**:
```bash
result = shell(ls -la)
echo Status: {result.exit_code}
ssh {S.fqdn} -p {S.port} whoami
```

---

## Grammar Development Strategy

### Key Rules

1. **Start-of-line detection** determines mode
   - `IDENTIFIER =` → Expression mode
   - `if`/`for`/`while`/`elif`/`else` → Expression mode  
   - Everything else → Command mode

2. **No mode keywords needed**
   - No `cmd:` or `expr:` prefixes
   - Natural, readable syntax

3. **Clear interpolation syntax**
   - Expression mode: `shell(command)` for explicit commands
   - Command mode: `{expr}` for expression injection

### Development Tips

1. **Start with mode detection**
   ```javascript
   _statement: $ => choice(
     $.assignment,      // Starts with IDENTIFIER =
     $.control_flow,    // Starts with if/for/while
     $.command          // Everything else
   )
   ```

2. **Add data structures next**
   - Lists: `[1, 2, 3]`
   - Maps: `{'key': 'value'}`
   - Property access: `$S.fqdn`

3. **Then control flow**
   - If/elif/else
   - For loops
   - While loops

4. **Finally cross-mode features**
   - `shell()` function
   - `{}` interpolation
   - Result objects

---

## Timeline Summary

| Phase | Duration | Status | Deliverable |
|-------|----------|--------|-------------|
| 1 | 1 week | ✅ Complete | Mode switching + data structures |
| 2 | 1 week | ✅ Complete | **Automatic mode detection** + control flow + expressions + property access |
| 3 | 1 week | 🚧 In Progress | shell() and {} interpolation |
| **Total** | **3 weeks** | **Phase 2** | **Complete RShell syntax** |

---

## Phase 2 Achievements (NEW!)

**Automatic Line-Based Mode Detection** - No manual mode switching required! ✅

The scanner now automatically detects whether each line should be parsed as EXPR or CMD mode:

- **EXPR mode auto-detected**: `X = 42`, `if (X > 10) {`, `for S in SERVERS {`
- **CMD mode auto-detected**: `echo hello`, `ls -la`, `grep pattern`
- **Mode change optimization**: Only emits mode tokens when switching between EXPR/CMD

**Test Results**: 38/38 tests passing (100%)

See [`PHASE_2_MODE_DETECTION_COMPLETE.md`](PHASE_2_MODE_DETECTION_COMPLETE.md) for full technical details.

---

**Last Updated**: 2025-11-17
**Current Phase**: Week 3 - Cross-mode features (shell() and {} interpolation)
**Completed**: Phase 1 + Phase 2 with automatic mode detection - All 38 tests passing (100%)
