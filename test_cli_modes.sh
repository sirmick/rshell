#!/bin/bash
# Test script for CLI modes

echo "Testing RShell CLI modes"
echo "========================"

# Create a simple test script
cat > /tmp/test_script.sh << 'EOF'
echo "Hello from test script"
x=42
echo "x=$x"
EOF

echo ""
echo "1. Testing --parse-only mode"
echo "-----------------------------"
mix run -e "RShell.CLI.main([\"--parse-only\", \"/tmp/test_script.sh\"])"

echo ""
echo "2. Testing file execution mode"
echo "-------------------------------"
mix run -e "RShell.CLI.main([\"/tmp/test_script.sh\"])"

echo ""
echo "3. Testing --line-by-line mode"
echo "-------------------------------"
mix run -e "RShell.CLI.main([\"--line-by-line\", \"/tmp/test_script.sh\"])"

echo ""
echo "4. Testing --help"
echo "-----------------"
mix run -e "RShell.CLI.main([\"--help\"])"

echo ""
echo "All tests complete!"