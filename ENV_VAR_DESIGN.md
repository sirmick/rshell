# Environment Variables Design: Rich Data Support

**Last Updated**: 2025-11-14
**Status**: Phase 1 Complete ✅ (JSON module with 33 tests), Variable expansion and bracket notation ✅ Complete

---

## Overview

RShell environment variables support both simple strings AND rich data structures (maps, lists, nested structures). The system automatically handles conversion based on context:

- **Text expansion** (`$VAR` in strings) → JSON serialization
- **Builtin invocation** → Direct struct passing (no conversion!)
- **External commands** → JSON serialization
- **Terminal display** → JSON pretty-printing

---

## Core Design Principles

1. **Type Preservation**: Keep rich types as long as possible
2. **Automatic Conversion**: Only convert to text when crossing boundaries
3. **JSON as Wire Format**: Universal text representation
4. **Protocol-Based**: Extensible via `RShell.EnvValue` protocol

---

## Environment Variable Storage

### Context Structure

```elixir
# lib/r_shell/runtime.ex

%{
  env: %{
    # String values (traditional)
    "PATH" => "/usr/bin:/bin",
    "USER" => "mick",
    
    # Map values (structured data)
    "CONFIG" => %{
      "database" => %{"host" => "localhost", "port" => 5432},
      "cache" => %{"enabled" => true, "ttl" => 3600}
    },
    
    # List values
    "SERVERS" => ["web1", "web2", "db1"],
    
    # Nested structures
    "APPS" => [
      %{"name" => "frontend", "port" => 3000},
      %{"name" => "backend", "port" => 4000}
    ]
  },
  cwd: "/home/user",
  exit_code: 0,
  # ...
}
```

### Type Representation

Environment variables can be:
- `String.t()` - Simple string values
- `map()` - Key-value structures
- `list()` - Arrays of any values
- Mixed nested structures

---

## Design Philosophy: Conversion at Boundaries

This design follows the same philosophy as [`PIPELINE_DESIGN.md`](PIPELINE_DESIGN.md:1):

**Key Principle**: Rich types preserved throughout RShell, JSON conversion ONLY when crossing to external programs.

### Conversion Boundaries

| Boundary | Direction | Conversion |
|----------|-----------|------------|
| **Shell → Env Var** | `setenv A='{"x":1}'` | JSON string → Elixir map/list |
| **Env Var → Builtin** | `bro -b $A` | Native map → Native map (NO conversion!) |
| **Env Var → External** | `external_cmd $A` | Native map → JSON string |
| **Terminal Display** | `printenv A` | Native map → Pretty JSON |

### Critical Insight: Native Pass-Through to Builtins

```bash
# Set env var from JSON (conversion at setenv boundary)
setenv CONFIG='{"host":"localhost","port":5432}'

# Pass to builtin - NATIVE struct preserved!
my_builtin --config $CONFIG
# Builtin receives: ['my_builtin', '--config', %{"host" => "localhost", "port" => 5432}]
# NO JSON conversion!

# Pass to external - JSON conversion happens here
external_cmd $CONFIG
# External receives: ["external_cmd", "{\"host\":\"localhost\",\"port\":5432}"]
```

### Comparison with Pipeline Design

| Aspect | Pipeline Design | Env Var Design |
|--------|----------------|----------------|
| **Type Preservation** | Stream elements stay as structs | Env vars stay as maps/lists |
| **Builtin → Builtin** | Native structs preserved | Native maps/lists preserved |
| **Conversion Point** | External process input | External command arguments |
| **Protocol Use** | `Streamable` for stream elements | JSON encode/decode for env vars |
| **No Round-Trip** | ✅ Builtin pipelines | ✅ Builtin with env var args |

**Key Difference**: Don't overload `RShell.Streamable` for env vars. Use direct JSON encoding when needed.

---

## JSON Conversion Module

Instead of protocol, use a dedicated module for env var conversions:

