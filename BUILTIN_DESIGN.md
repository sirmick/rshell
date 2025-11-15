io# RShell Builtin Commands Design

**Last Updated**: 2025-11-12

---

## Overview

Builtin commands are functions implemented in Elixir that execute within the runtime process, rather than spawning external processes. They have access to runtime context and can modify shell state (environment variables, working directory, etc.).

**Implementation Status**:
- ✅ Builtin system with reflection-based discovery
- ✅ Echo builtin with full flag support (-n, -e, -E)
- ✅ AST traversal for command extraction
- ✅ Unified signature for all builtins
- ✅ Comprehensive test coverage across all builtins
- ✅ Integration with Runtime execution flow
- ✅ Docstring-based options parsing and help text generation
- ✅ Compile-time option parser generation from @doc attributes
- ✅ Stream-only I/O design with JSON-based conversion
- ✅ **Module-based namespace system** for organizing builtins
- ✅ **16 implemented builtins**: echo, true, false, pwd, cd, man, env, test, inspect, math:add, math:sub, math:mul, math:div, math:eq, math:neq, math:mod, math:rem

---

## Options Parsing and Help Text

### Design Philosophy

**Low-overhead, declarative approach**: Builtin options and help text are embedded in standard Elixir `@doc` attributes using a structured format.

**At compile time**, the `@before_compile` hook in [`RShell.Builtins.Helpers`](lib/r_shell/builtins/helpers.ex:1) parses these docstrings to generate:
1. `__builtin_options__/1` - Option parser specifications
2. `__builtin_help__/1` - Formatted help text for `man` builtin
3. `__builtin_mode__/1` - Invocation mode (:parsed or :argv)

**At runtime**, [`RShell.Builtins.OptionParser`](lib/r_shell/builtins/option_parser.ex:1) uses the generated specs to parse command-line arguments.

### Docstring Format

```elixir
@doc """
<command_name> - <brief description>

<detailed description paragraph>

Usage: <command_name> [OPTIONS] [ARGS]...

Options:
  <short>, <long>
      type: <type>
      default: <value>
      desc: <description>
  
  <short>, <long>
      type: <type>
      default: <value>
      desc: <description>

<additional sections: Examples, Notes, etc.>

## Examples
    <command> example1
    <command> example2
"""
```

### Example: Echo Builtin

```elixir
@doc """
echo - write arguments to standard output

Write the STRING(s) to standard output separated by spaces and followed by a newline.

Usage: echo [OPTION]... [STRING]...

Options:
  -n, --no-newline
      type: boolean
      default: false
      desc: Do not output the trailing newline
  
  -e, --enable-escapes
      type: boolean
      default: false
      desc: Enable interpretation of backslash escapes
  
  -E, --disable-escapes
      type: boolean
      default: false
      desc: Disable interpretation of backslash escapes (default behavior)

When -e is enabled, the following escape sequences are recognized:
  \\n  newline          \\t  horizontal tab    \\r  carriage return
  \\\\  backslash        \\a  alert (bell)      \\b  backspace
  \\e  escape character \\f  form feed         \\v  vertical tab

## Examples
    echo hello world
    echo -n test
    echo -e "line1\\nline2"
"""
def shell_echo(argv, stdin, context) do
  {:ok, opts, args} = parse_builtin_options(:echo, argv)
  # ... implementation using opts map
end
```

### Implementation Flow

1. **Compile Time** ([`RShell.Builtins.Helpers.__before_compile__/1`](lib/r_shell/builtins/helpers.ex:19)):
   - Scans all `shell_*` functions with arity 3
   - Reads `@shell_*_opts` module attribute for mode (:parsed or :argv)
   - Parses `@doc` attributes using [`DocParser.parse_options/1`](lib/r_shell/builtins/doc_parser.ex:37)
   - Generates private `__builtin_options__(name)` functions returning option specs
   - Generates private `__builtin_help__(name)` functions returning formatted help text
   - Generates private `__builtin_mode__(name)` functions returning invocation mode

2. **Runtime** ([`RShell.Builtins.execute/4`](lib/r_shell/builtins.ex:69)):
   - Checks invocation mode via `__builtin_mode__(name)`
   - **:parsed mode**: Parses options using [`OptionParser.parse/2`](lib/r_shell/builtins/option_parser.ex:68)
     - On success: Calls builtin with `%ParsedOptions{}` struct
     - On error: Calls builtin with `%ParseError{}` struct
   - **:argv mode**: Passes raw argv list directly to builtin
   - `man <builtin>` command retrieves help via `get_builtin_help(name)`

### Invocation Modes

Builtins declare their mode using `@shell_*_opts` attribute:

