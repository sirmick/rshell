# START HERE - RShell Development Guide

**A prompt starter for AI-assisted development on the RShell project.**

---

## Project Overview

RShell is an **interactive Bash shell implementation in Elixir** that provides incremental parsing, execution, and a functional CLI using strongly-typed AST structures. The project emphasizes clean architecture, comprehensive testing, and type safety.

### Core Philosophy

- **Test-First Development**: Write tests before implementation
- **Clean Code**: Heavy abstraction, clear separation of concerns
- **Type Safety**: Strongly-typed AST with 59 auto-generated structs
- **Event-Driven**: Loose coupling via Phoenix.PubSub
- **Comprehensive Testing**: 184+ tests covering all layers

---

## Critical Files

### Main Entry Points

1. **[`lib/r_shell.ex`](lib/r_shell.ex)** (305 lines)
   - High-level parsing API
   - AST analysis utilities
   - Entry point for programmatic usage

2. **[`lib/r_shell/cli.ex`](lib/r_shell/cli.ex)** (666 lines)
   - Interactive REPL implementation
   - Multiple execution modes (interactive, file, line-by-line, parse-only)
   - Command history and debug commands

### Core Architecture Components

3. **[`lib/r_shell/incremental_parser.ex`](lib/r_shell/incremental_parser.ex)** (357 lines)
   - GenServer managing incremental parsing state
   - Broadcasts AST updates and executable nodes via PubSub
   - Detects completion and executable nodes

4. **[`lib/r_shell/runtime.ex`](lib/r_shell/runtime.ex)** (477 lines)
   - Execution engine for parsed commands
   - Context management (env vars, cwd, exit codes)
   - Subscribes to parser events, executes nodes

5. **[`lib/r_shell/input_buffer.ex`](lib/r_shell/input_buffer.ex)** (203 lines)
   - Lightweight lexical analysis
   - Detects continuation needs (quotes, heredocs, control structures)
   - No AST analysis required

6. **[`lib/r_shell/builtins.ex`](lib/r_shell/builtins.ex)** (621 lines)
   - Native Elixir implementations of shell builtins
   - 8 implemented: echo, true, false, pwd, cd, export, printenv, man, env
   - Two invocation modes: `:parsed` (with option parser) and `:argv` (raw)

### Type System

7. **[`lib/bash_parser/ast/types.ex`](lib/bash_parser/ast/types.ex)** (1848 lines)
   - **59 auto-generated typed structs** from tree-sitter grammar
   - Strong typing with `@enforce_keys` and `@type` specs
   - ⚠️ **AUTO-GENERATED** - Do not manually edit (except ErrorNode module)

8. **[`lib/bash_parser.ex`](lib/bash_parser.ex)** (114 lines)
   - NIF interface to Rust parser
   - Low-level parsing functions
   - Incremental parsing API

### Rust NIF Layer

9. **[`native/RShell.BashParser/src/lib.rs`](native/RShell.BashParser/src/lib.rs)** (405 lines)
   - Tree-sitter-bash parser wrapper
   - Incremental parsing with tree reuse
   - Converts parse tree to Elixir maps

---

## Important Directories

### `/lib/r_shell/`
Core runtime and execution components:
- `application.ex` - OTP application setup
- `builtins.ex` - Shell builtin implementations
- `cli.ex` - Interactive shell
- `error_classifier.ex` - Distinguishes syntax errors from incomplete structures
- `incremental_parser.ex` - Parser GenServer
- `input_buffer.ex` - Continuation detection
- `pubsub.ex` - Event bus wrapper
- `runtime.ex` - Execution engine

### `/lib/bash_parser/ast/`
AST manipulation and types:
- `types.ex` - 59 auto-generated typed structs ⚠️
- `walker.ex` - AST traversal utilities

### `/test/`
Comprehensive test suite (184+ tests):
- `input_buffer_test.exs` (51 tests) - Continuation detection
- `incremental_parser_pubsub_test.exs` (24 tests) - Parser events
- `pubsub_test.exs` (26 tests) - Event bus
- `builtins_test.exs` - Builtin command tests
- `runtime_test.exs` - Execution engine tests
- `error_classifier_test.exs` (14 tests) - Error classification
- Helper: `test/test_helper.exs` - Shared test utilities