```elixir
# lib/r_shell/env_json.ex

defmodule RShell.EnvJSON do
  @moduledoc """
  JSON encoding/decoding for environment variable values.
  
  Uses JSON wrapping technique for universal type detection:
  - Wrap value in {\"json\": value}
  - Parse as JSON
  - Extract [\"json\"] key
  
  This allows automatic detection of maps, lists, numbers, booleans, strings.
  Requires strings to be quoted like JSON.
  """
  
  @doc """
  Parse value using JSON wrapping technique.
  
  ## Examples
      iex> parse(\"{\\\"x\\\":1}\")
      {:ok, %{\"x\" => 1}}
      
      iex> parse(\"[1,2,3]\")
      {:ok, [1, 2, 3]}
      
      iex> parse(\"42\")
      {:ok, 42}
      
      iex> parse(\"\\\"hello\\\"\")
      {:ok, \"hello\"}
      
      iex> parse(\"hello\")
      {:error, \"Invalid JSON: must quote strings\"}
  """
  def parse(value) when is_binary(value) do
    # Wrap in {"json": value} and parse
    wrapped = "{\"json\":#{value}}"
    
    case Jason.decode(wrapped) do
      {:ok, %{"json" => parsed_value}} ->
        {:ok, parsed_value}
      
      {:error, %Jason.DecodeError{} = error} ->
        {:error, "Invalid JSON: #{Exception.message(error)}"}
    end
  end
  
  # Already native - return as-is wrapped in :ok
  def parse(value), do: {:ok, value}
  
  @doc """
  Encode native Elixir structure to JSON string.
  Used when passing env vars to external commands.
  """
  def encode(value) when is_binary(value), do: value
  def encode(value) when is_map(value), do: Jason.encode!(value)
  def encode(value) when is_list(value) do
    # Check if charlist
    if is_charlist?(value) do
      List.to_string(value)
    else
      Jason.encode!(value)
    end
  end
  def encode(value) when is_integer(value), do: Integer.to_string(value)
  def encode(value) when is_float(value), do: Float.to_string(value)
  def encode(true), do: "true"
  def encode(false), do: "false"
  def encode(nil), do: ""
  def encode(atom) when is_atom(atom), do: Atom.to_string(atom)
  
  @doc """
  Pretty-print for terminal display.
  """
  def format(value) when is_binary(value), do: value
  def format(value) when is_map(value), do: Jason.encode!(value, pretty: true)
  def format(value) when is_list(value) do
    if is_charlist?(value) do
      List.to_string(value)
    else
      Jason.encode!(value, pretty: true)
    end
  end
  def format(value), do: encode(value)
  
  defp is_charlist?([]), do: false
  defp is_charlist?(list) do
    Enum.all?(list, fn
      c when is_integer(c) and c >= 0 and c <= 1114111 -> true
      _ -> false
    end)
  end
end
```

**Note**: `RShell.Streamable` protocol remains for pipeline elements (FileInfo, File.Stat, etc.) but is NOT used for env var conversion.

---

## Bracket Notation for Nested Data Access

**Status**: ✅ Implemented (2025-11-13)

RShell supports **bracket notation** for accessing nested map keys and list indices within environment variables, similar to PowerShell's object property access.

### Syntax

```bash
# Map key access
$VAR["key"]
$VAR["nested"]["deep"]

# List index access
$VAR[0]
$VAR[1]

# Mixed access
$CONFIG["servers"][0]
$DATA[2]["name"]
```

### Implementation

Bracket notation is implemented as a **universal runtime feature** in [`extract_text_from_node/2`](lib/r_shell/runtime.ex:400). When a variable expansion contains bracket syntax, the runtime:

1. **Parses brackets** - Extracts the variable name and bracket chain
2. **Navigates structure** - Traverses nested maps/lists using keys/indices
3. **Returns value** - Retrieves the final nested value

```elixir
# lib/r_shell/runtime.ex:400-416
defp extract_text_from_node(%Types.SimpleExpansion{children: children}, context) do
  var_name = extract_variable_name(children)
  
  # Check for bracket notation
  if String.contains?(var_name, "[") do
    {base_var, bracket_chain} = parse_bracket_access(var_name, context)
    # Navigate nested structure
    navigate_nested(base_var, bracket_chain)
  else
    # Simple variable lookup
    Map.get(context.env, var_name)
  end
end
```

### Examples

#### Map Access

```bash
# Set a nested map
env CONFIG='{"database":{"host":"localhost","port":5432},"cache":{"ttl":3600}}'

# Access nested keys
echo $CONFIG["database"]
# Output: {"host":"localhost","port":5432}

echo $CONFIG["database"]["host"]
# Output: localhost

echo $CONFIG["database"]["port"]
# Output: 5432
```

#### List Access

```bash
# Set a list
env SERVERS='["web1","web2","db1"]'

# Access by index
echo $SERVERS[0]
# Output: web1

echo $SERVERS[2]
# Output: db1
```

#### Mixed Structures

```bash
# Set a list of maps
env APPS='[{"name":"frontend","port":3000},{"name":"backend","port":4000}]'

# Access nested data
echo $APPS[0]["name"]
# Output: frontend

echo $APPS[1]["port"]
# Output: 4000
```

### Type Preservation

Bracket notation preserves native types when used with builtins:

```bash
# Native map preserved in builtin arguments
env -e DATABASE='{"host":"localhost","port":5432}'
my_builtin --config $DATABASE["host"]
# Builtin receives: ["my_builtin", "--config", "localhost"]
```

### Error Handling

- **Undefined variable**: Returns empty string (bash behavior)
- **Invalid key**: Returns empty string
- **Out of bounds**: Returns empty string
- **Type mismatch**: Returns empty string (e.g., index on map, key on list)

### Universal Support

Because bracket notation is implemented at the runtime level, it works **everywhere** variable expansion occurs:

- ✅ Command arguments: `echo $CONFIG["key"]`
- ✅ String interpolation: `echo "Host: $CONFIG["host"]"`
- ✅ Builtin options: `my_cmd --port $CONFIG["port"]`
- ✅ Control flow conditions: `if [ "$APP["status"]" = "active" ]`
- ✅ For loop iteration: `for val in $DATA["items"]; do...`

