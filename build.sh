#!/bin/bash

# build.sh - Build script for RShell project
# This script handles the complete build process for the RShell Elixir project
# including Rust NIF compilation and Elixir dependency management.

set -e  # Exit on any error

echo "🚀 Starting RShell build process..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Check if required tools are available
check_dependencies() {
    print_status $YELLOW "🔍 Checking dependencies..."
    
    # Check Elixir
    if ! command -v elixir &> /dev/null; then
        print_status $RED "❌ Elixir not found. Please install Elixir."
        exit 1
    fi
    
    # Check Mix
    if ! command -v mix &> /dev/null; then
        print_status $RED "❌ Mix not found. Please install Elixir."
        exit 1
    fi
    
    # Check Rust/Cargo
    if ! command -v cargo &> /dev/null; then
        print_status $RED "❌ Cargo not found. Please install Rust."
        exit 1
    fi
    
    print_status $GREEN "✅ All dependencies found"
}

# Setup tree-sitter-bash
setup_tree_sitter() {
    print_status $YELLOW "🌳 Setting up tree-sitter-bash..."
    
    # Check if vendor/tree-sitter-bash exists
    if [ ! -d "vendor/tree-sitter-bash" ]; then
        print_status $YELLOW "📥 Cloning tree-sitter-bash..."
        mkdir -p vendor
        git clone https://github.com/tree-sitter/tree-sitter-bash.git vendor/tree-sitter-bash
        print_status $GREEN "✅ tree-sitter-bash cloned"
    else
        print_status $GREEN "✅ tree-sitter-bash already exists"
    fi
    
    # Check for node-types.json
    if [ ! -f "vendor/tree-sitter-bash/src/node-types.json" ]; then
        print_status $RED "❌ node-types.json not found in vendor/tree-sitter-bash/src/"
        exit 1
    fi
    
    print_status $GREEN "✅ tree-sitter-bash setup complete"
}

# Install Elixir dependencies
install_elixir_deps() {
    print_status $YELLOW "📦 Installing Elixir dependencies..."
    mix deps.get
    print_status $GREEN "✅ Elixir dependencies installed"
}

# Build Rust NIF
build_rust_nif() {
    print_status $YELLOW "🔨 Building Rust NIF..."
    
    # Build the Rust NIF
    if cargo build --manifest-path native/RShell.BashParser/Cargo.toml; then
        print_status $GREEN "✅ Rust NIF built successfully"
    else
        print_status $RED "❌ Failed to build Rust NIF"
        exit 1
    fi
}

# Copy NIF to priv/native
copy_nif() {
    print_status $YELLOW "📂 Copying NIF to priv/native..."
    
    # Create priv/native directory if it doesn't exist
    mkdir -p priv/native
    
    # Determine the correct NIF file to copy based on the platform
    local nif_path=""
    if [ -f "native/RShell.BashParser/target/debug/librshell_bash_parser.so" ]; then
        nif_path="native/RShell.BashParser/target/debug/librshell_bash_parser.so"
    elif [ -f "native/RShell.BashParser/target/debug/librshell_bash_parser.dylib" ]; then
        nif_path="native/RShell.BashParser/target/debug/librshell_bash_parser.dylib"
    elif [ -f "native/RShell.BashParser/target/debug/librshell_bash_parser.dll" ]; then
        nif_path="native/RShell.BashParser/target/debug/librshell_bash_parser.dll"
    else
        print_status $RED "❌ No NIF library file found"
        exit 1
    fi
    
    # Copy the NIF file
    cp "$nif_path" priv/native/
    print_status $GREEN "✅ NIF library copied to priv/native/"
}

# Generate AST types from grammar
generate_ast_types() {
    print_status $YELLOW "🔧 Generating AST types from tree-sitter grammar..."
    
    if mix gen.ast_types; then
        print_status $GREEN "✅ AST types generated successfully"
    else
        print_status $RED "❌ AST type generation failed"
        exit 1
    fi
}

# Compile Elixir project
compile_elixir() {
    print_status $YELLOW "⚙️  Compiling Elixir project..."
    
    if mix compile; then
        print_status $GREEN "✅ Elixir project compiled successfully"
    else
        print_status $RED "❌ Elixir compilation failed"
        exit 1
    fi
}

# Run tests
run_tests() {
    print_status $YELLOW "🧪 Running tests..."
    
    # Test CLI functionality
    print_status $YELLOW "📋 Testing CLI functionality..."
    if mix parse_bash test_script.sh > /dev/null 2>&1; then
        print_status $GREEN "✅ CLI test passed"
    else
        print_status $RED "❌ CLI test failed"
        exit 1
    fi
    
    # Test programmatic functionality
    print_status $YELLOW "🔧 Testing programmatic functionality..."
    if mix run mix_test_programmatic.exs > /dev/null 2>&1; then
        print_status $GREEN "✅ Programmatic test passed"
    else
        print_status $RED "❌ Programmatic test failed"
        exit 1
    fi
    
    print_status $GREEN "✅ All tests passed"
}

# Main build process
main() {
    print_status $GREEN "🔨 RShell Build Script"
    echo "==========================="
    
    # Check dependencies
    check_dependencies
    
    # Setup tree-sitter-bash
    setup_tree_sitter
    
    # Install Elixir dependencies
    install_elixir_deps
    
    # Build Rust NIF
    build_rust_nif
    
    # Copy NIF to priv/native
    copy_nif
    
    # Generate AST types from grammar
    generate_ast_types
    
    # Compile Elixir project
    compile_elixir
    
    # Run tests (optional - remove comment to enable)
    # run_tests
    
    echo "==========================="
    print_status $GREEN "🎉 Build process completed successfully!"
    echo ""
    print_status $YELLOW "📋 Next steps:"
    echo "  - CLI usage: mix parse_bash <script.sh>"
    echo "  - Programmatic: See examples in mix_test_programmatic.exs"
    echo ""
}

# Run main function
main "$@"

# Make script executable with: chmod +x build.sh