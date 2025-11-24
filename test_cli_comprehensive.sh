#!/bin/bash
# Comprehensive test for CLI error handling

echo "🧪 Testing RShell CLI Error Handling"
echo "======================================"
echo ""

echo "Test 1: Command not found"
echo "Input: sdfgdg"
echo "Expected: ❌ Command not found: sdfgdg"
echo ""
cat << 'EOF' | timeout 5 mix cli 2>&1 | grep -E "(rshell>|❌|Error)" | tail -5
sdfgdg
.quit
EOF

echo ""
echo "Test 2: Testing builtin commands"
echo "Input: echo hello"
echo "Expected: hello"
echo ""
cat << 'EOF' | timeout 5 mix cli 2>&1 | grep -E "(rshell>|hello)" | tail -5
echo hello
.quit
EOF

echo ""
echo "Test 3: Multiple commands"
echo "Input: echo test1, badcmd, echo test2"
echo ""
cat << 'EOF' | timeout 5 mix cli 2>&1 | grep -E "(rshell>|test|❌)" | tail -10
echo test1
badcmd
echo test2
.quit
EOF

echo ""
echo "======================================"
echo "✅ Tests completed!"