**:parsed mode** - Automatic option parsing from docstring:
```elixir
@shell_echo_opts :parsed
def shell_echo(%ParsedOptions{} = opts, stdin, context) do
  # opts.options = %{no_newline: true, enable_escapes: false, ...}
  # opts.arguments = ["hello", "world"]
  # opts.argv = ["-n", "hello", "world"]
  output =
    opts.arguments
    |> Enum.join(" ")
    |> maybe_process_escapes(opts.options.enable_escapes)
    |> maybe_add_newline(opts.options.no_newline)
  
  {context, stream(output), stream(""), 0}
end

def shell_echo(%ParseError{} = error, stdin, context) do
  # error.reason = "Unknown option: -z"
  # error.argv = ["-z", "hello"]
  help_text = get_builtin_help("echo")
  stderr = "echo: #{error.reason}\n\n#{help_text}"
  {context, stream(""), stream(stderr), 1}
end
```

**:argv mode** - Raw argument list (for custom parsing):
```elixir
@shell_pwd_opts :argv
def shell_pwd(_argv, _stdin, context) do
  {context, stream(context.cwd <> "\n"), stream(""), 0}
end
```

### Generated Helper Functions (Compile-Time)

The `@before_compile` hook generates these private functions:

```elixir
# Option specs (parsed from docstring)
defp __builtin_options__(:echo) do
  # Reads docstring at runtime via Code.fetch_docs/1
  # Parses via DocParser.parse_options/1
  [
    %{
      short: "-n",
      long: "--no-newline",
      type: :boolean,
      key: :no_newline,
      default: false,
      description: "Do not output the trailing newline"
    },
    # ...
  ]
end

# Help text (extracted from docstring)
defp __builtin_help__(:echo) do
  # Reads docstring at runtime via Code.fetch_docs/1
  # Extracts via DocParser.extract_help_text/1
  """
  echo - write arguments to standard output
  
  Usage: echo [OPTION]... [STRING]...
  
  Options:
    -n, --no-newline        Do not output the trailing newline
  ...
  """
end

# Invocation mode (from @shell_*_opts attribute)
defp __builtin_mode__(:echo), do: :parsed
defp __builtin_mode__(:pwd), do: :argv

# Public helper for man builtin
def get_builtin_help(name) when is_binary(name) do
  __builtin_help__(String.to_atom(name))
end
```

**Note**: Option specs and help text are parsed at runtime from compiled docs, not stored as module attributes. This keeps the compiled beam file smaller.

---

## Namespace System

RShell implements a **module-based namespace system** for organizing builtins. This keeps the codebase manageable and provides clear separation of concerns.

### Architecture

**Main Module**: `RShell.Builtins` - Core builtins and namespace routing
**Namespace Modules**: `RShell.Builtins.*` - Domain-specific builtins

```
RShell.Builtins           # Core: echo, cd, pwd, env, test, inspect, etc.
  ├── Math                # math:add, math:sub, math:mul, math:div, math:eq, math:neq, math:mod, math:rem
  ├── Str (future)        # str:upper, str:lower, str:trim, etc.
  └── Json (future)       # json:parse, json:format, etc.
```

### Usage

**Namespaced commands** use colon (`:`) separator:

```bash
math:add 5 3              # Addition
math:sub 10 3             # Subtraction
math:mul 2 5              # Multiplication
math:div 10 2             # Division
math:eq 5 5               # Equality comparison (returns 1 or 0)
math:neq 5 3              # Inequality comparison (returns 1 or 0)
math:mod 10 3             # Modulo (returns 1)
math:rem 10 3             # Remainder (returns 1)

# Future namespaces:
str:upper "hello"         # String operations
json:parse '{"x":1}'      # JSON operations
```

### Implementation

**1. Namespace Module Structure:**

Each namespace is a separate module using the Helpers with `namespace: true`:

```elixir
defmodule RShell.Builtins.Math do
  @moduledoc "Mathematical operations namespace"
  
  use RShell.Builtins.Helpers, namespace: true
  
  @namespace "math"
  
  def namespace, do: @namespace
  
  @shell_add_opts :argv
  def shell_add(argv, _stdin, context) do
    # Implementation
  end
end
```

**2. Routing in Main Module:**

`RShell.Builtins.execute/4` routes namespaced commands:

```elixir
def execute(name, argv, stdin, context) do
  case String.split(name, ":", parts: 2) do
    [namespace, command] ->
      # Route to RShell.Builtins.Math.shell_add/3
      execute_namespaced(namespace, command, argv, stdin, context)
    
    [_single_name] ->
      # Execute from RShell.Builtins.shell_*/3
      execute_local(name, argv, stdin, context)
  end
end
```

**3. Public Helper Functions:**

Namespace modules use `namespace: true` option, which generates **public** helper functions:

```elixir
# In namespace modules:
def __builtin_options__(name), do: [...]
def __builtin_help__(name), do: "..."
def __builtin_mode__(name), do: :argv | :parsed
```

This allows `RShell.Builtins` to query mode and options from namespace modules.

### Benefits

