# RShell Enhanced Syntax Design

**Status**: ✅ Phase 3 Complete - Command Substitution + Redirection Design
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

- **Expression Mode**: Line starts with `IDENTIFIER =` (or `+=`, `-=` etc), `if`, `for`, `while`, `else`, `elif`. Or in ${} while in Command Mode
- **Command Mode**: Everything else, or in $rsh() in Expression Mode

### 2. Clear Mode Boundaries

```bash
# Expression mode (starts with assignment)
SERVERS = [{'fqdn':'a.b.c', 'port':8000}]

# Expression mode (starts with 'for')
for S in SERVERS {
  # Expression mode (starts with assignment)
  result = $rsh(ssh $S.fqdn -p $S.port)
  
  # Expression mode (starts with 'if')
  if (not result.success) {FAILED += S}
}

# Command mode (doesn't start with keyword or assignment)
ssh server.com -p 8080 -c uname -a
```

### 3. Cross-Mode Features

**Expression Mode → Command Mode:**
- `$rsh(command)` - Execute command from EXPR mode
- Returns captured output as string or result object

**Command Mode → Expression Mode:**
- `${expression}` - Expression interpolation in CMD mode
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

# Command execution from EXPR mode
result = $rsh(ssh $S.fqdn -p $S.port)
output = $rsh(uname -a)
hostname = $rsh(hostname)
```

### Command Mode Triggers

A line enters **Command Mode** if it starts with anything else:

```bash
# Direct commands
ssh server.com -p 8080
echo Hello World
ls -la

# Commands with expression interpolation
ssh ${S.fqdn} -p ${S.port} -c uname -a
echo Server ${S.fqdn} succeeded! Total: ${SUCCESS.length}
cat ${filename}
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
  result = $rsh(ssh $S.fqdn -p $S.port)
}

# Iterate with index (future)
for (i, S) in enumerate(SERVERS) {
  echo "Server ${i}: ${S.fqdn}"
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
  result = $rsh(check_status)
  ready = result.success
}
```

### Command Execution with $rsh()

Execute commands from Expression mode and capture output:

```bash
# Basic execution
hostname = $rsh(hostname)
files = $rsh(ls -la)
user = $rsh(whoami)

# Multiple executions
user = $rsh(whoami) and host = $rsh(hostname)

# In assignments
result = $rsh(ssh $S.fqdn -p $S.port)

# With result object (when assigned)
result = $rsh(ssh server.com uname -a)
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

# With redirection (planned)
echo "hello" > output.txt
echo "world" >> output.txt
grep "pattern" < input.txt
command (stderr)> errors.txt
command (stderr+stdout)> all_output.txt
```

### Expression Interpolation with ${}

Inject expression values into commands:

```bash
# Property access
ssh ${S.fqdn} -p ${S.port} -c uname -a
cat ${CONFIG.logfile}
mkdir ${BASE_PATH}/subdir

# String expressions
echo Server ${S.fqdn} succeeded!
echo Total successful: ${SUCCESS.length}
curl https://${HOST}:${PORT}/api

# Complex expressions
echo Processing item ${i+1} of ${ITEMS.length}
ssh ${SERVERS[0].fqdn} whoami
```

### Variable References in Commands

Use variables in command mode:

```bash
# Standard variable reference
echo $USER
cat $FILENAME

# Expression interpolation
echo ${S.fqdn}
ssh ${S.fqdn} -p ${S.port}
```

### Variable References

```bash
# $ syntax for variable references
echo $NAME
ssh $HOST -p $PORT
cat $FILENAME

# ${} syntax for expressions
echo ${S.fqdn}
ssh ${S.fqdn} -p ${S.port}
```

### File Redirection (Planned)

RShell will use a more explicit syntax for redirection:

```bash
# Standard output
echo "hello" > file.txt          # Overwrite
echo "world" >> file.txt          # Append

# Standard input
grep "pattern" < input.txt

# Error streams with explicit syntax
command (stderr)> errors.txt                # Stderr only
command (stderr+stdout)> all_output.txt     # Both streams

# Command chaining
command1 && command2    # Run if success
command1 || command2    # Run if failure
command1 ; command2     # Run regardless
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
  result = $rsh(ssh $S.fqdn -p $S.port echo ok)
  
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
  echo ${S.fqdn} succeeded! Total: ${SUCCESS.length} of ${SERVERS.length}
  
  # Command mode - SSH command
  ssh ${S.fqdn} -p ${S.port} -c uname -a
}