### `/native/RShell.BashParser/`
Rust NIF implementation:
- `src/lib.rs` - Parser implementation
- `Cargo.toml` - Rust dependencies (tree-sitter, rustler)

---

## Architecture Layers

```
┌─────────────────────────────────────────────────────────┐
│              Application Layer (CLI, REPL)              │
│                                                          │
│  ┌────────────────────────────────────────────────────┐ │
│  │   InputBuffer (Continuation Detection)             │ │
│  │   - No AST analysis                                │ │
│  │   - Lightweight lexical checks                     │ │
│  └────────────────────────────────────────────────────┘ │
└────────────────────┬────────────────────────────────────┘
                     │ Complete fragments only
                     ↓
┌─────────────────────────────────────────────────────────┐
│         Phoenix.PubSub (Event Bus)                      │
│   Topics: :ast, :executable, :runtime, :output, :context│
└─────────────────────────────────────────────────────────┘
                     │
            ┌────────┴────────┐
            ↓                 ↓
   ┌─────────────────┐  ┌─────────────────┐
   │ IncrementalParser│  │    Runtime      │
   │   GenServer      │  │   GenServer     │
   │                  │  │                 │
   │ - Rust NIF       │  │ - Execute nodes │
   │ - Broadcast AST  │  │ - Context mgmt  │
   │ - Detect exec    │  │ - Builtins      │
   └─────────────────┘  └─────────────────┘
```

---

## Development Style

### 1. Test-First Approach

Always write tests before implementation:

```elixir
# Example test structure
describe "feature_name" do
  test "describes expected behavior" do
    # Arrange
    input = prepare_input()
    
    # Act
    result = function_under_test(input)
    
    # Assert
    assert result == expected
    assert result.field == specific_value
  end
end
```

### 2. Heavy Abstraction

- Separate concerns into distinct modules
- Use GenServers for stateful components
- Communicate via PubSub events
- Strong typing throughout

### 3. Pattern Matching on Types

```elixir
case node do
  %Types.Command{} -> execute_command(node, context)
  %Types.IfStatement{} -> execute_if_statement(node, context)
  %Types.Pipeline{} -> execute_pipeline(node, context)
end
```

### 4. Comprehensive Error Handling

- Distinguish syntax errors from incomplete structures
- Provide context-aware user feedback
- No silent failures

---

## Key Design Decisions

### Why Separate Parser and Runtime?

| Benefit | Description |
|---------|-------------|
| **Concurrency** | Parse while executing |
| **Flexibility** | Parse-only or execute-only modes |
| **Fault Tolerance** | Independent failure domains |
| **Testing** | Test components in isolation |

**Cost**: +55 KB memory (~9%), +3 μs CPU (0.3%)  
**Verdict**: Negligible overhead, substantial benefits

### Why InputBuffer Before Parser?

- **Prevents ERROR nodes** for incomplete input
- **Lightweight** - no AST analysis required
- **Clean separation** - continuation detection vs parsing
- **Matches bash** - separate lexer/parser phases

### Why Strongly-Typed AST?

| Benefit | Typed Structs | String Types |
|---------|---------------|--------------|
| Type Safety | ✅ Compile-time | ❌ Runtime |
| Performance | ✅ Fast pattern matching | ❌ String comparison |
| IDE Support | ✅ Autocomplete | ❌ None |
| Maintainability | ✅ Clear structure | ❌ Fragile |

---

## Documentation Files

### Essential Reading

1. **[`ARCHITECTURE_DESIGN.md`](ARCHITECTURE_DESIGN.md)** (661 lines)
   - Comprehensive architecture overview
   - Component descriptions
   - Performance characteristics
   - Design decisions with justification

2. **[`BUILD.md`](BUILD.md)** (283 lines)
   - Complete build instructions
   - Platform-specific notes
   - Troubleshooting guide

3. **[`README.md`](README.md)** (411 lines)
   - Quick start guide
   - Usage examples
   - Feature overview
   - API documentation

### Design Documents