| Benefit | Description |
|---------|-------------|
| **Modularity** | Each namespace is self-contained |
| **Scalability** | Add namespaces without bloating main module |
| **Organization** | Clear separation by domain |
| **Discoverability** | `math:` prefix makes purpose obvious |
| **No Conflicts** | `add` in math namespace vs `add` in list namespace |

### Adding a New Namespace

1. Create module in `lib/r_shell/builtins/`:

```elixir
defmodule RShell.Builtins.Str do
  use RShell.Builtins.Helpers, namespace: true
  
  @namespace "str"
  def namespace, do: @namespace
  
  @shell_upper_opts :argv
  def shell_upper(argv, _stdin, context) do
    # Implementation
  end
end
```

2. That's it! Automatic discovery and routing.

### Testing Namespaced Builtins

```elixir
# test/unit/builtins/str_test.exs
test "str:upper converts to uppercase" do
  {_ctx, stdout, _stderr, exit_code} =
    Builtins.execute("str:upper", ["hello"], "", @empty_context)
  
  assert Enum.to_list(stdout) == ["HELLO"]
  assert exit_code == 0
end
```

---

## Architecture

### Module Structure

**`RShell.Builtins`** - All builtin implementations

- Functions named with `shell_` prefix: `shell_echo`, `shell_cd`, `shell_pwd`
- Reflection-based discovery: `function_exported?(__MODULE__, :shell_#{name}, 3)`
- Automatic invocation: `apply(__MODULE__, :shell_#{name}, [args, stdin, context])`

### Unified Signature

**All builtins use the same signature:**

```elixir
@spec shell_*(args, stdin, context) :: {new_context, stdout, stderr, exit_code}

@type args :: [String.t()]
@type stdin :: Stream.t()   # Always Stream!
@type context :: Runtime.context()
@type stdout :: Stream.t()  # Always Stream!
@type stderr :: Stream.t()  # Always Stream!
@type exit_code :: integer()
```

**Parameters:**
- `args` - Command arguments (already parsed from AST)
- `stdin` - Input stream/string (from previous command in pipeline or empty)
- `context` - Full runtime context (env, cwd, mode, etc.)

**Returns:**
- `new_context` - Updated context (unchanged if builtin is pure)
- `stdout` - Output stream or string
- `stderr` - Error stream or string
- `exit_code` - 0 for success, non-zero for failure

---

## I/O Design: Stream-Only Architecture

**Design Decision**: ALL I/O uses `Stream.t()` - no String, no Enumerable, no IO.device.

### Why Stream-Only?

1. ✅ **Uniform type** - No type detection, no conversion logic
2. ✅ **Lazy by default** - Efficient pipelines without memory pressure
3. ✅ **Composable** - All commands chain naturally
4. ✅ **Supports structured data** - Stream elements can be ANY type (strings, structs, etc.)
5. ✅ **Simple to write** - `Stream.concat([text])` is trivial

### Stream Elements Can Be Any Type

```elixir
# Text stream (traditional shell output)
Stream.concat(["line1\n", "line2\n", "line3\n"])

# Struct stream (rich data, PowerShell-like)
Stream.map(files, fn name ->
  %FileInfo{name: name, size: File.stat!(name).size, ...}
end)

# Mixed stream (unusual but allowed)
Stream.concat([%FileInfo{}, "text line", 42])
```

### Pattern Matching on Stream Elements

Builtins process stream elements uniformly, regardless of type:

```elixir
def shell_grep([pattern], stdin, context) when is_struct(stdin, Stream) do
  # Filter works on ANY stream element type
  filtered = Stream.filter(stdin, fn item ->
    # Convert to text for pattern matching
    text = RShell.Streamable.to_text(item)
    String.contains?(text, pattern)
  end)
  
  {context, filtered, Stream.concat([]), 0}
end
```

### Helper for Simple Cases

```elixir
# Helper function for simple text output
defp stream(text) when is_binary(text), do: Stream.concat([text])

# Usage in builtins
def shell_pwd(_argv, _stdin, context) do
  {context, stream(context.cwd <> "\n"), stream(""), 0}
end

def shell_echo(args, _stdin, context) do
  output = Enum.join(args, " ") <> "\n"
  {context, stream(output), stream(""), 0}
end
```

### Type Conversion via Protocol

**Protocol definition**:
```elixir
defprotocol RShell.Streamable do
  @doc "Convert value to text representation"
  def to_text(value)
end

# String implementation (pass-through)
defimpl RShell.Streamable, for: BitString do
  def to_text(str), do: str
end

# Struct implementations (custom formatting)
defimpl RShell.Streamable, for: RShell.FileInfo do
  def to_text(file) do
    # ls -la style output
    "#{file.permissions} #{file.size} #{file.name}\n"
  end
end
```

**Automatic conversion when needed**:

