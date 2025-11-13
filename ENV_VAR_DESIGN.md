# Environment Variables Design: Rich Data Support

**Last Updated**: 2025-11-13
**Status**: Phase 1 Complete (JSON module), Variable expansion pending

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

## Variable Expansion in Arguments

### AST Node Detection

Tree-sitter parses `$VAR` as `SimpleExpansion` or `Expansion` nodes:

```elixir
# Current implementation (lib/r_shell/runtime.ex:358-365)
defp extract_text_from_node(%Types.SimpleExpansion{children: children}) do
  # For now, return the expansion text as-is (e.g., "$VAR")
  # Later we can expand variables from context
  children
  |> Enum.map(&extract_text_from_node/1)
  |> Enum.join("")
  |> then(&"$#{&1}")
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

### Phase 1: JSON & Core Support ✅ COMPLETE
- [x] Create `RShell.EnvJSON` module for JSON encoding/decoding
- [x] Implement `parse/1` with JSON wrapping technique
- [x] Implement `encode/1` for text conversion
- [x] Implement `format/1` for pretty-printing
- [x] Add Jason dependency to `mix.exs`
- [x] Write comprehensive tests (33 tests in `test/env_json_test.exs`)

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

### Completed (Phase 1)
✅ **JSON Module** - `RShell.EnvJSON` with parse/encode/format functions
✅ **Comprehensive tests** - 33 tests covering all JSON operations
✅ **Wrapping technique** - Automatic type detection for maps, lists, numbers, booleans
✅ **Round-trip support** - Parse → Encode → Parse preserves data

### Design Principles
✅ **Rich data support** - Maps, lists, nested structures in env vars
✅ **Automatic JSON conversion** - Only when crossing text boundaries
✅ **Type preservation** - Keep native types as long as possible
✅ **Backward compatible** - String env vars work as before
✅ **Flexible output** - Compact JSON for expansion, pretty JSON for display

### Remaining Work
⏳ **Variable expansion** - Integrate with runtime AST extraction
⏳ **Export enhancement** - Use JSON parsing for assignments
⏳ **Printenv builtin** - Create with JSON display support
⏳ **Option parser** - Add rich type support for builtin arguments

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

This separation keeps concerns clean: pipelines use protocols for streaming data, env vars use JSON for serialization.