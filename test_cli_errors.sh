#!/bin/bash
# Test script to verify CLI error handling

echo "Testing CLI error handling..."
echo ""

# Start CLI and test error scenarios
cat << 'EOF' | timeout 5 mix cli || true
sdfgdg
.quit
EOF

echo ""
echo "Test completed!"