```elixir
# Terminal output - convert stream to text
defp display_to_terminal(stream) do
  stream
  |> Stream.map(&RShell.Streamable.to_text/1)
  |> Enum.each(&IO.write/1)
end

# External process input - convert stream to text
defp feed_to_external(stream, pipeline_handle) do
  stream
  |> Stream.map(&RShell.Streamable.to_text/1)
  |> Stream.into(Pipeline.stdin_writer(pipeline_handle))
  |> Stream.run()
end

# Builtin → Builtin - NO CONVERSION (preserves structs!)
defp builtin_to_builtin(stream, next_builtin) do
  next_builtin.(stream)
end
```

### Complete Example

```elixir
# Builtin that produces struct stream
def shell_ls([], _stdin, context) do
  files = File.ls!(".")
  
  stream = Stream.map(files, fn name ->
    stat = File.stat!(name)
    %RShell.FileInfo{
      name: name,
      size: stat.size,
      permissions: format_perms(stat.mode),
      modified: stat.mtime
    }
  end)
  
  {context, stream, Stream.concat([]), 0}
end

# Builtin that works with ANY stream element type
def shell_head(["-n", n], stdin, context) do
  count = String.to_integer(n)
  limited = Stream.take(stdin, count)
  {context, limited, Stream.concat([]), 0}
end
```

**Usage scenarios**:
- `ls | head -5` → Struct stream throughout (rich data!)
- `ls | grep foo` → Automatic to_text conversion when grep matches
- `ls` → Terminal display converts structs to text via protocol
- `ls | external_cmd` → Runtime converts struct stream to text stream

### Benefits of Stream-Only Design

| Benefit | Description |
|---------|-------------|
| **No dual implementations** | Each builtin has ONE output logic |
| **No type detection** | Runtime doesn't guess String vs Stream vs Enumerable |
| **Auto-conversion** | Protocol handles text conversion only when needed |
| **Preserves structure** | Builtin chains keep rich types (like PowerShell!) |
| **Simple to write** | `stream(text)` helper makes simple cases trivial |
| **Lazy pipelines** | Memory-efficient for large data |

---

## Context Management

### Context Structure

```elixir
%{
  mode: :simulate | :capture | :real,
  env: %{String.t() => String.t()},    # Environment variables
  cwd: String.t(),                      # Current working directory
  exit_code: integer(),                 # Last command exit code
  command_count: integer(),             # Number of commands executed
  output: [String.t()],                 # Accumulated output
  errors: [String.t()]                  # Accumulated errors
}
```

### Immutable Updates

All context modifications create new maps:

```elixir
# Pure builtin - returns context unchanged
def shell_echo(args, _stdin, context) do
  output = Enum.join(args, " ") <> "\n"
  {context, output, "", 0}  # context unchanged
end

# Context-modifying builtin - returns new context
def shell_cd([path], _stdin, context) do
  new_cwd = resolve_path(path, context.cwd)
  new_context = %{context | cwd: new_cwd}
  {new_context, "", "", 0}
end

# Env-modifying builtin
def shell_export([assignment], _stdin, context) do
  [name, value] = String.split(assignment, "=", parts: 2)
  new_env = Map.put(context.env, name, value)
  new_context = %{context | env: new_env}
  {new_context, "", "", 0}
end
```

### Runtime Integration

Runtime always replaces old context with returned context:

```elixir
def handle_call({:execute_node, node}, _from, state) do
  {new_context, stdout, stderr, exit_code} = execute_builtin(...)
  
  # Materialize streams for broadcasting
  stdout_str = materialize_output(stdout)
  stderr_str = materialize_output(stderr)
  
  # Broadcast output
  PubSub.broadcast(session_id, :output, {:stdout, stdout_str})
  PubSub.broadcast(session_id, :output, {:stderr, stderr_str})
  
  # Replace context with new context
  {:reply, {:ok, stdout_str, stderr_str, exit_code}, 
   %{state | context: new_context}}
end
```

---

## Error Handling

Builtins support flexible error reporting:

### Exit Code Style (POSIX)

```elixir
def shell_cd([path], _stdin, context) do
  if File.dir?(path) do
    new_context = %{context | cwd: path}
    {new_context, "", "", 0}
  else
    {context, "", "cd: #{path}: No such file or directory\n", 1}
  end
end
```

### Tagged Tuple Style (Elixir)

```elixir
def shell_cd([path], _stdin, context) do
  case resolve_path(path, context.cwd) do
    {:ok, new_cwd} ->
      new_context = %{context | cwd: new_cwd}
      {new_context, "", "", 0}
    
    {:error, :enoent} ->
      {context, "", "cd: #{path}: No such file or directory\n", 1}
  end
end
```

Runtime handles both styles consistently.

---

## Implemented Builtins

### 1. Echo (`shell_echo`)

**Status**: ✅ Fully implemented and tested

