# Build Instructions for RShell

This document provides complete instructions for building RShell from source.

## Prerequisites

- **Elixir**: 1.14+ with Mix build tool (verified working with 1.19.3)
- **Rust**: Latest stable version with cargo (tested with rustler 0.32.0)
- **Git**: For cloning dependencies

## Quick Build (Recommended)

Use the provided build script for a complete, automated build:

```bash
git clone https://github.com/sirmick/rshell.git
cd rshell
chmod +x build.sh
./build.sh
```

This single command:
1. ✅ Checks for required dependencies (Elixir, Mix, Cargo)
2. ✅ Clones tree-sitter-bash to `vendor/` (if needed)
3. ✅ Installs Elixir dependencies
4. ✅ Builds the Rust NIF
5. ✅ Copies NIF library to `priv/native/`
6. ✅ Generates 59 typed AST structures from grammar
7. ✅ Compiles the Elixir project

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
# Platform-specific copy (automatically detects .so, .dylib, or .dll)
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
- May require `build-essential` package

### macOS
- The build produces a `.dylib` (dynamic library) file
- May require Xcode command line tools: `xcode-select --install`
- Ensure Homebrew is up to date if using it for dependencies

### Windows
- The build produces a `.dll` (dynamic link library) file
- Requires Microsoft Visual C++ Build Tools or Visual Studio
- May need to use `cargo build --release` for some configurations

## Testing the Build

After building, verify everything works:

### Run Test Suite
```bash
mix test
```

The comprehensive test suite includes:
- **432 tests** across all components
- **22 doctests** for inline documentation
- NIF unit tests
- Typed AST conversion tests
- Nested structure tests
- AST walker tests
- Parser event tests (24 tests)
- Input buffer tests (51 tests)
- Runtime execution tests
- Builtins tests

All tests should pass (some may be skipped for unimplemented features).

### CLI Test
```bash
mix parse_bash test_script.sh
```

Expected output:
```
Parsing Bash script: test_script.sh
✅ Parse successful!
=
program [1:1 - 24:18] '#!/bin/bash\n\n...'
  comment [1:1 - 1:12] '#!/bin/bash'
  command [4:1 - 4:20] 'echo "Hello World!"'
...
=
AST Summary:
  Commands: 5
  Functions: 1
```

Note: The task shows the filename being parsed before the success message.

### Interactive Test
```bash
iex -S mix

# Try parsing in the REPL
{:ok, ast} = RShell.parse("echo 'Hello'")
IO.inspect(ast.__struct__)  # Verify it's a typed struct

# Try the interactive CLI
RShell.CLI.main([])
# Type commands interactively, use Ctrl+D to exit
```

## Development Workflow

```bash
# Start interactive Elixir shell with project loaded
iex -S mix

# Run unit tests
mix test

# Run specific test file
mix test test/typed_ast_test.exs

# Cleanup build artifacts
mix clean
rm -rf _build priv/native

# Rebuild from scratch
./build.sh
```

## Type Generation Details

### What is Generated

The `mix gen.ast_types` task reads `vendor/tree-sitter-bash/src/node-types.json` and generates:

- **59 typed modules** in `lib/bash_parser/ast/types.ex`
- Node types are categorized into:
  - **11 literals** (string, number, variable, etc.)
  - **6 commands** (command, pipeline, etc.)
  - **18 statements** (if, for, while, case, etc.)
  - **5 expressions** (binary, unary, etc.)
  - **3 redirects** (file, heredoc, etc.)
  - **16 others** (program, comment, etc.)
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

## Troubleshooting

### NIF Loading Issues
If you get NIF loading errors, verify:
1. The NIF library was copied to `priv/native/`
2. Platform-specific library extension is correct (.so/.dylib/.dll)
3. Library file has appropriate permissions: `chmod 755 priv/native/librshell_bash_parser.*`

**Known Warning**: You may see a deprecation warning about single-quoted strings and charlist usage in `lib/bash_parser.ex:22`. This is non-critical and can be fixed by running `mix format --migrate`.

### Rustler Version Issues
The project currently uses:
- `rustler = "0.32.0"` in `Cargo.toml`
- `{:rustler, "~> 0.30.0"}` in `mix.exs`

These versions are compatible. If you encounter issues:
1. Ensure your Rust toolchain is up to date: `rustup update`
2. Clean and rebuild: `mix clean && ./build.sh`

### Missing NIF Library
Ensure the NIF library is copied to `priv/native/` after building:
- Linux/macOS: `librshell_bash_parser.so` or `*.dylib`
- Windows: `librshell_bash_parser.dll`

### Compilation Errors
Make sure Rust toolchain is up to date:
```bash
rustup update
```

### Tree-sitter-bash Missing
If `vendor/tree-sitter-bash` is missing:
```bash
git clone https://github.com/tree-sitter/tree-sitter-bash.git vendor/tree-sitter-bash
```

### Build Fails on Mix Compile
Clean and rebuild:
```bash
mix clean
mix deps.clean --all
mix deps.get
./build.sh
```

## Build Script Features

The [`build.sh`](build.sh) script includes:
- ✅ Dependency checking for Elixir, Mix, and Cargo
- ✅ Tree-sitter-bash setup (auto-clones if missing)
- ✅ Elixir dependency installation (`mix deps.get`)
- ✅ Rust NIF compilation with cargo
- ✅ Platform-aware NIF library copying (.so, .dylib, .dll)
- ✅ AST type generation from grammar (59 types)
- ✅ Elixir project compilation
- ✅ Colored output for better visibility
- ✅ Error handling with meaningful messages
- ✅ Informative next steps after completion

**Note**: The test verification steps in the script are currently commented out but can be enabled if needed.

## Cross-platform Support

The system supports different platforms through separate NIF binary formats:
- `.so` for Linux
- `.dylib` for macOS  
- `.dll` for Windows

The Elixir code automatically detects and loads the correct platform-specific NIF.

## Additional Resources

- [Tree-sitter](https://tree-sitter.github.io/) - The parsing framework
- [Tree-sitter Bash](https://github.com/tree-sitter/tree-sitter-bash) - Bash grammar
- [Rustler](https://github.com/rusterlium/rustler) - Rust/Elixir integration
- [Bash Reference](https://pubs.opengroup.org/onlinepubs/9699919799/utilities/V3_chap02.html) - POSIX shell command language