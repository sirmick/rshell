# RShell

**A modern, type-safe Bash shell implementation in Elixir with native data structure support.**

RShell is an interactive Bash shell that extends traditional shell capabilities with **native type preservation**, **JSON-aware variables**, and **structured data iteration**. Built on tree-sitter parsing and strongly-typed AST structures, RShell provides bash compatibility while enabling powerful data processing workflows.

## Why RShell?

Traditional bash shells treat everything as strings. RShell preserves **native Elixir data types** throughout execution, enabling:

- **Native Type Variables**: Store maps, lists, and numbers—not just strings
- **Structured Data Iteration**: `for i in [1,2,3]` iterates over numbers, not strings
- **JSON-Aware Builtins**: Pass structured data between commands without serialization
- **Type Preservation Boundaries**: Automatic conversion only where needed (concatenation, external commands)

### Quick Example

```bash
# Traditional bash: everything is strings
export DATA="[1,2,3]"
for i in $DATA; do echo $i; done
# Output: [1,2,3]  (treats entire string as one value)

# RShell: native type preservation
export DATA=[1,2,3]
for i in $DATA; do echo $i; done
# Output: 1, 2, 3  (iterates over list elements)
```

## Overview

RShell combines tree-sitter-bash parsing with an execution runtime to create a functional shell with **native type support** and **bracket notation** for nested data access. It demonstrates real-time incremental parsing, automatic execution of complete commands, builtin command support, and observable execution through PubSub events.

## Features

### 🎯 Native Type System
- **Type Preservation**: Variables store native Elixir types (maps, lists, numbers, booleans)
- **Bracket Notation**: Access nested map keys and list indices with `$VAR["key"]` or `$VAR[0]` syntax
- **Smart Boundaries**: Automatic conversion only at string boundaries (concatenation, external commands)
- **JSON Support**: Parse and emit JSON directly in environment variables
- **Structured Iteration**: For loops iterate over list elements, not split strings

### 🚀 Parser
- **Strongly-Typed AST**: 59 typed Elixir structs auto-generated from tree-sitter grammar
- **Incremental Parsing**: Line-by-line parsing with incomplete structure detection
- **Native Performance**: Rust-based tree-sitter for fast parsing
- **Event-Driven**: PubSub broadcasts for AST updates and executable nodes

### ⚙️ Runtime & Execution
- **Native Type Builtins**: Commands receive and return structured data
- **Builtin Commands**: Native Elixir implementations (echo, export, env, pwd, cd, true, false, printenv, man)
- **Execution Modes**: Simulate, capture, and real (stub) modes
- **Context Management**: Rich environment with native type support, working directory, exit codes
- **Observable Execution**: PubSub events for execution lifecycle and output

### 💻 CLI
- **Interactive Shell**: REPL with real-time parsing and execution
- **Command History**: Multi-line input with incremental feedback
- **Debug Commands**: `.ast`, `.status`, `.reset` for inspection
- **Fast Response**: Immediate command execution with builtin support

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

### Interactive Shell (CLI)

Start the interactive shell:
```bash
# Via mix
mix run -e "RShell.CLI.main([])"

# Or build and run escript
mix escript.build
./rshell
```

Example session with **native type support**:
```
🐚 RShell - Interactive Bash Shell
==================================================
Type bash commands. Built-in commands start with '.'
Type .help for available commands

✅ Parser started (PID: #PID<0.123.0>)
✅ Runtime started (PID: #PID<0.124.0>)
📡 Session ID: cli_123456
🎬 Mode: simulate

rshell> export DATA=[1,2,3]
✓ DATA=[1, 2, 3]

rshell> echo $DATA
[1, 2, 3]

rshell> for i in $DATA; do echo "Number: $i"; done
Number: 1
Number: 2
Number: 3

rshell> export USER={"name":"Alice","age":30}
✓ USER={"name":"Alice","age":30}

rshell> echo $USER
{"name":"Alice","age":30}

rshell> .quit
👋 Goodbye!
```

### Native Type Examples

**Lists**:
```bash
# Store a list
export NUMS=[10,20,30]

# Iterate over elements (not string split!)
for n in $NUMS; do
  echo "Value: $n"
done
# Output:
# Value: 10
# Value: 20
# Value: 30

# Access by index with bracket notation
echo $NUMS[0]
# Output: 10

echo $NUMS[2]
# Output: 30
```

**Maps/Objects**:
```bash
# Store structured data
export CONFIG={"host":"localhost","port":8080}

# Pass to builtins as native map
echo $CONFIG
# Output: {"host":"localhost","port":8080}

# Access nested keys with bracket notation
echo $CONFIG["host"]
# Output: localhost

echo $CONFIG["port"]
# Output: 8080

# String concatenation converts to JSON
echo "Server: "$CONFIG["host"]
# Output: Server: localhost
```