---

## Variable Expansion in Arguments

### AST Node Detection

Tree-sitter parses `$VAR` as `SimpleExpansion` or `Expansion` nodes:

```elixir
# Enhanced implementation with bracket notation (lib/r_shell/runtime.ex:400-416)
defp extract_text_from_node(%Types.SimpleExpansion{children: children}, context) do
  var_name = extract_variable_name(children)
  
  # Check for bracket notation
  if String.contains?(var_name, "[") do
    {base_var, bracket_chain} = parse_bracket_access(var_name, context)
    navigate_nested(base_var, bracket_chain)
  else
    # Simple variable lookup
    case Map.get(context.env, var_name) do
      nil -> ""
      value -> value  # Native type preserved!
    end
  end
end
```

### Enhanced Variable Expansion

```elixir
# lib/r_shell/runtime.ex

defp extract_text_from_node(%Types.SimpleExpansion{children: children}, context) do
  # Extract variable name
  var_name = children
    |> Enum.map(&extract_variable_name/1)
    |> Enum.join("")
  
  # Look up in context.env
  case Map.get(context.env, var_name) do
    nil -> 
      # Undefined variable - return empty string (bash behavior)
      ""
    
    value ->
      # Convert to text using Streamable protocol (same as pipelines!)
      RShell.Streamable.to_text(value)
  end
end

# Extract variable name from VariableName node
defp extract_variable_name(%Types.VariableName{source_info: %{text: text}}), do: text
defp extract_variable_name(_), do: ""
```

### Expansion Examples

```bash
# String variable
export USER=mick
echo "Hello $USER"
# Output: Hello mick

# Map variable (expands to JSON)
export CONFIG='{"host":"localhost","port":5432}'
echo "Config: $CONFIG"
# Output: Config: {"host":"localhost","port":5432}

# List variable (expands to JSON)
export SERVERS='["web1","web2","db1"]'
echo "Servers: $SERVERS"
# Output: Servers: ["web1","web2","db1"]
```

---

## Builtin Command Integration

### Option Parser Enhancement

Update option parser to handle rich types:

```elixir
# lib/r_shell/builtins/option_parser.ex

defmodule RShell.Builtins.OptionParser do
  # Add new type: :json
  @type option_spec :: %{
    optional(:short) => String.t(),
    optional(:long) => String.t(),
    type: :boolean | :string | :integer | :json | :list | :map,
    default: any(),
    key: atom(),
    description: String.t()
  }
  
  # ... existing code ...
  
  defp parse_value(value, :json) do
    # Try to parse as JSON, fall back to string
    case Jason.decode(value) do
      {:ok, decoded} -> decoded
      {:error, _} -> value
    end
  end
  
  defp parse_value(value, :map) do
    case Jason.decode(value) do
      {:ok, map} when is_map(map) -> map
      _ -> %{}
    end
  end
  
  defp parse_value(value, :list) do
    case Jason.decode(value) do
      {:ok, list} when is_list(list) -> list
      _ -> []
    end
  end
end
```

### Variable Expansion in Builtin Arguments

**Key Insight**: When builtins receive arguments with variable expansions:

1. **In shell strings** (`echo "$CONFIG"`) → Expand to JSON text
2. **Direct pass** (programmatic) → Keep as struct

```elixir
# lib/r_shell/runtime.ex

# Enhanced argument extraction with expansion
defp extract_arguments(args_nodes, context) when is_list(args_nodes) do
  args =
    args_nodes
    |> Enum.map(&extract_text_from_node(&1, context))  # Pass context for expansion!
    |> Enum.reject(&(&1 == ""))
  
  {:ok, args}
end

# Enhanced node extraction with context
defp extract_text_from_node(%Types.SimpleExpansion{children: children}, context) do
  var_name = children
    |> Enum.map(&extract_variable_name/1)
    |> Enum.join("")
  
  case Map.get(context.env, var_name) do
    nil -> ""
    value -> RShell.Streamable.to_text(value)  # JSON for maps/lists!
  end
end

defp extract_text_from_node(%Types.String{children: children}, context) do
  children
  |> Enum.map(&extract_text_from_node(&1, context))  # Propagate context
  |> Enum.join("")
end

defp extract_text_from_node(%Types.Concatenation{children: children}, context) do
  children
  |> Enum.map(&extract_text_from_node(&1, context))
  |> Enum.join("")
end

# Fallback for nodes without children
defp extract_text_from_node(node, _context) do
  extract_text_from_node(node)  # Use existing single-arity version
end
```

---

## Export Command Enhancement

### Support Rich Data Assignment

