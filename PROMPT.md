# RShell Development Context

## Project Overview
RShell is a modern shell implementation combining Bash compatibility with enhanced type-safe features. It consists of two main components:
1. **RShell Grammar** - Tree-sitter based parser for RShell syntax (Expression/Command modes)
2. **Elixir Runtime** - Execution engine with native type support and structured data

## Critical Paths for Fast Context

### Core Documentation
- `rshell/RSHELL_SYNTAX_DESIGN.md` - RShell language syntax (EXPR/CMD modes)
- `rshell/BUILD.md` - Build instructions and dependencies
- `rshell/TEST_GUIDE.md` - TDD patterns and test organization
- `rshell/RUNTIME_DESIGN.md` - Execution model and PubSub architecture

### Test Infrastructure (USE THESE, DON'T CREATE NEW TEST FILES)
```bash
# Primary test commands - always use these
./build.sh                    # Build everything (grammar + Elixir)
mix test                       # Run full test suite
mix test test/unit/           # Unit tests only
mix test test/integration/    # Integration tests only
mix test.watch                # Continuous testing (TDD mode)
mix cli                        # Interactive CLI for manual testing
python test_cli_automated.py  # Automated CLI integration tests
```

### Grammar Testing (RShell-specific syntax)
```bash
cd rshell-grammar
./build_grammar.sh            # Build and test grammar
python3 tests/test_grammar_simple.py  # 60/62 tests passing (96.8%)
tree-sitter parse examples/rshell/01_server_health_monitor.rsh
```

### Key Source Locations
```
/home/mick/rshell/
├── lib/r_shell/              # Core runtime
│   ├── runtime.ex            # Execution engine
│   ├── cli/                  # CLI state management
│   │   ├── executor.ex       # Command executor
│   │   └── state.ex          # Session state
│   └── builtins/             # Native commands
├── lib/bash_parser/          # AST processing
│   └── ast/                  # AST types and walker
├── rshell-grammar/           # Tree-sitter grammar
│   ├── grammar.js            # Grammar definition
│   └── src/scanner.c         # Mode detection scanner
└── test/                     # Test organization
    ├── unit/                 # Single module tests
    ├── integration/          # Multi-module tests
    └── support/              # Test helpers (CLIHelper)
```

## TDD Workflow (REQUIRED)

### 1. Before ANY Implementation
```bash
# Check existing tests for similar functionality
grep -r "pattern" test/ lib/

# Find the right test file or create one
ls test/unit/         # For single module tests
ls test/integration/  # For feature tests (preferred)
```

### 2. Write Test FIRST
```elixir
# Use CLIHelper for integration tests (preferred)
defmodule RShell.Integration.YourFeatureTest do
  use ExUnit.Case, async: true
  import RShell.TestSupport.CLIHelper

  test "your feature behavior" do
    script = """
    # Your test case
    echo "test"
    """
    
    state = assert_cli_success(script)
    # Verify behavior
  end
end
```

### 3. Run Test (Should Fail)
```bash
mix test test/integration/your_feature_test.exs
```

### 4. Implement Minimal Code
- Make ONLY enough changes to pass the test
- Follow existing patterns in similar modules

### 5. Verify & Refactor
```bash
mix test                      # All tests green
mix format                    # Format code
mix test --cover             # Check coverage
```

## Clean Development Rules

### Temporary Files in temp
- ✅ `temp/debug_*.exs` files
- ✅ `temp/test_*.md` documentation
- ✅ try to avoid ad-hoc test scripts
- ✅ Use existing test infrastructure
- ✅ Keep docs in designated `.md` files

### Follow Module Patterns
```bash
# Before creating new modules, check similar ones
ls lib/r_shell/builtins/      # For new builtins
ls lib/r_shell/cli/           # For CLI features
ls lib/bash_parser/ast/       # For AST processing
```

### Grammar Changes
```bash
cd rshell-grammar
vim grammar.js                # Edit grammar
tree-sitter generate          # Generate parser
./build_grammar.sh            # Build and test
cd ..
./build.sh                    # Rebuild entire project
```

## RShell Syntax Features

### Mode Detection (Automatic)
```rshell
# EXPR mode (assignments, control flow)
SERVERS = [{'fqdn':'a.b.c', 'port':8000}]
for S in SERVERS {
  result = $rsh(ssh $S.fqdn)    # Execute command from EXPR mode
}

# CMD mode (shell commands)
echo Server: ${S.fqdn}          # Expression interpolation in CMD
ssh ${S.fqdn} -p ${S.port}
```

### Key Syntax Elements
- **EXPR Mode**: Infered from keys like lines that start with `X =`, `X +=`, `X -=` `if`, `for`, `while` etc
- **CMD Mode**: Everything else (shell commands)
- **CMD mode in EXPR**: `$rsh(command)` in EXPR mode
- **EXPR mode in CMD**: `${expr}` in CMD mode
- **Switching content is in the scanner.c** And can depend on counting the number of braces, brackets etc
- **Native Types**: Lists `[1,2,3]`, Maps `{'key':'value'}` etc

## Testing Best Practices

### Use Test Helpers
```elixir
# ALWAYS use CLIHelper for new tests
import RShell.TestSupport.CLIHelper

# Simple success check
state = assert_cli_success("echo hello\\n")

# Output verification
assert_cli_output(script, [
  stdout_contains: "expected",
  exit_code: 0
])
```

### Test Organization
- **Unit**: `/home/mick/rshell/test/unit/` - Single module
- **Integration**: `/home/mick/rshell/test/integration/` - Feature tests (PREFERRED)
- **Support**: `/home/mick/rshell/test/support/cli_test_helper.ex` - Main helper

### Common Test Commands
```bash
# Specific test file
mix test test/integration/control_flow_test.exs

# Specific test by line
mix test test/integration/control_flow_test.exs:42

# With tag
mix test --only focus

# Verbose
mix test --trace
```

## Architecture Notes

### Parser Pipeline
1. **Scanner** (`scanner.c`) - Detects EXPR/CMD mode per line
2. **Grammar** (`grammar.js`) - Parses syntax based on mode
3. **AST** - 59 typed Elixir structs from tree-sitter

### Runtime Pipeline  
1. **IncrementalParser** - Line-by-line parsing
2. **PubSub** - Event broadcasting (`:executable`, `:runtime`, `:output`)
3. **Runtime** - Executes AST nodes
4. **Builtins** - Native Elixir implementations

### PubSub Topics
- `session:ID:executable` - Parser → Runtime (executable nodes)
- `session:ID:runtime` - Execution lifecycle events
- `session:ID:output` - stdout/stderr streams
- `session:ID:context` - Environment/directory changes

## Quick Reference

### Build & Test
```bash
./build.sh                    # Full build
mix test                      # Run tests
mix test.watch               # TDD mode
mix cli                      # Interactive shell
```

### Debug Issues
```bash
iex -S mix                   # Interactive Elixir
mix test --trace            # Verbose test output
cd rshell-grammar && tree-sitter parse test.rsh  # Parse debugging
```

### Clean Workspace
```bash
mix clean                    # Clean Elixir build
rm -rf _build priv/native   # Full clean
git clean -fdx              # Remove ALL untracked files (careful!)
```

Remember: Use established infrastructure. Write tests first. Keep workspace clean.