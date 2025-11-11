# RShell

RShell provides an Elixir library for parsing Bash scripts into **strongly-typed Abstract Syntax Trees (AST)** using the tree-sitter parsing framework.

## Overview

This project integrates the `tree-sitter-bash` Rust library with Elixir through Rustler, providing native performance parsing capabilities with compile-time type safety for Bash script analysis.

## Features

- **Strongly-Typed AST**: 59 typed Elixir structs auto-generated from tree-sitter grammar
- **Native Performance**: Uses Rust's tree-sitter for fast, incremental parsing
- **Grammar-Driven**: Types are generated directly from `node-types.json` schema
- **Rich AST Output**: Complete syntax tree with named fields and nested structures
- **CLI Interface**: `mix parse_bash` command for command-line usage
- **Programmatic API**: Full Elixir API for script analysis and manipulation
- **Cross-platform**: Works on Linux, macOS, and Windows

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

## Quick Start

The easiest way to build RShell is using the provided build script:

```bash
git clone https://github.com/sirmick/rshell.git
cd rshell
chmod +x build.sh
./build.sh
```

This automatically:
- Sets up tree-sitter-bash grammar
- Installs Elixir dependencies
- Builds the Rust NIF
- Generates 59 typed AST structs from the grammar
- Compiles the Elixir project

For manual build instructions, see [BUILD.md](BUILD.md).

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
# Parse a script string - returns strongly-typed AST
{:ok, ast} = RShell.parse("echo 'Hello World'")

# AST is a typed Program struct
ast.__struct__  # => BashParser.AST.Types.Program

# Access typed fields
[command] = ast.children
command.__struct__  # => BashParser.AST.Types.Command

# Parse from file
{:ok, ast} = RShell.parse_file("my_script.sh")
```

#### Working with Typed AST
```elixir
# All fields are properly typed
script = """
if [ "$USER" = "admin" ]; then
  echo "Admin access"
fi
"""

{:ok, ast} = RShell.parse(script)

# Navigate the typed structure
[if_stmt] = ast.children
if_stmt.__struct__  # => BashParser.AST.Types.IfStatement

# Access named fields
[test_cmd] = if_stmt.condition
test_cmd.__struct__  # => BashParser.AST.Types.TestCommand

# All nested structures are typed
[binary_expr] = test_cmd.children
binary_expr.left  # => %BashParser.AST.Types.String{...}
binary_expr.right  # => [%BashParser.AST.Types.String{...}]
```

#### AST Analysis
```elixir
# Get all commands in the script
commands = RShell.commands(ast)
IO.puts("Found #{length(commands)} commands")

# Get all function definitions
functions = RShell.function_definitions(ast)

# Find specific node types
if_statements = RShell.find_nodes(ast, "if_statement")

# Each returned node is a typed struct
for if_stmt <- if_statements do
  IO.inspect(if_stmt.__struct__)  # => BashParser.AST.Types.IfStatement
end
```

#### Error Handling
```elixir
# Check for parse errors
if RShell.has_errors?("invalid @#$% syntax") do
  IO.puts("Invalid syntax detected")
end
```

#### Type Generation
```elixir
# Regenerate types from grammar (after updating tree-sitter)
mix gen.ast_types
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
1. Tree-sitter-bash is cloned to `vendor/tree-sitter-bash`
2. `mix gen.ast_types` reads `node-types.json` and generates 59 typed structs
3. Rust NIF is built with cargo (integrates tree-sitter parser)
4. Compiled NIF is copied to `priv/native/`
5. Elixir code is compiled with full type information

### Type System
- **59 Auto-generated Modules**: One for each tree-sitter node type
- **Strongly Typed**: Each struct has proper `@type` specs
- **Recursive Conversion**: Maps from NIF are recursively converted to typed structs
- **Named Fields**: All tree-sitter fields are properly extracted (e.g., `condition`, `body`, `left`, `right`)
- **Unnamed Children**: Handled via `children` field for generic child nodes

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

### Automated Build (Recommended)
```bash
chmod +x build.sh
./build.sh
```

### Manual Build
```bash
# Setup tree-sitter-bash
git clone https://github.com/tree-sitter/tree-sitter-bash.git vendor/tree-sitter-bash

# Get dependencies
mix deps.get

# Build Rust NIF
cargo build --manifest-path native/RShell.BashParser/Cargo.toml

# Copy NIF library (platform-specific)
mkdir -p priv/native
cp native/RShell.BashParser/target/debug/librshell_bash_parser.* priv/native/

# Generate typed AST structures
mix gen.ast_types

# Compile Elixir
mix compile
```

## Node Types

The parser provides 59 strongly-typed AST node types, including:

- **Statements**: `IfStatement`, `ForStatement`, `WhileStatement`, `CaseStatement`, `FunctionDefinition`
- **Commands**: `Command`, `CommandName`, `DeclarationCommand`, `TestCommand`
- **Expressions**: `BinaryExpression`, `UnaryExpression`, `TernaryExpression`, `ParenthesizedExpression`
- **Variables**: `VariableAssignment`, `SimpleExpansion`, `VariableName`
- **Literals**: `String`, `StringContent`, `Word`, `Number`, `Comment`
- **Redirects**: `FileRedirect`, `HeredocRedirect`, `HerestringRedirect`
- **And more**: See [`lib/bash_parser/ast/types.ex`](lib/bash_parser/ast/types.ex) for all 59 types

All types are auto-generated from the tree-sitter grammar using `mix gen.ast_types`.

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
