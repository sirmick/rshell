# Build Instructions for RShell

This document provides complete instructions for building RShell from source.

## Prerequisites

- Elixir 1.14+ with Mix build tool
- Rust stable (latest version) with cargo
- Git for cloning/updates

## Quick Build

```bash
# 1. Install Elixir dependencies
mix deps.get

# 2. Build Rust NIF
cargo build --manifest-path native/RShell.BashParser/Cargo.toml

# 3. Copy NIF library
mkdir -p priv/native
cp native/RShell.BashParser/target/debug/librshell_bash_parser.* priv/native/

# 4. Compile Elixir
mix compile

# 5. Test the build
mix parse_bash test_script.sh
```

## Development Workflow

```bash
# Start interactive Elixir shell
mix help

# Test parsing
mix test test_script.sh

# Run unit tests
mix test

# Cleanup build artifacts
rm -rf _build priv/native/target
```

## Troubleshooting

### Rustler Version Issues
If you get compatibility errors, update Rustler version in Cargo.toml:
```toml
rustler = "0.32.0"
```

### Missing NIF Library
Ensure the NIF library is copied to priv/native/ after building:
- Linux/macOS: librshell_bash_parser.so or *.dylib
- Windows: librshell_bash_parser.dll

### Compilation Errors
Make sure Rust toolchain is up to date:
```bash
rustup update
```

## Cross-platform Notes

The system supports different platforms through separate NIF binary formats:
- `.so` for Linux
- `.dylib` for macOS  
- `.dll` for Windows

The Elixir code automatically detects and loads the correct platform-specific NIF.