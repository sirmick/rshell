# CLI Test Cases for Error Detection

## Test 1: Incomplete `for` loop (ERROR → incomplete → complete)

```bash
# Type each line separately in the CLI:

for i in $a        # Should say: "❌ Syntax error" (missing semicolon + do)
do                 # Should say: "⏳ Waiting for more input: for needs 'done'"
echo yo            # Should say: "⏳ Waiting for more input: for needs 'done'"
done               # Should say: "✨ Ready to execute!"
```

## Test 2: True Syntax Error

```bash
if then fi         # Should say: "❌ Syntax error at line 0: ..."
```

## Test 3: Incomplete `if` statement

```bash
if true; then      # Should say: "⏳ Waiting for more input: if needs 'fi'"
echo hello         # Should say: "⏳ Waiting for more input: if needs 'fi'"
fi                 # Should say: "✨ Ready to execute!"
```

## Test 4: Another Syntax Error

```bash
echo "unclosed     # Should say: "❌ Syntax error..." (unclosed quote)
```

## Test 5: Complete command

```bash
echo "hello world" # Should say: "✨ Ready to execute!"
```

## Test 6: Incomplete while loop

```bash
while true; do     # Should say: "⏳ Waiting for more input: while needs 'done'"
echo hello         # Should say: "⏳ Waiting for more input: while needs 'done'"
done               # Should say: "✨ Ready to execute!"
```

## Test 7: Incomplete case statement

```bash
case $x in         # Should say: "❌ Syntax error" (no pattern)
  *)               # Should say: "⏳ Waiting for more input: case needs 'esac'"
echo hi;;          # Should say: "⏳ Waiting for more input: case needs 'esac'"
esac               # Should say: "✨ Ready to execute!"
```

## How to Run

```bash
cd /home/mick/rshell
mix cli
```

Then type each command and observe the feedback messages!