**Purpose**: Display arguments to stdout with optional formatting

**Signature**:
```elixir
@spec shell_echo(args, stdin, context) :: {new_context, stdout, stderr, exit_code}
```

**Flags**:
- `-n` - Suppress trailing newline
- `-e` - Enable interpretation of backslash escapes
- `-E` - Disable interpretation of backslash escapes (default)

**Escape Sequences** (with `-e`):
- `\n` - Newline
- `\t` - Horizontal tab
- `\r` - Carriage return
- `\\` - Backslash
- `\a` - Alert (bell)
- `\b` - Backspace
- `\e` - Escape character
- `\f` - Form feed
- `\v` - Vertical tab

**Examples**:
```elixir
# Basic usage
shell_echo(["hello", "world"], "", %{})
# => {%{}, "hello world\n", "", 0}

# No newline
shell_echo(["-n", "test"], "", %{})
# => {%{}, "test", "", 0}

# Escape sequences
shell_echo(["-e", "line1\\nline2"], "", %{})
# => {%{}, "line1\nline2\n", "", 0}

# Combined flags
shell_echo(["-n", "-e", "test\\n"], "", %{})
# => {%{}, "test\n", "", 0}
```

**Testing**: Comprehensive unit tests in `test/builtins_test.exs`
- Basic functionality (no args, single arg, multiple args)
- Flag behavior (-n, -e, -E)
- All escape sequences
- Flag combinations
- Edge cases (empty strings, spaces, special characters)
- Context preservation

### 2. True (`shell_true`)

**Status**: ✅ Fully implemented
**Purpose**: Return success exit code
**Mode**: `:argv`
**Exit Code**: Always 0

### 3. False (`shell_false`)

**Status**: ✅ Fully implemented
**Purpose**: Return failure exit code
**Mode**: `:argv`
**Exit Code**: Always 1

### 4. Pwd (`shell_pwd`)

**Status**: ✅ Fully implemented
**Purpose**: Print current working directory
**Mode**: `:argv`
**Returns**: `context.cwd` followed by newline

### 5. Cd (`shell_cd`)

**Status**: ✅ Fully implemented
**Purpose**: Change working directory
**Mode**: `:parsed`
**Options**: `-L` (logical, default), `-P` (physical)
**Modifies**: `context.cwd`

### 6. Man (`shell_man`)

**Status**: ✅ Fully implemented
**Purpose**: Display help for builtins
**Mode**: `:parsed`
**Options**: `-a` (list all)
**Uses**: Compile-time generated help text from docstrings

### 7. Env (`shell_env`)

**Status**: ✅ Fully implemented (2025-11-13)
**Purpose**: Unified environment variable management with rich type support
**Mode**: `:argv`
**Features**:
- List all env vars (no args)
- Set variables with JSON parsing: `env A={"x":1}`
- Get variables: `env PATH HOME`
- Automatic JSON type detection
- Pretty-printing for display

**Implementation**:
```elixir
@shell_env_opts :argv
def shell_env(argv, _stdin, context) do
  # Parse JSON values using RShell.EnvJSON
  case RShell.EnvJSON.parse(value_str) do
    {:ok, parsed_value} -> Map.put(env, name, parsed_value)
    {:error, _} -> Map.put(env, name, value_str)  # Fall back to string
  end
end
```

### 8. Inspect (`shell_inspect`)

**Status**: ✅ Fully implemented
**Purpose**: Inspect variable type and value
**Mode**: `:argv`
**Features**:
- Display Elixir type of variables
- Show IO.inspect representation
- Support for all native types (maps, lists, numbers, etc.)

### 9. Test (`shell_test`)

**Status**: ✅ Fully implemented (2025-11-13)
**Purpose**: Evaluate conditional expressions
**Mode**: `:argv`

**Supported Operations**:
- String comparison: `=`, `!=`
- Numeric comparison: `-eq`, `-ne`, `-gt`, `-ge`, `-lt`, `-le`
- Length checks: `-n`, `-z`
- Truthy evaluation (single arg)

**Rich Type Support**:
- Works with native types from env vars
- Automatic type conversion for comparisons
- Bracket notation support (inherited from runtime)

**Examples**:
```bash
test 5 -gt 3              # Numeric comparison
test $NAME = "alice"      # String comparison
test $CONFIG["port"] -eq 5432  # Map access
```

### 10. Math:Add (`shell_add` in `RShell.Builtins.Math`)

**Status**: ✅ Fully implemented (2025-11-15)
**Purpose**: Add numbers with native type output
**Mode**: `:argv`
**Namespace**: `math`

**Features**:
- Accepts 1 or more numbers
- Automatic type conversion (strings, booleans, native numbers)
- Returns sum as native integer or float
- Outputs to stdout stream as native type (not string!)

**Examples**:
```bash
math:add 5 3              # Returns 8
math:add 10 20 30         # Returns 60
math:add 3.14 2.86        # Returns 6.0
env X=5
math:add $X 10            # Returns 15
```

