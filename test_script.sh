#!/bin/bash

# Test script for RShell
echo "Hello World!"

# Variables and conditionals
NAME="developer"
if [ "$NAME" = "developer" ]; then
    echo "Welcome, $NAME!"
fi

# Loop example
for file in *.ex; do
    echo "Processing $file"
done

# Function definition
function greet() {
    local user=$1
    echo "Hello, $user!"
}

# Function call
greet "test user"