```elixir
# lib/r_shell/builtins.ex

@doc """
export - set environment variables

Set environment variable NAME to VALUE.
Values can be strings, JSON objects, or JSON arrays.

Usage: export NAME=VALUE

Options:
  -j, --json
      type: boolean
      default: false
      desc: Parse VALUE as JSON (auto-detect by default)

  -n, --unset
      type: boolean
      default: false
      desc: Remove the variable from the environment

## Examples
    export PATH=/usr/bin
    export DEBUG=true
    export CONFIG='{"host":"localhost","port":5432}'
    export SERVERS='["web1","web2","db1"]'
    export -j APPS '[{"name":"app1"},{"name":"app2"}]'
"""
@shell_export_opts :parsed
def shell_export(%ParsedOptions{} = opts, _stdin, context) do
  args = opts.arguments
  
  cond do
    opts.options.unset && length(args) > 0 ->
      # Remove variables (unchanged)
      new_env = Enum.reduce(args, context.env || %{}, fn var_name, env ->
        Map.delete(env, var_name)
      end)
      new_context = %{context | env: new_env}
      {new_context, stream(""), stream(""), 0}
    
    length(args) == 0 ->
      # Print all environment variables (with JSON formatting)
      env = context.env || %{}
      output = env
        |> Enum.map(fn {k, v} -> 
          "#{k}=#{RShell.Display.format(v)}"
        end)
        |> Enum.sort()
        |> Enum.join("\n")
      output = if output == "", do: "", else: output <> "\n"
      {context, stream(output), stream(""), 0}
    
    true ->
      # Set variables with JSON auto-detection
      new_env = Enum.reduce(args, context.env || %{}, fn assignment, env ->
        case String.split(assignment, "=", parts: 2) do
          [name, value] -> 
            # Try to parse as JSON, fall back to string
            parsed_value = parse_env_value(value, opts.options.json)
            Map.put(env, name, parsed_value)
          
          [name] -> 
            Map.put(env, name, "")
        end
      end)
      new_context = %{context | env: new_env}
      {new_context, stream(""), stream(""), 0}
  end
end

# Parse environment variable value
defp parse_env_value(value, force_json) do
  cond do
    force_json ->
      # Forced JSON parsing
      case Jason.decode(value) do
        {:ok, decoded} -> decoded
        {:error, _} -> value  # Fall back to string
      end
    
    String.starts_with?(value, "{") || String.starts_with?(value, "[") ->
      # Auto-detect JSON (starts with { or [)
      case Jason.decode(value) do
        {:ok, decoded} -> decoded
        {:error, _} -> value  # Fall back to string
      end
    
    true ->
      # Plain string
      value
  end
end
```

---

## Printenv Command Enhancement

```elixir
@doc """
printenv - print environment variables

Print the values of environment variables.
Rich data structures are displayed as formatted JSON.

Usage: printenv [OPTIONS] [NAME]...

Options:
  -0, --null
      type: boolean
      default: false
      desc: End each output line with null byte instead of newline

  -j, --json
      type: boolean
      default: false
      desc: Output as compact JSON (no pretty-printing)

## Examples
    printenv
    printenv PATH
    printenv CONFIG
    printenv -j CONFIG
"""
@shell_printenv_opts :parsed
def shell_printenv(%ParsedOptions{} = opts, _stdin, context) do
  args = opts.arguments
  env = context.env || %{}
  use_null = opts.options.null
  use_compact = opts.options.json
  separator = if use_null, do: <<0>>, else: "\n"
  
  output = if length(args) == 0 do
    # Print all variables
    env
    |> Enum.map(fn {k, v} -> 
      value_text = if use_compact do
        RShell.Streamable.to_text(v)
      else
        RShell.Display.format(v)
      end
      "#{k}=#{value_text}"
    end)
    |> Enum.sort()
    |> Enum.join(separator)
  else
    # Print specific variables
    args
    |> Enum.map(fn name ->
      case Map.get(env, name) do
        nil -> ""
        value ->
          if use_compact do
            RShell.Streamable.to_text(value)
          else
            RShell.Display.format(value)
          end
      end
    end)
    |> Enum.join(separator)
  end
  
  output = if output == "", do: "", else: output <> separator
  {context, stream(output), stream(""), 0}
end
```

---

## Example Usage Scenarios

### Scenario 1: Configuration Management

```bash
# Set configuration as structured data
export CONFIG='{"database":{"host":"localhost","port":5432},"cache":{"ttl":3600}}'

# View configuration (pretty-printed)
printenv CONFIG
# Output:
# {
#   "database": {
#     "host": "localhost",
#     "port": 5432
#   },
#   "cache": {
#     "ttl": 3600
#   }
# }

# Expand in string (compact JSON)
echo "Config: $CONFIG"
# Output: Config: {"database":{"host":"localhost","port":5432},"cache":{"ttl":3600}}
```

### Scenario 2: Server Lists

```bash
# Define server list
export SERVERS='["web1.example.com","web2.example.com","db1.example.com"]'

# View list
printenv SERVERS
# Output:
# [
#   "web1.example.com",
#   "web2.example.com",
#   "db1.example.com"
# ]

# Use in command
echo "Deploying to: $SERVERS"
# Output: Deploying to: ["web1.example.com","web2.example.com","db1.example.com"]
```

### Scenario 3: Programmatic Builtin Usage (Future)

