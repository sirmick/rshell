# Unit Tests Documentation

This document provides detailed coverage of RShell's unit test suite, organized by module.

---

## Overview

**Total Unit Tests**: 7 test files covering core modules  
**Test Pattern**: Silent success (no output on pass), verbose failure (full diagnostics on failure)  
**Async Policy**: Most tests run async, except where noted  
**Global Timeout**: 2 seconds per test (configured in [`test/test_helper.exs`](test/test_helper.exs:1))

---

## Test Files

### 1. [`test/unit/input_buffer_test.exs`](test/unit/input_buffer_test.exs:1) (51 tests)

Tests the [`RShell.InputBuffer`](lib/r_shell/input_buffer.ex:1) module, which performs lightweight lexical analysis to detect when input is complete or needs continuation.

#### Test Coverage

**Line Continuations** (4 tests):
- Complete commands without backslash
- Incomplete commands with trailing backslash
- Backslash-newline sequences
- Multi-line commands with resolved continuations

**Quote Handling** (7 tests):
- Balanced single quotes
- Balanced double quotes
- Unclosed single/double quotes
- Escaped quotes within strings
- Nested quotes (different types)
- Properly closed nested quotes

**Heredoc Handling** (5 tests):
- Commands without heredocs
- Incomplete heredocs (missing end marker)
- Complete heredocs with end marker
- Dash syntax (`<<-EOF`)
- Complete dash-syntax heredocs

**For Loops** (5 tests):
- Incomplete without `do`
- Incomplete with semicolon but no `do`
- Complete single-line for loops
- Incomplete with `do` but no `done`
- Complete multi-line for loops

**While Loops** (3 tests):
- Incomplete without `do`
- Complete with `do` and `done`
- Incomplete with `do` but no `done`

**Until Loops** (2 tests):
- Incomplete without `do`
- Complete with `do` and `done`

**If Statements** (6 tests):
- Incomplete without `then`
- Incomplete with `then` but no `fi`
- Complete if statements
- Multi-line if statements
- If-else statements
- If-elif-else statements

**Case Statements** (3 tests):
- Incomplete without `esac`
- Complete single-line case
- Multi-line case statements

**Nested Structures** (4 tests):
- Nested for loops (incomplete inner)
- Nested for loops (complete)
- For loop inside if (incomplete)
- For loop inside if (complete)

**Continuation Type Detection** (6 tests):
- `:complete` for finished commands
- `:line_continuation` for backslash
- `:quote_continuation` for unclosed quotes
- `:heredoc_continuation` for unclosed heredocs
- `:structure_continuation` for open for loops
- `:structure_continuation` for open if statements