### 11. Math:Sub (`shell_sub` in `RShell.Builtins.Math`)

**Status**: ✅ Fully implemented (2025-11-15)
**Purpose**: Subtract numbers from left to right
**Mode**: `:argv`
**Namespace**: `math`

**Features**:
- Single argument: returns negation
- Multiple arguments: subtracts left to right
- Returns result as native integer or float

**Examples**:
```bash
math:sub 10 3             # Returns 7
math:sub 100 20 5         # Returns 75
math:sub 5                # Returns -5
```

### 12. Math:Mul (`shell_mul` in `RShell.Builtins.Math`)

**Status**: ✅ Fully implemented (2025-11-15)
**Purpose**: Multiply numbers
**Mode**: `:argv`
**Namespace**: `math`

**Features**:
- Accepts 1 or more numbers
- Multiplies all arguments
- Returns product as native integer or float

**Examples**:
```bash
math:mul 5 3              # Returns 15
math:mul 2 3 4            # Returns 24
math:mul 3.5 2            # Returns 7.0
```

### 13. Math:Div (`shell_div` in `RShell.Builtins.Math`)

**Status**: ✅ Fully implemented (2025-11-15)
**Purpose**: Divide numbers from left to right
**Mode**: `:argv`
**Namespace**: `math`

**Features**:
- Requires at least 2 arguments
- Divides left to right
- Always returns float
- Division by zero error handling

**Examples**:
```bash
math:div 10 2             # Returns 5.0
math:div 100 5 2          # Returns 10.0
math:div 7 2              # Returns 3.5
math:div 10 0             # Error: division by zero
```
### 14. Math:Eq (`shell_eq` in `RShell.Builtins.Math`)

**Status**: ✅ Fully implemented (2025-11-15)
**Purpose**: Test numeric equality and output boolean value
**Mode**: `:argv`
**Namespace**: `math`

**Features**:
- Requires exactly 2 arguments
- Compares two numbers for equality
- Returns 1 (true) if equal, 0 (false) if not equal
- Always exits with code 0 (success)
- Automatic type conversion (strings, booleans, native numbers)

**Examples**:
```bash
math:eq 5 5               # Returns 1
math:eq 10 3              # Returns 0
env X=42
math:eq $X 42             # Returns 1
```

**Note**: This builtin outputs to stdout (1 or 0), not an exit code. For use in if statements, use the test builtin: `if test $X -eq 5; then ...`

### 15. Math:Neq (`shell_neq` in `RShell.Builtins.Math`)

**Status**: ✅ Fully implemented (2025-11-15)
**Purpose**: Test numeric inequality and output boolean value
**Mode**: `:argv`
**Namespace**: `math`

**Features**:
- Requires exactly 2 arguments
- Compares two numbers for inequality
- Returns 1 (true) if not equal, 0 (false) if equal
- Always exits with code 0 (success)
- Automatic type conversion (strings, booleans, native numbers)

**Examples**:
```bash
math:neq 5 3              # Returns 1
math:neq 10 10            # Returns 0
env X=42
math:neq $X 100           # Returns 1
```

**Note**: This builtin outputs to stdout (1 or 0), not an exit code. For use in if statements, use the test builtin: `if test $X -ne 5; then ...`

### 16. Math:Mod (`shell_mod` in `RShell.Builtins.Math`)

**Status**: ✅ Fully implemented (2025-11-15)
**Purpose**: Compute modulo of two integers
**Mode**: `:argv`
**Namespace**: `math`

**Features**:
- Requires exactly 2 arguments
- Computes modulo (result has sign of divisor)
- Converts floats to integers (truncates)
- Returns result as native integer
- Division by zero error handling

**Examples**:
```bash
math:mod 10 3             # Returns 1
math:mod -10 3            # Returns 2 (positive, sign of divisor)
math:mod 10 -3            # Returns -2 (negative, sign of divisor)
math:mod -10 -3           # Returns -1 (negative, sign of divisor)
```

**Mathematical Behavior**: `Integer.mod(dividend, divisor)` - result has same sign as divisor

### 17. Math:Rem (`shell_rem` in `RShell.Builtins.Math`)

**Status**: ✅ Fully implemented (2025-11-15)
**Purpose**: Compute remainder of integer division
**Mode**: `:argv`
**Namespace**: `math`

**Features**:
- Requires exactly 2 arguments
- Computes remainder (result has sign of dividend)
- Converts floats to integers (truncates)
- Returns result as native integer
- Division by zero error handling

**Examples**:
```bash
math:rem 10 3             # Returns 1
math:rem -10 3            # Returns -1 (negative, sign of dividend)
math:rem 10 -3            # Returns 1 (positive, sign of dividend)
math:rem -10 -3           # Returns -1 (negative, sign of dividend)
```

