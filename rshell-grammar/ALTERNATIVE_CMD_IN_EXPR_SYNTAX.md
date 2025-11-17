# Alternative Syntaxes for Commands in Expression Mode

## Problem Statement
- Need to execute shell commands from within EXPR mode lines
- Quoting is cumbersome (especially when commands contain quotes)
- Solution likely requires scanner modifications
- Must be unambiguous and easy to parse

## Alternative Syntax Options

### Option 1: Backtick Operator (Shell-style)
```rshell
# Single backticks for command execution
result = `ls -la`
files = `find . -name "*.txt"`
if (`test -f config.json`) {
    config = `cat config.json`
}
```
**Pros:**
- Familiar from bash/shell scripting
- Single character delimiter
- Clear visual distinction

**Cons:**
- Conflicts with template string syntax
- May need escaping for literal backticks

### Option 2: Dollar-Paren `$(...)` (Bash-style)
```rshell
# Bash-style command substitution
result = $(ls -la)
files = $(find . -name "*.txt")
if ($(test -f config.json)) {
    config = $(cat config.json)
}
```
**Pros:**
- Familiar from bash
- Clear boundaries
- Can handle nested parens with counting

**Cons:**
- Might conflict with variable syntax
- Two-character delimiter

### Option 3: Exclamation Mark Prefix `!`
```rshell
# Exclamation mark indicates shell command
result = !ls -la
files = !find . -name "*.txt"
if (!test -f config.json) {
    config = !cat config.json
}
```
**Pros:**
- Single character
- Visual distinction
- Common in other languages (Julia, IPython)

**Cons:**
- Conflicts with logical NOT operator
- Ambiguous parsing

### Option 4: Special Brackets `<[...]>`
```rshell
# Special bracket combination
result = <[ls -la]>
files = <[find . -name "*.txt"]>
if (<[test -f config.json]>) {
    config = <[cat config.json]>
}
```
**Pros:**
- Unambiguous
- Clear boundaries
- Unlikely to conflict

**Cons:**
- More typing
- Less familiar syntax

### Option 5: Double Backticks ``` `` ... `` ```
```rshell
# Double backticks for raw commands
result = ``ls -la``
files = ``find . -name "*.txt"``
if (``test -f config.json``) {
    config = ``cat config.json``
}
```
**Pros:**
- Different from template strings (single backticks)
- Clear distinction
- Symmetrical

**Cons:**
- Could be confused with template strings
- Four characters total for delimiters

### Option 6: Pipe Brackets `|[...]|`
```rshell
# Pipe-bracket combination
result = |[ls -la]|
files = |[find . -name "*.txt"]|
if (|[test -f config.json]|) {
    config = |[cat config.json]|
}
```
**Pros:**
- Visually distinct
- Pipe symbol relates to shell
- Unambiguous

**Cons:**
- More typing
- New syntax to learn

### Option 7: Command Block After Equals `= >`
```rshell
# Special => operator starts command mode
result => ls -la
files => find . -name "*.txt"
# For conditionals, still need some delimiter
if ($(test -f config.json)) {
    config => cat config.json
}
```
**Pros:**
- Clean for assignments
- Minimal syntax

**Cons:**
- Only works for assignments
- Doesn't help with conditionals

### Option 8: Inline Mode Switch `#!`
```rshell
# Hash-bang switches to command mode for rest of expression
result = #! ls -la
files = #! find . -name "*.txt"
if (#! test -f config.json) {
    config = #! cat config.json
}
```
**Pros:**
- Clear mode switch indicator
- Relates to shebang

**Cons:**
- Could conflict with comments
- Two characters

## Recommended Solution: `$(...)` Syntax

After analysis, I recommend the **`$(...)`** syntax for these reasons:

1. **Familiarity**: Bash users already know this syntax
2. **Clear boundaries**: Parentheses provide unambiguous start/end
3. **Scanner implementation**: Can track paren depth in scanner
4. **Nesting support**: Can handle commands with parens inside
5. **No quote conflicts**: Commands can use quotes freely

### Implementation Details

**Scanner modifications needed:**
```c
// In scanner.c
case '$':
    if (peek() == '(') {
        advance();  // consume '('
        int paren_depth = 1;
        while (paren_depth > 0 && !eof()) {
            char c = advance();
            if (c == '(') paren_depth++;
            else if (c == ')') paren_depth--;
        }
        return COMMAND_SUBSTITUTION;
    }
    // ... handle regular $ for variables
```

**Grammar rule:**
```javascript
command_substitution: $ => seq(
    '$(',
    $.command_text,  // Raw command text captured by scanner
    ')'
),
```

### Usage Examples
```rshell
# Basic usage
files = $(ls -la)
user = $(whoami)

# With quotes in command
result = $(grep "error" /var/log/syslog)
json = $(curl -H "Content-Type: application/json" https://api.example.com)

# In conditionals  
if ($(test -f "config.json")) {
    config = $(cat config.json)
}

# With pipes and redirects
processes = $(ps aux | grep python | wc -l)
output = $(echo "test" > /tmp/file && cat /tmp/file)

# Nested in expressions
count = len($(ls).split("\n"))
exists = $(test -f file.txt) == ""  # empty output means success

# Multiple on one line
backup = $(cp file.txt file.bak) and log = $(echo "Backed up" >> log.txt)
```

## Alternative: Minimal Scanner Change with `@{...}`

If `$()` conflicts too much with existing syntax, `@{...}` could work:

```rshell
result = @{ls -la}
if (@{test -f config.json}) {
    data = @{cat config.json}
}
```

**Pros:**
- `@` is less commonly used
- Clear visual marker
- Braces are familiar for interpolation

**Cons:**
- Less familiar than `$()`
- New syntax to learn

## Conclusion

The `$(...)` syntax provides the best balance of:
- Familiarity (bash users know it)
- Implementation feasibility (scanner can track parens)
- No quoting issues (commands can use quotes freely)
- Clear boundaries (unambiguous start/end)

The scanner would need to recognize `$(` as a special token and consume everything until the matching `)`, handling nested parentheses correctly.