**Nested Structures with Bracket Notation**:
```bash
# Store nested configuration
export SETTINGS={"database":{"host":"localhost","port":5432},"cache":{"ttl":3600}}

# Access deeply nested values
echo $SETTINGS["database"]["host"]
# Output: localhost

echo $SETTINGS["database"]["port"]
# Output: 5432

echo $SETTINGS["cache"]["ttl"]
# Output: 3600

# Mix list and map access
export APPS=[{"name":"frontend","port":3000},{"name":"backend","port":4000}]

echo $APPS[0]["name"]
# Output: frontend

echo $APPS[1]["port"]
# Output: 4000
```

**Type Boundaries**:
```bash
# Native types preserved in variable expansion
export A=[1,2,3]
echo $A              # [1, 2, 3] (native list formatted)

# Bracket notation preserves types
echo $A[0]           # 1 (native number)

# Concatenation forces string conversion
echo "Data: "$A      # Data: [1,2,3] (JSON string)

# For loops iterate native lists
for i in $A; do echo $i; done
# Output: 1, 2, 3 (numbers, not "[1,2,3]" as string)
```

### CLI Commands

- `.help` - Show available commands
- `.status` - Show parser and runtime status
- `.ast` - Display current AST structure
- `.reset` - Clear parser state
- `.quit` - Exit the shell

### Parse a Script File

Parse bash scripts from the command line:
```bash
mix parse_bash script.sh
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

#### Builtin Execution
```elixir
# Builtins are automatically invoked by the runtime
alias RShell.Builtins

# Execute echo directly
{new_context, stdout, stderr, exit_code} =
  Builtins.shell_echo(["hello", "world"], "", %{})

# stdout => "hello world\n"
# exit_code => 0

# Check if command is a builtin
Builtins.is_builtin?("echo")  # => true
Builtins.is_builtin?("ls")    # => false
```

#### Execution Modes

**`:simulate` mode (default)** - Safe execution for testing
```elixir
{:ok, runtime} = Runtime.start_link(
  session_id: "test",
  mode: :simulate,  # Builtins execute, external commands are logged
  auto_execute: true
)

# Builtin commands execute normally
# External commands show: [SIMULATED] ls -la
```

**`:capture` mode** - Alternative simulation format
```elixir
Runtime.set_mode(runtime, :capture)
# External commands show: [CAPTURED] ls -la
```

**`:real` mode** - Real execution (stub, not implemented)
```elixir
Runtime.set_mode(runtime, :real)
# Would execute external commands via ports
# Currently shows: [WOULD EXECUTE] ls -la
```

#### Error Handling
```elixir
# Check for parse errors
if RShell.has_errors?("invalid @#$% syntax") do
  IO.puts("Invalid syntax detected")
end

# Runtime errors set exit code
context = Runtime.get_context(runtime)
context.exit_code  # => 0 for success, non-zero for errors
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

## How To

### Running Tests

Run the complete test suite:
```bash
# All tests
mix test

# Specific test file
mix test test/incremental_parser_nif_test.exs

# With verbose output
mix test --trace

# Run only tests matching a pattern
mix test --only tag_name
```

### Using the CLI

Parse bash scripts from the command line:
```bash
# Parse a file
mix parse_bash script.sh

# Parse with verbose output
mix parse_bash script.sh --verbose

# Example output shows typed AST structure
mix parse_bash test_script.sh
```

### Regenerating AST Types

After updating tree-sitter-bash grammar:
```bash
# 1. Update tree-sitter-bash
cd vendor/tree-sitter-bash
git pull origin master
cd ../..

# 2. Regenerate 59 typed structs from node-types.json
mix gen.ast_types

# 3. Recompile and test
mix clean
mix compile
mix test
```

This reads `vendor/tree-sitter-bash/src/node-types.json` and generates:
- 59 typed modules in `lib/bash_parser/ast/types.ex`
- Each with `@type` specs, `from_map/1` conversion, and `node_type/0` identifier

### Building the NIF

Compile the Rust NIF bridge:
```bash
# Build in debug mode
cargo build --manifest-path native/RShell.BashParser/Cargo.toml

# Build in release mode (faster, larger binary)
cargo build --release --manifest-path native/RShell.BashParser/Cargo.toml

# Copy to priv/native/ (required for Elixir to load it)
mkdir -p priv/native
cp native/RShell.BashParser/target/debug/librshell_bash_parser.* priv/native/

# Or use the automated build script
./build.sh
```

Platform-specific library extensions:
- Linux: `.so` (shared object)
- macOS: `.dylib` (dynamic library)
- Windows: `.dll` (dynamic link library)

### Interactive Testing

Test the implementation in IEx (Interactive Elixir):
```bash
# Start IEx with the project loaded
iex -S mix

# Parse and inspect
{:ok, ast} = RShell.parse("echo 'Hello'")
ast.__struct__  # => BashParser.AST.Types.Program

# Explore typed fields
[command] = ast.children
command.__struct__  # => BashParser.AST.Types.Command
```

## Dependencies

- **Elixir**: 1.14+ with Mix build tool
- **Rust**: Latest stable Rust with cargo
- **tree-sitter-bash**: Embedded via git subtree in `vendor/tree-sitter-bash`

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