**Mathematical Behavior**: `rem(dividend, divisor)` - result has same sign as dividend

**Note**: The difference between `mod` and `rem` is in how they handle negative numbers. Use `mod` for mathematical modulo (always non-negative for positive divisor), use `rem` for remainder after truncating division.


---

## Example: How Echo Was Implemented

### Step 1: Basic Implementation

```elixir
defmodule RShell.Builtins do
  @moduledoc """
  Shell builtin commands with flexible I/O and context management.
  """

  @type args :: [String.t()]
  @type stdin :: Stream.t()   # Always Stream!
  @type context :: map()
  @type stdout :: Stream.t()  # Always Stream!
  @type stderr :: Stream.t()  # Always Stream!
  @type result :: {context, stdout, stderr, integer()}

  @doc """
  Execute a builtin by name using reflection.
  """
  def execute(name, args, stdin, context) do
    function_name = String.to_atom("shell_#{name}")
    
    if function_exported?(__MODULE__, function_name, 3) do
      apply(__MODULE__, function_name, [args, stdin, context])
    else
      {context, "", "#{name}: command not found\n", 127}
    end
  end

  @doc """
  Check if a command is a builtin.
  """
  def is_builtin?(name) do
    function_exported?(__MODULE__, String.to_atom("shell_#{name}"), 3)
  end

  @doc """
  Echo arguments to stdout.
  
  ## Flags
  - `-n` - Do not output trailing newline
  - `-e` - Enable interpretation of backslash escapes
  - `-E` - Disable interpretation of backslash escapes (default)
  
  ## Examples
      iex> shell_echo(["hello"], "", %{})
      {%{}, "hello\\n", "", 0}
      
      iex> shell_echo(["-n", "hello"], "", %{})
      {%{}, "hello", "", 0}
  """
  def shell_echo(args, _stdin, context) do
    {flags, words} = parse_echo_flags(args)
    
    output = Enum.join(words, " ")
    output = if flags.enable_escapes, do: process_escapes(output), else: output
    output = if flags.no_newline, do: output, else: output <> "\n"
    
    {context, output, "", 0}
  end

  # Parse echo flags
  defp parse_echo_flags(args) do
    Enum.reduce(args, {%{no_newline: false, enable_escapes: false}, []}, fn
      "-n", {flags, words} -> 
        {Map.put(flags, :no_newline, true), words}
      "-e", {flags, words} -> 
        {Map.put(flags, :enable_escapes, true), words}
      "-E", {flags, words} -> 
        {Map.put(flags, :enable_escapes, false), words}
      word, {flags, words} -> 
        {flags, words ++ [word]}
    end)
  end

  # Process backslash escape sequences
  defp process_escapes(text) do
    text
    |> String.replace("\\n", "\n")
    |> String.replace("\\t", "\t")
    |> String.replace("\\\\", "\\")
  end
end
```

**Actual Implementation**: See [`lib/r_shell/builtins.ex`](lib/r_shell/builtins.ex)

### Step 2: Runtime Integration

```elixir
# In lib/r_shell/runtime.ex

defp execute_command(%Types.Command{} = cmd, context, session_id) do
  # Extract command name and arguments from AST
  {command_name, args} = extract_command_parts(cmd)
  
  # Check if it's a builtin
  if RShell.Builtins.is_builtin?(command_name) do
    execute_builtin(command_name, args, "", context, session_id)
  else
    # Future: lookup in PATH and execute external command
    execute_external_command_stub(cmd, context, session_id)
  end
end

defp execute_builtin(name, args, stdin, context, session_id) do
  # Execute builtin
  {new_context, stdout, stderr, exit_code} = 
    RShell.Builtins.execute(name, args, stdin, context)
  
  # Materialize streams if needed
  stdout_str = materialize_output(stdout)
  stderr_str = materialize_output(stderr)
  
  # Broadcast output
  unless stdout_str == "" do
    PubSub.broadcast(session_id, :output, {:stdout, stdout_str})
  end
  
  unless stderr_str == "" do
    PubSub.broadcast(session_id, :output, {:stderr, stderr_str})
  end
  
  # Update context with output and exit code
  %{new_context | 
    output: [stdout_str | new_context.output],
    exit_code: exit_code
  }
end

# Helper: Extract command name and args from AST
defp extract_command_parts(%Types.Command{} = cmd) do
  command_name = extract_text_from_node(cmd.name)
  args = Enum.map(cmd.argument || [], &extract_text_from_node/1)
  {command_name, args}
end

defp extract_text_from_node(nil), do: ""
defp extract_text_from_node(node) when is_struct(node) do
  node.source_info.text || ""
end

# Helper: Materialize streams to strings
defp materialize_output(output) when is_binary(output), do: output
defp materialize_output(output) when is_struct(output, Stream) do
  output |> Enum.to_list() |> Enum.join("")
end
defp materialize_output(output) when is_list(output) do
  Enum.join(output, "")
end
```