# Expression mode - report failures
if (FAILED.length > 0) {
  for S in FAILED {
    # Command mode
    echo FAILED: ${S.fqdn}
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

# Expression mode - read log (command execution)
LINES = $rsh(cat $LOGFILE).stdout.split('\n')

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
echo Total errors: ${ERROR_COUNT}
echo Total warnings: ${WARNING_COUNT}

# Expression mode - show details
if (ERROR_COUNT > 0) {
  for ERR in ERRORS {
    # Command mode
    echo ERROR: ${ERR}
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
  echo Deploying ${VERSION} to ${S.fqdn} (${S.role})
  
  # Expression mode - copy files
  result = $rsh(rsync -avz ./dist/ ${S.fqdn}:/app/)
  
  if (not result.success) {
    # Command mode
    echo FAILED to copy files to ${S.fqdn}
    continue
  }
  
  # Expression mode - restart service
  restart_result = $rsh(ssh ${S.fqdn} systemctl restart app)
  
  if (restart_result.success) {
    # Command mode
    echo SUCCESS: ${S.fqdn} deployed and restarted
  } else {
    # Command mode
    echo FAILED: ${S.fqdn} restart failed
  }
}

# Command mode - final message
echo Deployment complete for version ${VERSION}
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

### Phase 3: Cross-Mode Features (Completed)

**Goal**: Command execution and interpolation

**Grammar Features**:
- `$rsh(command)` - Execute command from EXPR mode
- `${expression}` - Interpolation in CMD mode
- Path literals: `/bin/ls`, `./script.sh`
- Result object (`.success`, `.stdout`, `.stderr`, `.exit_code`)

**Completed Features**:
- ✅ $rsh() command execution
- ✅ ${} interpolation in commands
- ✅ Path literal support
- ✅ Property access
- ✅ Result objects

**Test Cases**:
```bash
result = $rsh(ls -la)
echo Status: ${result.exit_code}
ssh ${S.fqdn} -p ${S.port} whoami
user = $rsh(whoami) and host = $rsh(hostname)
```

### Phase 4: Redirection & Command Chaining (Planned)

**Goal**: File redirection and command sequencing

**Planned Features**:
- Output redirection: `>`, `>>`
- Input redirection: `<`
- Error redirection: `(stderr)>`, `(stderr+stdout)>`
- Command chaining: `&&`, `||`, `;`

**Test Cases**:
```bash
echo "hello" > output.txt
echo "world" >> output.txt
grep "pattern" < input.txt
command (stderr)> errors.txt
test -f file && echo "exists" || echo "not found"
```

---

## Grammar Development Strategy

### Key Rules

1. **Start-of-line detection** determines mode
   - `IDENTIFIER =`, `IDENTIFIER +=`, `IDENTIFIER -=` → Expression mode
   - `if`/`for`/`while`/`elif`/`else` → Expression mode
   - Everything else → Command mode

2. **No mode keywords needed**
   - No `cmd:` or `expr:` prefixes
   - Natural, readable syntax

3. **Clear interpolation syntax**
   - Expression mode: `$rsh(command)` for command execution
   - Command mode: `${expr}` for expression interpolation
   - Scanner tracks context with brace/bracket counting

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
   - `$rsh()` command execution from EXPR mode
   - `${}` interpolation in CMD mode
   - Result objects
   - Path literals

---

## Timeline Summary

| Phase | Duration | Status | Deliverable |
|-------|----------|--------|-------------|
| 1 | 1 week | ✅ Complete | Mode switching + data structures |
| 2 | 1 week | ✅ Complete | Automatic mode detection + control flow + expressions |
| 3 | 1 week | ✅ Complete | $rsh() execution + ${} interpolation + path literals |
| 4 | 1 week | 📋 Planned | File redirection + command chaining |
| **Total** | **4 weeks** | **Phase 3** | **Core RShell syntax complete** |

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

**Last Updated**: 2025-11-18
**Current Phase**: Phase 3 Complete - Command execution with $rsh() syntax
**Completed**: All core syntax features including $rsh() execution, ${} interpolation, and path literals
**Next**: Phase 4 - File redirection with explicit syntax: `(stderr)>`, `(stderr+stdout)>`