```elixir
# Direct programmatic call with rich data
context = %{
  env: %{
    "CONFIG" => %{
      "host" => "localhost",
      "port" => 5432,
      "options" => %{"ssl" => true}
    }
  },
  cwd: "/",
  exit_code: 0,
  command_count: 0,
  output: [],
  errors: []
}

# Custom builtin that expects rich data
{new_ctx, stdout, stderr, code} = 
  RShell.Builtins.execute("deploy", ["--config", "$CONFIG"], "", context)

# The deploy builtin receives:
# argv = ["--config", "{\"host\":\"localhost\",\"port\":5432,\"options\":{\"ssl\":true}}"]
# 
# Or with enhanced option parser:
# %ParsedOptions{
#   options: %{
#     config: %{"host" => "localhost", "port" => 5432, "options" => %{"ssl" => true}}
#   },
#   arguments: []
# }
```

---

## Implementation Checklist

### Phase 1: JSON & Core Support ✅ COMPLETE (2025-11-13)
- [x] Create `RShell.EnvJSON` module for JSON encoding/decoding
- [x] Implement `parse/1` with JSON wrapping technique (lines 43-57)
- [x] Implement `encode/1` for text conversion (lines 77-93)
- [x] Implement `format/1` for pretty-printing (lines 107-117)
- [x] Add Jason dependency to `mix.exs` (already present)
- [x] Write comprehensive tests (33 tests in `test/env_json_test.exs`)
- [x] Charlist detection to avoid treating `[1,2,3]` as charlist

### Phase 2: Variable Expansion ⏳ TODO
- [ ] Update `extract_text_from_node/2` to accept context
- [ ] Implement variable lookup in expansion nodes (SimpleExpansion, Expansion)
- [ ] Use `EnvJSON.encode/1` for text conversion in expansions
- [ ] Thread context through all extraction functions in runtime.ex
- [ ] Write expansion tests

### Phase 3: Export Enhancement ⏳ TODO
- [ ] Update export builtin to use `EnvJSON.parse/1` for value parsing
- [ ] Add `-j/--json` flag for explicit JSON mode
- [ ] Update export to use `EnvJSON.format/1` for display
- [ ] Write export tests for rich data (maps, lists, nested structures)

### Phase 4: Printenv Enhancement ⏳ TODO
- [ ] Create printenv builtin (currently not implemented)
- [ ] Add `-j/--json` flag for compact output
- [ ] Use `EnvJSON.format/1` for pretty-printing by default
- [ ] Use `EnvJSON.encode/1` for compact JSON with `-j` flag
- [ ] Write printenv tests for rich data

### Phase 5: Option Parser Enhancement ⏳ TODO
- [ ] Add `:json`, `:map`, `:list` types to option specs
- [ ] Implement automatic JSON parsing for option values using `EnvJSON.parse/1`
- [ ] Write option parser tests for rich types

### Phase 6: Integration Testing
- [ ] End-to-end tests with rich env vars
- [ ] Test variable expansion in commands
- [ ] Test JSON round-tripping
- [ ] Performance testing with large structures

---

## Dependencies

Add to `mix.exs`:

```elixir
defp deps do
  [
    {:rustler, "~> 0.30.0"},
    {:rustler_precompiled, "~> 0.7.0"},
    {:phoenix_pubsub, "~> 2.1"},
    {:jason, "~> 1.4"}  # ADD THIS for JSON encoding/decoding
  ]
end
```

---

## Summary

### Completed
✅ **Phase 1: JSON Module** (2025-11-13)
  - `RShell.EnvJSON` with parse/encode/format functions
  - 33 comprehensive tests covering all operations
  - Wrapping technique for automatic type detection
  - Round-trip support (Parse → Encode → Parse preserves data)
  - Proper charlist handling

✅ **Bracket Notation** (2025-11-13)
  - Universal runtime feature in `extract_text_from_node/2`
  - Syntax: `$VAR["key"]`, `$VAR[0]`, `$VAR["nested"]["deep"]`
  - Works everywhere variable expansion occurs
  - Documented in lines 221-343

✅ **Enhanced `env` Builtin** (2025-11-13)
  - Unified environment variable management
  - Automatic JSON parsing with `RShell.EnvJSON.parse/1`
  - Pretty-printing with `RShell.EnvJSON.format/1`
  - Supports rich data types (maps, lists, numbers, booleans)

### Design Principles
✅ **Rich data support** - Maps, lists, nested structures in env vars
✅ **Automatic JSON conversion** - Only when crossing text boundaries
✅ **Type preservation** - Keep native types as long as possible
✅ **Backward compatible** - String env vars work as before
✅ **Flexible output** - Compact JSON for expansion, pretty JSON for display

### Remaining Work (Lower Priority)
⏳ **Export enhancement** - Currently basic, could add `-j` flag for explicit JSON mode
⏳ **Option parser** - Add `:json`, `:map`, `:list` types to option specs
⏳ **Variable attributes** - Implementation of readonly, exported, local flags (see lines 936-1304)

**Key Innovation**: Environment variables can hold ANY Elixir term with automatic JSON serialization via the dedicated `RShell.EnvJSON` module. Unlike the pipeline system which uses the `Streamable` protocol for stream elements, env vars use JSON for text conversion.

