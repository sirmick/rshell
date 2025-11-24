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
    
    # Check tree-sitter CLI
    if ! command -v tree-sitter &> /dev/null; then
        print_status $YELLOW "⚠️  tree-sitter CLI not found. Grammar will not be built."
        SKIP_GRAMMAR=1
    fi
    
    print_status $GREEN "✅ All dependencies found"
}

# Build RShell grammar (tree-sitter)
build_grammar() {
    if [ "$SKIP_GRAMMAR" = "1" ]; then
        print_status $YELLOW "⏭️  Skipping grammar build (tree-sitter not available)"
        return
    fi
    
    print_status $YELLOW "🌳 Building RShell grammar..."
    
    if [ -f "rshell-grammar/build_grammar.sh" ]; then
        cd rshell-grammar
        ./build_grammar.sh
        cd ..
        print_status $GREEN "✅ RShell grammar built successfully"
    else
        print_status $YELLOW "⚠️  Grammar build script not found, skipping"
    fi
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
    
    # Build the Rust NIF (RShell.Grammar contains the grammar parser NIF)
    if cargo build --manifest-path native/RShell.Grammar/Cargo.toml --release; then
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
    if [ -f "native/RShell.Grammar/target/release/librshell_grammar.so" ]; then
        nif_path="native/RShell.Grammar/target/release/librshell_grammar.so"
    elif [ -f "native/RShell.Grammar/target/release/librshell_grammar.dylib" ]; then
        nif_path="native/RShell.Grammar/target/release/librshell_grammar.dylib"
    elif [ -f "native/RShell.Grammar/target/release/librshell_grammar.dll" ]; then
        nif_path="native/RShell.Grammar/target/release/librshell_grammar.dll"
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
    
    if mix gen.rshell_ast_types; then
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
    
    # Build RShell grammar (tree-sitter)
    build_grammar
    
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
    echo "  - Grammar tests: cd rshell-grammar && python3 tests/test_grammar_simple.py"
    echo ""
}

# Run main function
main "$@"

# Make script executable with: chmod +x build.sh