4. **[`BUILTIN_DESIGN.md`](BUILTIN_DESIGN.md)** - Builtin command design
5. **[`ENV_VAR_DESIGN.md`](ENV_VAR_DESIGN.md)** - Environment variable handling
6. **[`PIPELINE_DESIGN.md`](PIPELINE_DESIGN.md)** - Pipeline execution design
7. **[`RUNTIME_DESIGN.md`](RUNTIME_DESIGN.md)** - Runtime execution model

---

## Testing Strategy

### Test Coverage by Layer

| Layer | Files | Tests | Purpose |
|-------|-------|-------|---------|
| **Input Buffer** | `input_buffer_test.exs` | 51 | Continuation detection |
| **Parser NIF** | `incremental_parser_nif_test.exs` | 21 | Low-level parsing |
| **Parser Events** | `incremental_parser_pubsub_test.exs` | 24 | Event broadcasting |
| **PubSub** | `pubsub_test.exs` | 26 | Event bus |
| **Error Classification** | `error_classifier_test.exs` | 14 | Error vs incomplete |
| **Runtime** | `runtime_test.exs` | 10 | Execution engine |
| **Builtins** | `builtins_test.exs` | many | Builtin commands |
| **Total** | 6+ main files | **184+** | All layers |

### Running Tests

```bash
# All tests
mix test

# Specific test file
mix test test/input_buffer_test.exs

# With verbose output
mix test --trace

# Run only specific tests
mix test --only tag_name
```

---

## Building the Project

### Quick Build

```bash
./build.sh
```

This automatically:
1. Clones tree-sitter-bash grammar
2. Builds Rust NIF
3. Generates 59 typed AST structs
4. Compiles Elixir project

### Manual Build Steps

See [`BUILD.md`](BUILD.md) for detailed instructions.

---

## Common Development Tasks

### Adding a New Builtin

1. Add function to `lib/r_shell/builtins.ex`
2. Choose invocation mode (`:parsed` or `:argv`)
3. Add docstring with usage and options
4. Write comprehensive tests in `test/builtins_test.exs`
5. Update `BUILTIN_DESIGN.md`

### Modifying AST Types

⚠️ **Do not manually edit `lib/bash_parser/ast/types.ex`**

1. Update tree-sitter-bash grammar (external)
2. Run `mix gen.ast_types`
3. Recompile and test

### Adding Parser Features

1. Write tests in `test/incremental_parser_pubsub_test.exs`
2. Modify `lib/r_shell/incremental_parser.ex`
3. Update `lib/r_shell/runtime.ex` if execution needed
4. Update documentation

---

## Project Status

### Implemented ✅

- Incremental parsing with tree-sitter
- 59 strongly-typed AST structs
- Event-driven architecture (PubSub)
- InputBuffer continuation detection
- Interactive CLI with multi-line input
- 8 builtin commands (echo, cd, export, etc.)
- Comprehensive test suite (184+ tests)

### Stubbed (Not Yet Implemented) ⚠️

- External command execution (via ports)
- Pipeline execution (`|`, `&&`, `||`)
- Control structures (if/for/while/case execution)
- Command substitution
- Process substitution
- Redirects (>, <, >>, 2>&1)

---

## Quick Reference

### File Editing Guidelines

| File Pattern | Edit Policy |
|--------------|-------------|
| `lib/bash_parser/ast/types.ex` | ⚠️ **AUTO-GENERATED** - Do not edit manually |
| `test/*.exs` | ✅ Always add tests first |
| `lib/r_shell/*.ex` | ✅ Clean abstractions, heavy testing |
| `native/RShell.BashParser/src/lib.rs` | ⚠️ Requires Rust rebuild |
| `*.md` | ✅ Keep updated with code changes |

### Key Commands

```bash
# Build
./build.sh

# Test
mix test
mix test --trace

# Run CLI
mix run -e "RShell.CLI.main([])"

# Build escript
mix escript.build
./rshell

# Regenerate types
mix gen.ast_types
```

---

## Getting Help

1. Read [`ARCHITECTURE_DESIGN.md`](ARCHITECTURE_DESIGN.md) for system overview
2. Check [`BUILD.md`](BUILD.md) for build issues
3. Review test files for usage examples
4. Consult design documents for specific subsystems

---

**Remember**: This project prioritizes clean architecture, comprehensive testing, and type safety. Always write tests first, maintain clear separation of concerns, and update documentation alongside code changes.