### Design Difference from Pipelines

**Pipeline system** uses `RShell.Streamable` protocol:
- Stream elements preserve rich types between builtins
- `to_text/1` converts to text only at boundaries (terminal, external commands)

**Env var system** uses `RShell.EnvJSON` module:
- Env vars stored as native Elixir terms (maps, lists, etc.)
- `parse/1` converts JSON text → native terms
- `encode/1` converts native terms → compact JSON text
- `format/1` converts native terms → pretty JSON text


---

## RShell Variable Design: Simplified & Enhanced

**Last Updated**: 2025-11-13
**Status**: Design Complete, Implementation Pending

---

### Core Philosophy: Always Global Assignment

**RShell Enhancement**: Unlike bash, direct variable assignment (`X=value`) **always creates global variables**, even inside functions (when implemented).

**Rationale**:
- Simpler mental model than bash's confusing scoping
- Global by default is more predictable
- Explicit locality via `env -l` when needed
- Avoids bash's implicit local creation

---

### Variable Assignment Syntax

#### Direct Assignment (VariableAssignment AST Node)

```bash
# Always global, no attributes
X=12
Y="hello"
CONFIG={"host":"localhost","port":5432}
SERVERS=["web1","web2","db1"]
```

**Behavior**:
- Parsed as `VariableAssignment` AST node
- Always global (even inside functions)
- Supports JSON value detection via `RShell.EnvJSON.parse/1`
- No implicit attributes (not readonly, not exported)

#### Attributed Assignment (via `env` Builtin)

```bash
# Readonly variable
env -r API_KEY="secret123"

# Exported variable
env -e PATH=/usr/bin

# Local variable (inside function only)
env -l TEMP="value"

# Combined attributes
env -er DATABASE_URL="postgres://localhost"
env -lr CONFIG="local readonly"

# Modify existing variable attributes
env -e -r X  # Make X exported + readonly
```

**Flags**:
- `-e` / `--export` - Export to child processes
- `-r` / `--readonly` - Make immutable
- `-l` / `--local` - Function-local (error outside functions)

---

### Context Structure Enhancement

#### Parallel Metadata Design (Recommended)

**Backward compatible** - separates values from attributes:

```elixir
%{
  # Values (unchanged - existing code compatible!)
  env: %{
    "A" => 123,
    "B" => "hello",
    "CONFIG" => %{"host" => "localhost", "port" => 5432}
  },
  
  # Metadata (NEW - only for vars with non-default attributes)
  env_meta: %{
    "B" => %{readonly: true, exported: false},
    "CONFIG" => %{readonly: false, exported: true}
    # "A" not present = default attributes (readonly: false, exported: false)
  },
  
  # Existing fields (unchanged)
  cwd: String.t(),
  exit_code: integer(),
  command_count: integer(),
  output: [any()],
  errors: [String.t()]
}
```

**Default Attributes**:
```elixir
@default_attributes %{
  readonly: false,
  exported: false
}
```

**Benefits**:
- ✅ Backward compatible (existing code unchanged)
- ✅ Opt-in metadata (low memory overhead)
- ✅ Clean separation (values vs attributes)
- ✅ Fast default path (no metadata lookup for 99% of vars)

---

### Helper Functions

```elixir
# Get variable value (unchanged)
def get_var(context, name), do: Map.get(context.env, name)

# Get variable attributes (with defaults)
def get_attributes(context, var_name) do
  Map.get(context.env_meta || %{}, var_name, @default_attributes)
end

# Check if readonly
def is_readonly?(context, var_name) do
  get_in(context, [:env_meta, var_name, :readonly]) == true
end

# Set variable with attributes
def set_var(context, name, value, attrs \\ @default_attributes) do
  # Check readonly
  if is_readonly?(context, name) do
    {:error, "#{name}: readonly variable"}
  else
    # Update value
    new_env = Map.put(context.env, name, value)
    
    # Update metadata (only if non-default)
    new_meta = if has_attributes?(attrs) do
      Map.put(context.env_meta || %{}, name, attrs)
    else
      context.env_meta || %{}
    end
    
    {:ok, %{context | env: new_env, env_meta: new_meta}}
  end
end

defp has_attributes?(attrs) do
  attrs.readonly == true || attrs.exported == true
end
```

---

### Reserved Keywords

The following bash commands are **reserved but not implemented**:

- `export` → Use `env -e` instead
- `readonly` → Use `env -r` instead
- `local` → Use `env -l` instead (inside functions)
- `declare` → Use `env` with appropriate flags

**Implementation**: `DeclarationCommand` AST node handling with helpful errors:

```elixir
%Types.DeclarationCommand{source_info: info} ->
  command_text = info.text || "declaration command"
  
  cond do
    String.starts_with?(command_text, "export ") ->
      {:error, "export is a reserved keyword. Use: env -e VAR=value"}
    
    String.starts_with?(command_text, "readonly ") ->
      {:error, "readonly is a reserved keyword. Use: env -r VAR=value"}
    
    String.starts_with?(command_text, "local ") ->
      {:error, "local is a reserved keyword. Use: env -l VAR=value"}
    
    String.starts_with?(command_text, "declare ") ->
      {:error, "declare is a reserved keyword. Use: env with flags"}
    
    true ->
      {:error, "Declaration command not supported: #{command_text}"}
  end
```