**Actual Implementation**: See [`lib/r_shell/runtime.ex`](lib/r_shell/runtime.ex:244-420)

Key features of the actual implementation:
- Proper AST traversal to extract command name and arguments
- Pattern matching on typed AST nodes (CommandName, Word, String, StringContent)
- Handles nested structures and concatenations
- Supports variable expansions (recognizes `$VAR` syntax)

### Step 3: Testing

```elixir
# test/builtins_test.exs

defmodule RShell.BuiltinsTest do
  use ExUnit.Case
  alias RShell.Builtins

  @empty_context %{
    mode: :simulate,
    env: %{},
    cwd: "/tmp",
    exit_code: 0,
    command_count: 0,
    output: [],
    errors: []
  }

  describe "shell_echo/3" do
    test "outputs single argument" do
      {_ctx, stdout, stderr, exit_code} = 
        Builtins.shell_echo(["hello"], "", @empty_context)
      
      assert stdout == "hello\n"
      assert stderr == ""
      assert exit_code == 0
    end

    test "outputs multiple arguments with spaces" do
      {_ctx, stdout, _stderr, _} = 
        Builtins.shell_echo(["hello", "world"], "", @empty_context)
      
      assert stdout == "hello world\n"
    end

    test "outputs empty line with no arguments" do
      {_ctx, stdout, _stderr, _} = 
        Builtins.shell_echo([], "", @empty_context)
      
      assert stdout == "\n"
    end

    test "handles -n flag (no newline)" do
      {_ctx, stdout, _stderr, _} = 
        Builtins.shell_echo(["-n", "hello"], "", @empty_context)
      
      assert stdout == "hello"
    end

    test "handles -e flag with escape sequences" do
      {_ctx, stdout, _stderr, _} = 
        Builtins.shell_echo(["-e", "hello\\nworld"], "", @empty_context)
      
      assert stdout == "hello\nworld\n"
    end

    test "returns context unchanged" do
      {new_ctx, _stdout, _stderr, _} = 
        Builtins.shell_echo(["test"], "", @empty_context)
      
      assert new_ctx == @empty_context
    end
  end

  describe "is_builtin?/1" do
    test "returns true for echo" do
      assert Builtins.is_builtin?("echo") == true
    end

    test "returns false for unknown command" do
      assert Builtins.is_builtin?("nonexistent") == false
    end
  end
end
```

### Step 4: Integration Test

```elixir
# test/runtime_test.exs

test "executes echo builtin", %{runtime: runtime, session_id: _session_id} do
  # Create command node
  node = %Types.Command{
    source_info: %Types.SourceInfo{
      start_line: 0, start_column: 0, end_line: 0, end_column: 10,
      text: "echo hello"
    },
    name: %Types.CommandName{
      source_info: %Types.SourceInfo{text: "echo"},
      children: []
    },
    argument: [
      %Types.Word{
        source_info: %Types.SourceInfo{text: "hello"},
        children: []
      }
    ],
    redirect: [],
    children: []
  }

  # Execute
  {:ok, _result} = Runtime.execute_node(runtime, node)

  # Check events
  assert_receive {:execution_started, _}, 1000
  assert_receive {:execution_completed, %{exit_code: 0}}, 1000
  assert_receive {:stdout, "hello\n"}, 1000
end
```

---

## Summary

### Builtin System Features

✅ **Reflection-based discovery** - Add functions, they're automatically available
✅ **Unified signature** - `shell_*(args, stdin, context) → {new_context, stdout, stderr, exit_code}`
✅ **Stream-only I/O** - Uniform type, consistent output format
✅ **JSON-based conversion** - Automatic type conversion via RShell.EnvJSON
✅ **Rich type support** - Environment variables can be maps, lists, numbers, booleans
✅ **Lazy evaluation** - Streams stay lazy throughout pipelines
✅ **Immutable context** - Functional updates, no mutation
✅ **Two invocation modes** - `:parsed` (automatic option parsing) or `:argv` (raw arguments)
✅ **Compile-time help generation** - Docstrings parsed for options and help text

### Adding New Builtins

1. Define `shell_<name>/3` function in `RShell.Builtins`
2. Declare invocation mode: `@shell_<name>_opts :parsed` or `:argv`
3. Add docstring with option specifications (for `:parsed` mode)
4. Accept `stdin` as `Stream.t()`, output as `Stream.t()`
5. Use `stream(text)` helper for simple text output
6. Use `RShell.EnvJSON.format/1` for rich type display
7. Return `{new_context, stdout_stream, stderr_stream, exit_code}`
8. Write tests

No registration needed - reflection handles discovery automatically!

**For rich data types**: Use `RShell.EnvJSON` module for parsing and formatting. Protocol-based conversion is not currently used for builtins.