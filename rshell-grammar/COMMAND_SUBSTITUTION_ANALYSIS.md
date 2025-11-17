# Command Substitution Syntax Analysis: $() Conflict

## The Issue
- `$()` is used for subshells in bash/shell (CMD mode)
- We want to use `$()` for command execution in EXPR mode
- Scanner already tracks modes (EXPR vs CMD)

## Analysis: Is This Actually a Problem?

### In CMD Mode
```rshell
# Traditional bash subshell usage
echo "Today is $(date)"
FILES=$(ls -la | wc -l)
for file in $(find . -name "*.txt"); do
    echo $file
done
```
Here `$()` means: execute command and substitute output

### In EXPR Mode  
```rshell
# Proposed usage
result = $(ls -la)
if ($(test -f config.json)) {
    data = $(cat config.json)
}
```
Here `$()` means: execute command and return result

## Key Insight: They're Actually the Same Thing!

Both uses are **command substitution** - the difference is just the surrounding context:
- **CMD mode**: Substitutes into a command string
- **EXPR mode**: Substitutes into an expression value

## Scanner Implementation

The scanner can handle this cleanly since it already tracks modes:

```c
// In scanner.c
case '$':
    if (peek() == '(') {
        // Same behavior in both modes!
        advance();  // consume '('
        int paren_depth = 1;
        // Consume until matching )
        while (paren_depth > 0 && !eof()) {
            char c = advance();
            if (c == '(') paren_depth++;
            else if (c == ')') paren_depth--;
        }
        return COMMAND_SUBSTITUTION;
    }
    // Handle regular $ for variables
```

The **grammar** interprets it differently based on context:
- In CMD context: Part of command argument
- In EXPR context: Value-returning expression

## Benefits of Unified Syntax

### 1. Consistency
```rshell
# CMD mode
echo "Files: $(ls | wc -l)"

# EXPR mode  
count = $(ls | wc -l)

# Both use the same syntax for the same concept!
```

### 2. Natural Transitions
```rshell
# Start in EXPR mode
files = $(ls *.txt)

# Switch to CMD mode, same syntax works
echo "Found $(ls *.txt | wc -l) text files"
```

### 3. Familiar to Users
- Bash users already know `$()`
- Same mental model in both modes
- No need to learn two different syntaxes

## Comparison with Alternatives

### If we used different syntax (e.g., `@{...}` in EXPR)
```rshell
# Inconsistent - users need to remember which mode
count = @{ls | wc -l}        # EXPR mode
echo "Count: $(ls | wc -l)"  # CMD mode - different!
```

### With unified `$()`
```rshell  
# Consistent - same syntax everywhere
count = $(ls | wc -l)        # EXPR mode
echo "Count: $(ls | wc -l)"  # CMD mode - same!
```

## Edge Cases to Consider

### 1. Nested Command Substitution
```rshell
# CMD mode
echo "Result: $(echo $(date))"

# EXPR mode
result = $(echo $(date))
```
Both work with paren depth tracking!

### 2. Mixed Mode Usage
```rshell
# EXPR mode line with command that contains $()
output = $(echo "Today is $(date)")
```
The scanner captures the whole thing, bash handles the inner $()

### 3. Variable References
```rshell
# $ without ( is still a variable
value = $VAR        # Variable reference
result = $(cmd)     # Command substitution
```

## Recommendation: Use `$()` in Both Modes

**Reasons:**
1. **No real conflict** - It's the same concept in both modes
2. **Consistency** - Same syntax for same operation
3. **Familiarity** - Bash users already know it
4. **Scanner simplicity** - One implementation for both modes
5. **Mental model** - "$(cmd) always runs a command"

**Implementation:**
- Scanner: Recognize `$(` and consume until matching `)`
- Grammar: Allow `command_substitution` in both CMD and EXPR contexts
- Parser: Same AST node, runtime interprets based on context

## Alternative If We Want Distinction

If we absolutely want different syntax for EXPR mode, the best alternative is:

### Backticks for EXPR, $() for CMD
```rshell
# EXPR mode uses backticks
result = `ls -la`
count = `find . | wc -l`

# CMD mode uses $()
echo "Files: $(ls -la)"
```

**But this has issues:**
- Backticks conflict with template strings
- Two syntaxes for the same concept
- More complex to explain/learn

## Conclusion

Using `$()` in both modes is actually the **best solution**:
- It's conceptually consistent
- Scanner implementation is straightforward
- No real conflict - just different contexts
- Users only learn one syntax
- Natural and familiar

The scanner already tracks modes, so it can emit the same token (`COMMAND_SUBSTITUTION`) in both modes, and the grammar handles it appropriately based on context.