---

### Future: Function Scope Stack

When implementing functions, add scope stack:

```elixir
%{
  env: %{...},           # Global variables
  env_meta: %{...},      # Global metadata
  
  env_stack: [           # NEW - function scope stack
    %{
      vars: %{"LOCAL" => "value"},
      meta: %{"LOCAL" => %{readonly: false, local: true}}
    }
  ],
  
  function_depth: 1      # 0 = global, 1+ = inside function(s)
}
```

**Lookup order**: stack (top to bottom) → env

---

## TODO: Variable Assignment & Attributes Implementation

**Status**: Design Complete, Implementation Partially Done
**Priority**: Medium (control flow tests mostly passing)

**Note**: Basic variable assignment works via VariableAssignment AST nodes. The attribute system (readonly, exported, local) is designed but not yet implemented. Control flow tests use alternative syntax (`env` builtin instead of `export`).

### Phase 1: Context Structure Enhancement

**Files**: `lib/r_shell/runtime.ex`

- [ ] Add `env_meta: %{}` field to context initialization in `init/1`
- [ ] Define `@default_attributes` module attribute
- [ ] Update context typespec to include `env_meta` field
- [ ] Ensure backward compatibility (existing tests pass)

**Tests**: `test/runtime_test.exs`
- [ ] Test context initialization includes `env_meta`
- [ ] Test default `env_meta` is empty map
- [ ] Verify existing tests still pass (backward compatibility)

---

### Phase 2: Helper Functions

**Files**: `lib/r_shell/runtime.ex`

- [ ] Implement `get_var/2` - Get variable value (simple wrapper)
- [ ] Implement `get_attributes/2` - Get attributes with defaults
- [ ] Implement `is_readonly?/2` - Check readonly flag
- [ ] Implement `is_exported?/2` - Check exported flag
- [ ] Implement `set_var/3` - Set variable with readonly checking
- [ ] Implement `set_var/4` - Set variable with attributes
- [ ] Implement `has_attributes?/1` - Check if attributes differ from default

**Tests**: `test/env_var_attributes_test.exs` (NEW)
- [ ] Test `get_var/2` returns correct value
- [ ] Test `get_attributes/2` returns defaults when no metadata
- [ ] Test `get_attributes/2` returns stored metadata when present
- [ ] Test `is_readonly?/2` returns false by default
- [ ] Test `is_readonly?/2` returns true when set
- [ ] Test `is_exported?/2` returns false by default
- [ ] Test `is_exported?/2` returns true when set
- [ ] Test `set_var/4` creates variable with attributes
- [ ] Test `set_var/4` rejects modification of readonly variable
- [ ] Test `set_var/4` allows modification of non-readonly variable
- [ ] Test `has_attributes?/1` returns false for default attributes
- [ ] Test `has_attributes?/1` returns true for non-default attributes

---

### Phase 3: VariableAssignment Execution

**Files**: `lib/r_shell/runtime.ex`

- [ ] Add pattern match for `%Types.VariableAssignment{}` in `simple_execute/3`
- [ ] Implement `execute_variable_assignment/3` function
- [ ] Extract variable name from VariableName node
- [ ] Extract value text from value node
- [ ] Parse value with `RShell.EnvJSON.parse/1` for JSON detection
- [ ] Fall back to string if JSON parsing fails
- [ ] Update context.env with parsed value (always global, no attributes)
- [ ] Broadcast variable_set event via PubSub

**Tests**: `test/variable_assignment_test.exs` (NEW)
- [ ] Test simple string assignment: `X="hello"`
- [ ] Test number assignment: `COUNT=0`
- [ ] Test JSON map assignment: `CONFIG={"x":1}`
- [ ] Test JSON list assignment: `SERVERS=["a","b"]`
- [ ] Test nested structure assignment
- [ ] Test assignment inside for loop (persistence)
- [ ] Test assignment updates existing variable
- [ ] Test variable persists across multiple commands
- [ ] Test PubSub event is broadcast with correct data
- [ ] Test assignment with variable expansion: `Y=$X`

---

### Phase 4: DeclarationCommand Handling (Reserved Keywords)

**Files**: `lib/r_shell/runtime.ex`

- [ ] Update `%Types.DeclarationCommand{}` pattern match in `simple_execute/3`
- [ ] Implement detection of reserved keywords (export, readonly, local, declare)
- [ ] Return helpful error messages with `env` command alternatives
- [ ] Set exit_code to 1 on error
- [ ] Broadcast error to PubSub stderr topic