**Edge Cases** (6 tests):
- Empty strings (complete)
- Whitespace-only strings (complete)
- Comments (complete)
- Commands with inline comments (complete)
- Backslash in single quotes (doesn't escape)
- Multiple commands on one line (complete)

#### Key Functions Tested

- [`ready_to_parse?/1`](lib/r_shell/input_buffer.ex:1) - Main continuation detection
- [`continuation_type/1`](lib/r_shell/input_buffer.ex:1) - Identifies continuation type

---

### 2. [`test/unit/error_classifier_test.exs`](test/unit/error_classifier_test.exs:1) (14 tests)

Tests the [`RShell.ErrorClassifier`](lib/r_shell/error_classifier.ex:1) module, which distinguishes syntax errors from incomplete structures in parsed ASTs.

**Async**: `false` (uses shared [`IncrementalParser`](lib/r_shell/incremental_parser.ex:1) GenServer)

#### Test Coverage

**Classification with Typed AST** (7 tests):
- Returns `:complete` for valid commands
- Returns `:syntax_error` for invalid syntax (e.g., `if then fi`)
- Returns `:incomplete` for if without fi
- Returns `:incomplete` for for loop without done
- Returns `:complete` for complete for loops
- Multi-line command building (incomplete → incomplete → complete)
- Distinguishes unclosed quotes (syntax error) from incomplete structures

**Error Node Detection** (3 tests):
- [`has_error_nodes?/1`](lib/r_shell/error_classifier.ex:1) returns false for valid commands
- Returns true for invalid syntax
- Returns false for incomplete but valid structures

**Incomplete Structure Detection** (3 tests):
- [`has_incomplete_structure?/1`](lib/r_shell/error_classifier.ex:1) returns false for complete commands
- Returns true for incomplete if statements
- Returns false for complete if statements

**Structure Identification** (3 tests):
- [`identify_incomplete_structure/1`](lib/r_shell/error_classifier.ex:1) identifies incomplete if (expects "fi")
- Identifies incomplete for loop (expects "done")
- Returns nil for complete commands

**Node Counting** (2 tests):
- [`count_structure_nodes/1`](lib/r_shell/error_classifier.ex:1) counts if statements
- Counts nested structures (both if and for)
- Returns 0 for simple commands

**Error Counting** (2 tests):
- [`count_error_nodes/1`](lib/r_shell/error_classifier.ex:1) returns 0 for valid commands
- Counts ERROR nodes in syntax errors
- Returns 0 for incomplete but valid structures

#### Key Functions Tested

- [`classify/1`](lib/r_shell/error_classifier.ex:1) - Main classification (`:complete | :syntax_error | :incomplete`)
- [`has_error_nodes?/1`](lib/r_shell/error_classifier.ex:1) - Detects ERROR nodes in AST
- [`has_incomplete_structure?/1`](lib/r_shell/error_classifier.ex:1) - Detects incomplete control structures
- [`identify_incomplete_structure/1`](lib/r_shell/error_classifier.ex:1) - Returns `%{type:, expecting:}` or nil
- [`count_structure_nodes/1`](lib/r_shell/error_classifier.ex:1) - Counts control structures
- [`count_error_nodes/1`](lib/r_shell/error_classifier.ex:1) - Counts ERROR nodes

---

### 3. [`test/unit/pubsub_test.exs`](test/unit/pubsub_test.exs:1) (26 tests)

Tests the [`RShell.PubSub`](lib/r_shell/pubsub.ex:1) module, which provides a Phoenix.PubSub wrapper for event-driven communication.

**Async**: `false` (shared PubSub instance)

#### Test Coverage

**PubSub Name** (1 test):
- [`pubsub_name/0`](lib/r_shell/pubsub.ex:1) returns `:rshell_pubsub`

**Topic Generation** (6 tests):
- [`ast_topic/1`](lib/r_shell/pubsub.ex:1) - `"session:{id}:ast"`
- [`executable_topic/1`](lib/r_shell/pubsub.ex:1) - `"session:{id}:executable"`
- [`runtime_topic/1`](lib/r_shell/pubsub.ex:1) - `"session:{id}:runtime"`
- [`output_topic/1`](lib/r_shell/pubsub.ex:1) - `"session:{id}:output"`
- [`context_topic/1`](lib/r_shell/pubsub.ex:1) - `"session:{id}:context"`
- Topics are unique per session

**Subscription (Specific Topics)** (3 tests):
- [`subscribe/2`](lib/r_shell/pubsub.ex:1) to single topic
- Subscribe to multiple topics
- Subscribe to all available topics

**Subscription (:all)** (1 test):
- Subscribe to all topics at once with `:all` atom

**Unsubscription** (2 tests):
- [`unsubscribe/2`](lib/r_shell/pubsub.ex:1) from specific topic
- Unsubscribe from multiple topics

**Broadcasting** (3 tests):
- [`broadcast/3`](lib/r_shell/pubsub.ex:1) to subscribed processes
- Doesn't broadcast to unsubscribed processes
- Broadcasts to multiple subscribers

**Broadcast From** (1 test):
- [`broadcast_from/4`](lib/r_shell/pubsub.ex:1) excludes sender from broadcast

**Session Isolation** (2 tests):
- Messages don't leak between sessions
- Different topics in same session don't interfere

**Message Formats** (5 tests):
- AST update messages: `{:ast_updated, ast}`
- Executable node messages: `{:executable_node, node, id}`
- Runtime execution messages: `{:execution_started | :execution_completed | :execution_failed, id, result}`
- Output messages: `{:stdout | :stderr, text}`
- Context change messages: `{:var_set | :cwd_changed | :function_defined | :alias_defined, ...}`

**Error Handling** (2 tests):
- Invalid topic atoms raise `FunctionClauseError`
- Broadcast succeeds with no subscribers

#### Key Functions Tested

- [`subscribe/2`](lib/r_shell/pubsub.ex:1) - Subscribe to topics (`:all` or list)
- [`unsubscribe/2`](lib/r_shell/pubsub.ex:1) - Unsubscribe from topics
- [`broadcast/3`](lib/r_shell/pubsub.ex:1) - Broadcast message to topic
- [`broadcast_from/4`](lib/r_shell/pubsub.ex:1) - Broadcast excluding sender
- Topic generators for 5 event types

---

### 4. [`test/unit/env_json_test.exs`](test/unit/env_json_test.exs:1) (40 tests)

Tests the [`RShell.EnvJSON`](lib/r_shell/env_json.ex:1) module, which handles JSON parsing/encoding for environment variables.

**Async**: `true`

#### Test Coverage

**Parsing** (18 tests):
- JSON objects (flat and nested)
- JSON arrays (homogeneous and mixed)
- Primitive types (integer, float, boolean true/false, null → nil)
- Quoted strings (valid)
- Error handling (unquoted strings, invalid JSON, malformed JSON)
- Pass-through for already-native values (maps, lists, numbers)

**Encoding** (11 tests):
- Maps to JSON
- Lists to JSON
- Nested structures to JSON
- Strings pass through unchanged
- Numbers to strings (integers, floats)
- Booleans to strings ("true", "false")
- `nil` to empty string
- Atoms to strings
- Charlists to strings

**Formatting** (5 tests):
- [`format/1`](lib/r_shell/env_json.ex:1) pretty-prints maps
- Pretty-prints lists with newlines
- Passes through strings
- Formats numbers
- Handles charlists

**Round-Trip** (3 tests):
- Maps round-trip correctly
- Lists round-trip correctly
- Nested structures round-trip correctly

#### Key Functions Tested

- [`parse/1`](lib/r_shell/env_json.ex:1) - Parse JSON string to Elixir term
- [`encode/1`](lib/r_shell/env_json.ex:1) - Encode Elixir term to JSON string
- [`format/1`](lib/r_shell/env_json.ex:1) - Pretty-print Elixir term

---

### 5. [`test/unit/builtins/helpers_test.exs`](test/unit/builtins/helpers_test.exs:1) (5 tests)

Tests the [`RShell.Builtins.Helpers`](lib/r_shell/builtins/helpers.ex:1) compile-time infrastructure for builtin commands.

**Async**: `false` (tests actual RShell.Builtins module with docstrings)

#### Test Coverage

**Integration with RShell.Builtins** (4 tests):
- [`get_builtin_help/1`](lib/r_shell/builtins.ex:1) returns documentation for echo
- Works with string names (not just atoms)
- Builtins can access options through [`parse_builtin_options/2`](lib/r_shell/builtins/helpers.ex:1) (tests echo -n flag)
- Man builtin displays help using infrastructure
- Man builtin lists all available builtins with `-a` flag

**Compile-Time Function Generation** (1 test):
- Verifies all `shell_*` functions are exported (echo, pwd, cd, export, printenv, man, true, false, env)

#### Key Functions Tested

- [`get_builtin_help/1`](lib/r_shell/builtins.ex:1) - Retrieve help text for builtin
- [`parse_builtin_options/2`](lib/r_shell/builtins/helpers.ex:1) - Parse command-line options
- Compile-time macro expansion that generates builtin wrappers

---

### 6. [`test/unit/builtins/doc_parser_test.exs`](test/unit/builtins/doc_parser_test.exs:1) (19 tests)

Tests the [`RShell.Builtins.DocParser`](lib/r_shell/builtins/doc_parser.ex:1) module, which parses structured docstrings for builtin commands.

**Async**: `true`

#### Test Coverage

**Option Parsing** (14 tests):
- Single boolean option
- Multiple options
- Short-form only options (`-e`)
- Long-form only options (`--verbose`)
- String type options
- Integer type options
- Empty list when no options section
- Multi-line descriptions
- Options with underscores in names (`--no-newline` → `:no_newline`)
- Hyphens converted to underscores (`--enable-escapes` → `:enable_escapes`)

**Help Text Extraction** (3 tests):
- [`extract_help_text/1`](lib/r_shell/builtins/doc_parser.ex:1) extracts complete help text
- Returns empty string for nil doc
- Preserves formatting (indentation, examples)

**Summary Extraction** (5 tests):
- [`extract_summary/1`](lib/r_shell/builtins/doc_parser.ex:1) extracts first line
- Trims whitespace
- Returns empty string for nil/empty doc
- Handles single-line docs

**Integration with Real Builtin Docs** (2 tests):
- Parses echo docstring correctly (3 options: -n, -e, -E)
- Parses pwd docstring correctly (no options)

#### Option Spec Format

Parsed options return maps with:
```elixir
%{
  short: "-n",           # Optional
  long: "--no-newline",  # Optional
  type: :boolean,        # :boolean | :string | :integer
  default: false,        # Type-appropriate default
  key: :no_newline,      # Atom key (hyphens → underscores)
  desc: "Description"    # Help text
}
```

#### Key Functions Tested

- [`parse_options/1`](lib/r_shell/builtins/doc_parser.ex:1) - Extract option specs from docstring
- [`extract_help_text/1`](lib/r_shell/builtins/doc_parser.ex:1) - Extract full help text
- [`extract_summary/1`](lib/r_shell/builtins/doc_parser.ex:1) - Extract first line summary

---

### 7. [`test/unit/builtins/option_parser_test.exs`](test/unit/builtins/option_parser_test.exs:1) (14 tests)

Tests the [`RShell.Builtins.OptionParser`](lib/r_shell/builtins/option_parser.ex:1) module, which parses command-line options at runtime.

**Async**: `true`

#### Test Coverage

**Boolean Options** (6 tests):
- Short flags (`-n`)
- Long flags (`--no-newline`)
- Uses defaults when flag not provided
- POSIX-style parsing (stops at first non-option)
- Multiple flags
- Both short and long names for same option

**String Options** (3 tests):
- Parses value after flag (`-f test.txt`)
- Error when value missing
- Long option with equals syntax (`--file=test.txt`)

**Integer Options** (2 tests):
- Parses integer values (`-c 42`)
- Error for invalid integers

**Separator Handling** (1 test):
- Stops parsing after `--` (treats rest as arguments)

**Unknown Options** (1 test):
- Treats unknown options as regular arguments (permissive parsing)

**Help Formatting** (2 tests):
- [`format_help/4`](lib/r_shell/builtins/option_parser.ex:1) formats help with options
- Formats help without options

#### Return Format

Successful parsing returns:
```elixir
{:ok, options_map, remaining_args}

# Example:
{:ok, %{no_newline: true, enable_escapes: false}, ["hello", "world"]}
```

Error returns:
```elixir
{:error, error_message}

# Example:
{:error, "Option -f requires a value"}
```

#### Key Functions Tested

- [`parse/2`](lib/r_shell/builtins/option_parser.ex:1) - Parse argv with option specs
- [`format_help/4`](lib/r_shell/builtins/option_parser.ex:1) - Generate help text

---

## Test Patterns

### Silent Success Pattern

Tests produce no output when passing:

```elixir
test "complete command without backslash" do
  assert InputBuffer.ready_to_parse?("echo hello")
end
```

✅ Pass: No output  
❌ Fail: Full diagnostic information

### Verbose Failure Pattern

On failure, tests show:
- Full AST structure (for parser tests)
- Execution context (for runtime tests)
- Command history
- Metrics (parse time, execution time)
- Stdout/stderr output

### Async Safety

Tests marked `async: false`:
- [`error_classifier_test.exs`](test/unit/error_classifier_test.exs:2) - Uses shared IncrementalParser GenServer
- [`pubsub_test.exs`](test/unit/pubsub_test.exs:2) - Shared PubSub instance
- [`helpers_test.exs`](test/unit/builtins/helpers_test.exs:2) - Tests actual compiled module

All other tests run in parallel (`async: true`).

### Timeout Protection

Global timeout: **2 seconds per test** (configured in [`test/test_helper.exs`](test/test_helper.exs:1))

Additional CLI helper timeout: **5 seconds** (in integration tests)

---

## Running Tests

```bash
# All unit tests
mix test test/unit/

# Specific test file
mix test test/unit/input_buffer_test.exs

# With verbose output
mix test test/unit/ --trace

# Single test by line number
mix test test/unit/input_buffer_test.exs:8
```

---

## Test Statistics

| Module | File | Tests | Async | Coverage |
|--------|------|------:|-------|----------|
| InputBuffer | [`input_buffer_test.exs`](test/unit/input_buffer_test.exs:1) | 51 | ✅ | Line continuations, quotes, heredocs, control structures, edge cases |
| ErrorClassifier | [`error_classifier_test.exs`](test/unit/error_classifier_test.exs:1) | 14 | ❌ | Classification, error detection, structure identification |
| PubSub | [`pubsub_test.exs`](test/unit/pubsub_test.exs:1) | 26 | ❌ | Topics, subscribe/unsubscribe, broadcast, isolation |
| EnvJSON | [`env_json_test.exs`](test/unit/env_json_test.exs:1) | 40 | ✅ | Parse, encode, format, round-trip |
| Builtins.Helpers | [`helpers_test.exs`](test/unit/builtins/helpers_test.exs:1) | 5 | ❌ | Compile-time infrastructure, help system |
| Builtins.DocParser | [`doc_parser_test.exs`](test/unit/builtins/doc_parser_test.exs:1) | 19 | ✅ | Option parsing, help extraction, summary |
| Builtins.OptionParser | [`option_parser_test.exs`](test/unit/builtins/option_parser_test.exs:1) | 14 | ✅ | Runtime option parsing, help formatting |
| **Total** | **7 files** | **169** | **4/3** | **Complete unit coverage** |

---

## Coverage Gaps

All core unit functionality is covered. The following are intentionally stubbed (tested in integration):
- External command execution (via ports)
- Pipeline execution (`|`, `&&`, `||`)
- Control structure execution (if/for/while/case)
- Command/process substitution
- Redirects (>, <, >>, 2>&1)

These are covered by integration tests in [`test/integration/`](test/integration/).

---

## Related Documentation

- [Integration Tests](test/integration/) - Cross-module tests
- [Test Helpers](test/support/) - Reusable test utilities
- [START_HERE.md](START_HERE.md) - Project overview
- [ARCHITECTURE_DESIGN.md](ARCHITECTURE_DESIGN.md) - System architecture