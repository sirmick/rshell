# Build Instructions for RShell

## Quick Build (Recommended)

Use the provided build script for a complete, automated build:

```bash
chmod +x build.sh
./build.sh
```

This single command:
1. ✅ Clones tree-sitter-bash to `vendor/` (if needed)
2. ✅ Installs Elixir dependencies
3. ✅ Builds the Rust NIF
4. ✅ Copies NIF library to `priv/native/`
5. ✅ Generates 59 typed AST structures from grammar
6. ✅ Compiles the Elixir project

## Manual Build Process

If you prefer to build manually, follow these steps:

### 1. Setup Tree-sitter Grammar

```bash
# Clone tree-sitter-bash
git clone https://github.com/tree-sitter/tree-sitter-bash.git vendor/tree-sitter-bash

# Verify node-types.json exists
ls vendor/tree-sitter-bash/src/node-types.json
```

### 2. Install Elixir Dependencies

```bash
mix deps.get
```

### 3. Build Rust NIF

```bash
cargo build --manifest-path native/RShell.BashParser/Cargo.toml
```

### 4. Copy NIF Library

```bash
mkdir -p priv/native
# Platform-specific copy
cp native/RShell.BashParser/target/debug/librshell_bash_parser.* priv/native/
```

### 5. Generate Typed AST Structures

```bash
mix gen.ast_types
```

This reads `vendor/tree-sitter-bash/src/node-types.json` and generates 59 typed Elixir structs in `lib/bash_parser/ast/types.ex`.

### 6. Compile Elixir Project

```bash
mix compile
```

## Platform-Specific Notes

### Linux
- The build produces a `.so` (shared object) file
- Ensure you have Rust and Elixir installed

### macOS
- The build produces a `.dylib` (dynamic library) file
- May require Xcode command line tools: `xcode-select --install`

### Windows
- The build produces a `.dll` (dynamic link library) file
- Requires Microsoft Visual C++ Build Tools or Visual Studio

## Testing the Build

After building, verify everything works:

### Run Test Suite
```bash
mix test
```

All 31 tests should pass, including:
- NIF unit tests
- Typed AST conversion tests
- Nested structure tests

### CLI Test
```bash
mix parse_bash test_script.sh
```

### Interactive Test
```bash
iex -S mix

# Try parsing in the REPL
{:ok, ast} = RShell.parse("echo 'Hello'")
ast.__struct__  # => BashParser.AST.Types.Program
```

## Build Requirements

- **Elixir**: 1.14+ with Mix build tool
- **Rust**: Latest stable version with cargo
- **Git**: For dependency management (if needed)

## Troubleshooting

### NIF Loading Issues
If you get NIF loading errors, verify:
1. The NIF library was copied to `priv/native/`
2. Platform-specific library extension is correct
3. Library file has appropriate permissions

### Build Errors
Check that all dependencies are installed and versions are compatible.

## Build Script Features

The [`build.sh`](build.sh) script includes:
- ✅ Tree-sitter-bash setup (auto-clones if missing)
- ✅ Dependency checking for Elixir, Mix, and Cargo
- ✅ Rust NIF compilation with cargo
- ✅ Platform-aware NIF library copying (.so, .dylib, .dll)
- ✅ AST type generation from grammar
- ✅ Colored output for better visibility
- ✅ Error handling with meaningful messages

## Type Generation Details

### What is Generated

The `mix gen.ast_types` task reads `vendor/tree-sitter-bash/src/node-types.json` and generates:

- **59 typed modules** in `lib/bash_parser/ast/types.ex`
- Each module includes:
  - Strongly-typed struct with `@enforce_keys`
  - Complete `@type` specifications
  - Recursive `from_map/1` conversion function
  - `node_type/0` identifier function

### Regenerating Types

After updating tree-sitter-bash:

```bash
# Pull latest tree-sitter-bash changes
cd vendor/tree-sitter-bash
git pull origin master
cd ../..

# Regenerate types
mix gen.ast_types

# Rebuild and test
mix clean
mix compile
mix test
```

## Architecture

### Data Flow

```
Bash Script
    ↓
[Rust NIF] tree-sitter parser
    ↓
Raw map with "type" field and named fields
    ↓
[BashParser.AST.Types.from_map/1] Recursive conversion
    ↓
Strongly-typed AST structs (59 types)
    ↓
[RShell API] Analysis and manipulation
```

### Key Files

- [`build.sh`](build.sh) - Automated build script
- [`native/RShell.BashParser/src/lib.rs`](native/RShell.BashParser/src/lib.rs) - Rust NIF wrapper
- [`lib/mix/tasks/gen/ast_types.ex`](lib/mix/tasks/gen/ast_types.ex) - Type generator
- [`lib/bash_parser/ast/types.ex`](lib/bash_parser/ast/types.ex) - Generated types (59 modules)
- [`vendor/tree-sitter-bash/src/node-types.json`](vendor/tree-sitter-bash/src/node-types.json) - Grammar schema