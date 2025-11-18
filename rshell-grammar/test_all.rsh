# Test 1: $rsh() in EXPR mode
result = $rsh(ls -la)

# Test 2: ${} in CMD mode  
echo "User: ${user}"

# Test 3: $() in CMD mode
echo $(whoami)