**Tests**: `test/declaration_command_test.exs` (NEW)
- [ ] Test `export VAR=value` returns helpful error
- [ ] Test `readonly VAR=value` returns helpful error
- [ ] Test `local VAR=value` returns helpful error
- [ ] Test `declare VAR=value` returns helpful error
- [ ] Test error includes suggested `env` command syntax
- [ ] Test exit_code is set to 1
- [ ] Test stderr PubSub event is broadcast
- [ ] Verify control flow tests can use alternative syntax

---

### Phase 5: Enhanced `env` Builtin

**Files**: `lib/r_shell/builtins.ex`

- [ ] Add `-e` / `--export` flag to option spec
- [ ] Add `-r` / `--readonly` flag to option spec
- [ ] Add `-l` / `--local` flag to option spec
- [ ] Update `shell_env/3` to handle attribute flags
- [ ] Parse attributes from flags into map
- [ ] Use `set_var/4` helper for attribute support
- [ ] Implement readonly checking before modification
- [ ] Implement local flag validation (error outside functions)
- [ ] Handle attribute modification mode (no value, just flags)
- [ ] Support combined flags: `-er`, `-lr`, etc.
- [ ] Update docstring with new flags and examples

**Tests**: `test/env_builtin_attributes_test.exs` (NEW)
- [ ] Test `env -r VAR=value` sets readonly
- [ ] Test `env -r VAR=value` then `env VAR=new` fails
- [ ] Test `env -e VAR=value` sets exported
- [ ] Test `env -l VAR=value` outside function fails
- [ ] Test `env -er VAR=value` sets both attributes
- [ ] Test `env -lr VAR=value` sets both attributes
- [ ] Test `env -e -r VAR` modifies existing variable
- [ ] Test combined flags work: `-er`, `-re`
- [ ] Test readonly error includes variable name
- [ ] Test local error includes helpful message
- [ ] Test attribute modification preserves value
- [ ] Test listing variables shows attributes (future enhancement)

---

### Phase 6: Integration Testing

**Tests**: `test/env_var_integration_test.exs` (NEW)

- [ ] Test variable assignment + expansion: `X=123; echo $X`
- [ ] Test readonly + assignment error: `env -r X=1; X=2` fails
- [ ] Test readonly + `env` modification error: `env -r X=1; env X=2` fails
- [ ] Test exported flag (mock child process check)
- [ ] Test JSON round-trip: `env A={"x":1}; echo $A`
- [ ] Test native type preservation in for loops
- [ ] Test assignment in for loop body: `for i in 1 2 3; do X=$i; done`
- [ ] Test loop variable overwrites previous value
- [ ] Test readonly prevents loop variable modification
- [ ] End-to-end: assignment + attributes + expansion + control flow

---

### Phase 7: Control Flow Test Migration

**Files**: `test/control_flow_test.exs`

- [ ] Replace `export COUNT=0` with `env COUNT=0` or `COUNT=0`
- [ ] Replace other export statements with direct assignment
- [ ] Verify all 6 blocked tests now pass
- [ ] Add comments explaining RShell's always-global semantics
- [ ] Update test documentation

---

### Phase 8: Documentation Updates

**Files**: `ENV_VAR_DESIGN.md`, `README.md`, `BUILTIN_DESIGN.md`

- [ ] Document always-global assignment semantics
- [ ] Document `env` flag usage (-e, -r, -l)
- [ ] Document reserved keywords (export, readonly, local, declare)
- [ ] Add migration guide from bash syntax
- [ ] Update examples to use new syntax
- [ ] Document context structure changes
- [ ] Document metadata opt-in design
- [ ] Add troubleshooting section for readonly errors

---

### Summary Checklist

**Context Structure**:
- [ ] Add `env_meta` field to context
- [ ] Define default attributes
- [ ] Implement helper functions
- [ ] Write helper function tests (12 tests)

**Variable Assignment**:
- [ ] Handle VariableAssignment AST node
- [ ] JSON parsing for rich types
- [ ] Always global, no attributes
- [ ] Write assignment tests (10 tests)

**Reserved Keywords**:
- [ ] Handle DeclarationCommand with errors
- [ ] Helpful error messages
- [ ] Write reserved keyword tests (7 tests)

**Enhanced `env` Builtin**:
- [ ] Add -e, -r, -l flags
- [ ] Readonly checking
- [ ] Attribute modification
- [ ] Write env attribute tests (12 tests)

**Integration & Migration**:
- [ ] End-to-end integration tests (10 tests)
- [ ] Migrate control flow tests (6 tests)
- [ ] Update documentation

**Total Estimated Tests**: ~57 new tests (when attribute system is implemented)

**Current Status**:
- ✅ JSON module: 33 tests passing
- ✅ Bracket notation: Works (inherited from runtime)
- ✅ `env` builtin: Implemented with rich type support
- ⏳ Variable attributes: Design complete, implementation pending

---

### Dependencies

- ✅ `RShell.EnvJSON` module (already implemented)
- ✅ JSON parsing support (Jason dependency)
- ⏳ Context structure changes
- ⏳ Helper function implementation
- ⏳ AST node handling (VariableAssignment, DeclarationCommand)

---

### This separation keeps concerns clean: pipelines use protocols for streaming data, env vars use JSON for serialization.