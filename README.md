# RShell

RShell provides an Elixir library for parsing Bash scripts into Abstract Syntax Trees (AST) using the tree-sitter parsing framework.

## Overview

This project integrates the `tree-sitter-bash` Rust library with Elixir through Rustler, providing native performance parsing capabilities for Bash script analysis.

## Features

- **Native Performance**: Uses Rust's tree-sitter for fast, incremental parsing
- **Rich AST Output**: Complete syntax tree with node types and positions
- **CLI Interface**: `mix parse_bash` command for command-line usage
- **Programmatic API**: Full Elixir API for script analysis and manipulation
- **Cross-platform**: Works on Linux, macOS, and Windows (with separate NIF compilation)

## Project Structure

```
rshell/
├── lib/                          # Elixir code
│   ├── r_shell.ex               # Main API
│   ├── bash_parser.ex           # NIF interface
│   ├── bash_parser/ast.ex        # AST manipulation utilities
│   └── mix/tasks/               # CLI tasks
├── native/RShell.BashParser/     # Rust NIF implementation
│   ├── src/lib.rs              # NIF wrapper around tree-sitter
│   └── Cargo.toml              # Rust dependencies
├── config/
│   └── config.exs              # Rustler configuration
├── vendor/tree-sitter-bash/     # Upstream tree-sitter-bash bindings
└── test_script.sh              # Example script for testing
```

## Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/sirmick/rshell.git
   cd rshell
   ```

2. Install Rust dependencies:
   ```elixir
   mix deps.get
   ```

3. Build the Rust NIF:
   ```bash
   cargo build --manifest-path native/RShell.BashParser/Cargo.toml
   cp native/RShell.BashParser/target/debug/librshell_bash_parser.* priv/native/
   ```

4. Compile the Elixir project:
   ```elixir
   mix compile
   ```

## Usage

### CLI Usage

Parse a Bash script from the command line:
```bash
mix parse_bash script.sh
```

Example output:
```
✅ Parse successful!
=
program [1:1 - 24:18] '#!/bin/bash\n\n...'

  - comment [1:1 - 1:12] '#!/bin/bash'
  - command [4:1 - 4:20] 'echo "Hello World!"'
    - command_name [4:1 - 4:5] 'echo'
      - word [4:1 - 4:5] 'echo'
    - string [4:6 - 4:20] '"Hello World!"'
      - " [4:6 - 4:7] '"'
      - string_content [4:7 - 4:19] 'Hello World!'
      - " [4:19 - 4:20] '"'

AST Summary:
  Commands: 5
  Functions: 1
```

### Programmatic Usage

#### Basic Parsing
```elixir
# Parse a script string
{:ok, ast} = RShell.parse("echo 'Hello World'")
IO.puts(ast.kind)  # "program"

# Parse from file
{:ok, ast} = RShell.parse_file("my_script.sh")
```

#### AST Analysis
```elixir
# Get all commands in the script
commands = RShell.commands(ast)
IO.puts("Found #{length(commands)} commands")

# Get all function definitions
functions = RShell.function_definitions(ast)
IO.puts("Found #{length(functions)} functions")

# Find specific node types
if_statements = RShell.find_nodes(ast, "if_statement")
```

#### Error Handling
```elixir
# Check for parse errors
if RShell.has_errors?("invalid @#$% syntax") do
  IO.puts("Invalid syntax detected")
end
```

## Architecture

### Rust Layer
The Rust NIF layer (`native/RShell.BashParser/src/lib.rs`) provides:
- Tree-sitter parser initialization
- Bash grammar integration from vendor/tree-sitter-bash
- Node-to-Elixir-map conversion
- Error handling for parse failures

### Elixir Layer
The Elixir layer provides:
- **RShell**: High-level API for parsing and analysis
- **BashParser.AST**: AST manipulation utilities
- **CLI Interface**: `mix parse_bash` task for command-line usage

### Build Process
1. Tree-sitter grammar is compiled from `vendor/tree-sitter-bash`
2. Rust NIF is built with cargo
3. Compiled NIF is copied to `priv/native/`
4. Elixir code is compiled and can use the NIF

## Testing

Test the implementation:
```bash
# Run tests
mix test

# Test CLI
mix parse_bash test_script.sh

# Test programmatic usage (start IEx shell)
iex -S mix
```

## Dependencies

- **Elixir**: 1.14+ with Mix build tool
- **Rust**: Latest stable Rust with cargo
- **tree-sitter-bash**: Embedded via git subtree in `vendor/tree-sitter-bash`

## Building from Source

```bash
# Get Rustler dependencies
mix deps.get

# Build Rust NIF
cargo build --manifest-path native/RShell.BashParser/Cargo.toml

# Copy NIF library
mkdir -p priv/native
cp native/RShell.BashParser/target/debug/librshell_bash_parser.so priv/native/

# Compile Elixir
mix compile
```

## Node Types

The parser recognizes these Bash syntax elements:

- **Commands**: `command`, `command_name`, `word`, `string`
- **Control Flow**: `if_statement`, `for_statement`, `while_statement`
- **Functions**: `function_definition`  
- **Variables**: `variable_assignment`, `simple_expansion`
- **Operators**: `binary_expression`, logical operators
- **Literals**: `string_content`, `comment`

## Tree-sitter Integration

The project uses `tree-sitter-bash` from the vendor directory, which provides:
- Complete Bash grammar specification
- Incremental parsing capability
- Position tracking for all nodes
- Support for complex Bash constructs

## License

MIT License - see LICENSE file for details.

## Links

- [Tree-sitter](https://tree-sitter.github.io/) - The parsing framework
- [Tree-sitter Bash](https://github.com/tree-sitter/tree-sitter-bash) - Bash grammar
- [Rustler](https://github.com/rusterlium/rustler) - Rust/Elixir integration
- [Bash Reference](https://pubs.opengroup.org/onlinepubs/9699919799/utilities/V3_chap02.html) - POSIX shell command language
