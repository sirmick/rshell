# RShell Pipeline & Redirection Design

**Last Updated**: 2025-11-12

---

## Overview

This document describes RShell's architecture for executing pipelines and redirections, combining Elixir builtins with external processes through streaming I/O and file descriptors managed via Rust NIF.

**Design Goals**:
- ✅ **Streaming I/O** - No buffering entire output, lazy evaluation
- ✅ **Structured data** - Support rich types (like PowerShell) AND traditional text
- ✅ **OS-level pipes** - Use kernel for efficient inter-process communication
- ✅ **Uniform interface** - Everything is a Stream in Elixir
- ✅ **Protocol-based conversion** - Automatic text conversion when crossing boundaries

---

## Architecture Components

```
┌─────────────────────────────────────────────────────────┐
│                    Runtime GenServer                     │
│  ┌────────────────────────────────────────────────────┐ │
│  │         Pipeline Orchestrator                       │ │
│  │  - Classifies commands (builtin vs external)       │ │
│  │  - Routes execution based on type                  │ │
│  │  - Manages Stream connections                      │ │
│  └────────────────────────────────────────────────────┘ │
│                        ↓                                 │
│         ┌──────────────┴──────────────┐                 │
│         ↓                              ↓                 │
│  ┌─────────────┐              ┌──────────────────┐      │
│  │   Builtin   │              │  Rust Pipeline   │      │
│  │  Executor   │              │     Manager      │      │
│  │             │              │  (via NIF)       │      │
│  │ Stream.t()  │              │                  │      │
│  │   ↕ ↕ ↕     │              │  spawn_pipeline  │      │
│  │ Structured  │              │  stdin writer    │      │
│  │    Data     │              │  stdout reader   │      │
│  └─────────────┘              └──────────────────┘      │
│         ↓                              ↓                 │
│  ┌─────────────────────────────────────────────┐        │
│  │     Protocol: RShell.Streamable             │        │
│  │  - to_text/1 for terminal display           │        │
│  │  - to_text/1 for external process input     │        │
│  └─────────────────────────────────────────────┘        │
└─────────────────────────────────────────────────────────┘
                        ↓
              ┌─────────────────┐
              │   OS Kernel     │
              │  - File Descs   │
              │  - Pipes        │
              │  - Backpressure │
              └─────────────────┘
```

---

## Stream-Only I/O System

### Core Principle

**ALL I/O uses `Stream.t()`** - no String, no Enumerable, no IO.device exposed to builtins.

```elixir
# Builtin signature
@spec shell_*(argv, stdin, context) :: {context, stdout, stderr, exit_code}
@type stdin :: Stream.t()   # Always Stream
@type stdout :: Stream.t()  # Always Stream
@type stderr :: Stream.t()  # Always Stream
```

### Stream Elements Can Be Any Type

```elixir
# Text stream (traditional shell)
Stream.concat(["line1\n", "line2\n"])

# Struct stream (rich data)
Stream.map(files, &to_file_struct/1)
# => Stream of %FileInfo{name: "foo.txt", size: 1024, ...}

# Mixed stream
Stream.concat([%FileInfo{}, "text", 42])
```

### Helper for Simple Cases

```elixir
# Helper function
defp stream(text) when is_binary(text), do: Stream.concat([text])

# Usage
def shell_echo(args, _stdin, context) do
  output = Enum.join(args, " ") <> "\n"
  {context, stream(output), stream(""), 0}
end
```

---

## Protocol-Based Type Conversion

### Protocol Definition

```elixir
defprotocol RShell.Streamable do
  @doc """
  Convert value to text representation for external processes or terminal display.
  """
  @spec to_text(t) :: String.t()
  def to_text(value)
end
```

### Implementations

```elixir
# String pass-through
defimpl RShell.Streamable, for: BitString do
  def to_text(str), do: str
end

# Custom struct
defmodule RShell.FileInfo do
  @derive {Inspect, only: [:name, :size]}
  defstruct [:name, :size, :permissions, :modified, :type]
end

defimpl RShell.Streamable, for: RShell.FileInfo do
  def to_text(file) do
    # ls -la style output
    "#{file.permissions} #{file.size |> pad(8)} #{file.modified |> format_time()} #{file.name}\n"
  end
  
  defp pad(num, width), do: String.pad_leading("#{num}", width)
  defp format_time(datetime), do: Calendar.strftime(datetime, "%b %d %H:%M")
end

# File.Stat
defimpl RShell.Streamable, for: File.Stat do
  def to_text(stat) do
    "#{stat.size}\t#{stat.mtime}\t#{stat.type}\n"
  end
end
```

### Automatic Conversion Points

```elixir
# 1. Terminal display
defp display_to_terminal(stream) do
  stream
  |> Stream.map(&RShell.Streamable.to_text/1)
  |> Enum.each(&IO.write/1)
end

# 2. External process input
defp feed_to_external(stream, pipeline_handle) do
  stream
  |> Stream.map(&RShell.Streamable.to_text/1)
  |> Stream.into(Pipeline.stdin_writer(pipeline_handle))
  |> Stream.run()
end

# 3. Builtin → Builtin (NO CONVERSION!)
defp builtin_to_builtin(output_stream, next_builtin, context) do
  # Pass stream directly - preserves struct types!
  next_builtin.(output_stream, context)
end
```

---

## Pipeline Execution Strategies

### Strategy 1: All Builtins

**Example**: `ls | grep foo | head -5`

```elixir
defp execute_builtin_pipeline([cmd1, cmd2, cmd3], context, session_id) do
  # Start with empty stream
  initial_stream = Stream.concat([])
  
  # Chain builtins, passing stream through
  {ctx1, stream1, _stderr1, _} = execute_builtin(cmd1, initial_stream, context)
  {ctx2, stream2, _stderr2, _} = execute_builtin(cmd2, stream1, ctx1)
  {ctx3, stream3, stderr3, code} = execute_builtin(cmd3, stream2, ctx2)
  
  # Display final output
  display_to_terminal(stream3)
  
  {ctx3, code}
end
```

**Key**: Streams stay lazy, structs preserved throughout!

### Strategy 2: All Externals

**Example**: `ls -la | grep foo | wc -l`

```elixir
defp execute_external_pipeline(commands, context, session_id) do
  # Spawn pipeline in Rust (OS-level pipes)
  {:ok, handle} = RShell.Pipeline.spawn(commands)
  
  # Read output as stream
  output_stream = RShell.Pipeline.stdout_reader(handle)
  
  # Display to terminal
  display_to_terminal(output_stream)
  
  # Wait for completion
  {:ok, exit_codes} = RShell.Pipeline.wait(handle)
  
  {context, List.last(exit_codes)}
end
```

**Key**: OS handles all pipe connections, Rust manages file descriptors.

### Strategy 3: Mixed Pipeline

**Example**: `ls_struct | external_grep foo | head_builtin -5`

```elixir
defp execute_mixed_pipeline(commands, context, session_id) do
  # Identify runs of external commands
  segments = segment_pipeline(commands)
  # => [{:builtin, cmd1}, {:external, [cmd2, cmd3]}, {:builtin, cmd4}]
  
  Enum.reduce(segments, {context, Stream.concat([])}, fn
    {:builtin, cmd}, {ctx, input_stream} ->
      {new_ctx, output_stream, _stderr, _code} = 
        execute_builtin(cmd, input_stream, ctx)
      {new_ctx, output_stream}
    
    {:external, ext_cmds}, {ctx, input_stream} ->
      # Spawn external pipeline
      {:ok, handle} = RShell.Pipeline.spawn(ext_cmds)
      
      # Convert struct stream to text and feed to external
      Task.async(fn ->
        input_stream
        |> Stream.map(&RShell.Streamable.to_text/1)
        |> Stream.into(Pipeline.stdin_writer(handle))
        |> Stream.run()
      end)
      
      # Get output as text stream
      output_stream = RShell.Pipeline.stdout_reader(handle)
      
      # Convert text back to stream for next builtin
      {ctx, output_stream}
  end)
end
```

**Key**: Automatic conversion at builtin ↔ external boundaries.

---

## Rust NIF Implementation

### NIF Module Structure

```
native/RShell.BashParser/src/
├── lib.rs              # Main NIF entry point
├── parser.rs           # Existing parser NIFs
└── pipeline.rs         # NEW: Pipeline management
```

### Pipeline Resource

```rust
// native/RShell.BashParser/src/pipeline.rs

use rustler::{Resource, ResourceArc, NifStruct};
use std::process::{Child, Command, Stdio, ChildStdin, ChildStdout};
use std::io::{Write, BufReader, BufRead};
use std::sync::{Arc, Mutex};

/// Handle for a running pipeline of external processes
pub struct PipelineHandle {
    processes: Vec<Child>,
    stdin: Option<Arc<Mutex<ChildStdin>>>,   // Write to first process
    stdout: Option<Arc<Mutex<BufReader<ChildStdout>>>>, // Read from last process
}

impl Resource for PipelineHandle {}

impl PipelineHandle {
    /// Spawn a pipeline of commands connected by OS pipes
    pub fn new(commands: Vec<Vec<String>>) -> Result<Self, String> {
        if commands.is_empty() {
            return Err("No commands provided".to_string());
        }
        
        let mut processes = Vec::new();
        let mut prev_stdout: Option<Stdio> = None;
        let mut first_stdin = None;
        let mut last_stdout = None;
        
        for (i, cmd_args) in commands.iter().enumerate() {
            if cmd_args.is_empty() {
                return Err(format!("Empty command at index {}", i));
            }
            
            let mut cmd = Command::new(&cmd_args[0]);
            cmd.args(&cmd_args[1..]);
            
            // Configure stdin
            if i == 0 {
                cmd.stdin(Stdio::piped());
            } else if let Some(stdout) = prev_stdout.take() {
                cmd.stdin(stdout);
            }
            
            // Configure stdout
            if i == commands.len() - 1 {
                cmd.stdout(Stdio::piped());
            } else {
                cmd.stdout(Stdio::piped());
            }
            
            // Spawn process
            let mut child = cmd.spawn()
                .map_err(|e| format!("Failed to spawn '{}': {}", cmd_args[0], e))?;
            
            // Capture first stdin
            if i == 0 {
                first_stdin = child.stdin.take();
            }
            
            // Set up next process's stdin
            if i < commands.len() - 1 {
                prev_stdout = child.stdout.take().map(Stdio::from);
            } else {
                // Capture last stdout
                last_stdout = child.stdout.take();
            }
            
            processes.push(child);
        }
        
        Ok(Self {
            processes,
            stdin: first_stdin.map(|s| Arc::new(Mutex::new(s))),
            stdout: last_stdout.map(|s| Arc::new(Mutex::new(BufReader::new(s)))),
        })
    }
}
```

### NIF Functions

```rust
// native/RShell.BashParser/src/lib.rs

mod pipeline;
use pipeline::PipelineHandle;

#[rustler::nif]
fn spawn_pipeline(commands: Vec<Vec<String>>) -> Result<ResourceArc<PipelineHandle>, String> {
    let handle = PipelineHandle::new(commands)?;
    Ok(ResourceArc::new(handle))
}

#[rustler::nif]
fn pipeline_write(handle: ResourceArc<PipelineHandle>, data: String) -> Result<usize, String> {
    if let Some(ref stdin) = handle.stdin {
        let mut stdin = stdin.lock()
            .map_err(|e| format!("Lock error: {}", e))?;
        
        stdin.write_all(data.as_bytes())
            .map_err(|e| format!("Write error: {}", e))?;
        
        stdin.flush()
            .map_err(|e| format!("Flush error: {}", e))?;
        
        Ok(data.len())
    } else {
        Err("No stdin available".to_string())
    }
}

#[rustler::nif]
fn pipeline_read_line(handle: ResourceArc<PipelineHandle>) -> Result<String, String> {
    if let Some(ref stdout) = handle.stdout {
        let mut stdout = stdout.lock()
            .map_err(|e| format!("Lock error: {}", e))?;
        
        let mut line = String::new();
        match stdout.read_line(&mut line) {
            Ok(0) => Ok(String::new()), // EOF
            Ok(_) => Ok(line),
            Err(e) => Err(format!("Read error: {}", e))
        }
    } else {
        Err("No stdout available".to_string())
    }
}

#[rustler::nif]
fn pipeline_close_stdin(handle: ResourceArc<PipelineHandle>) -> Result<(), String> {
    // Dropping stdin closes it
    if let Some(ref stdin) = handle.stdin {
        drop(stdin.lock().ok());
    }
    Ok(())
}

#[rustler::nif]
fn pipeline_wait(handle: ResourceArc<PipelineHandle>) -> Result<Vec<i32>, String> {
    let mut exit_codes = Vec::new();
    
    for child in &mut handle.processes {
        let status = child.wait()
            .map_err(|e| format!("Wait error: {}", e))?;
        exit_codes.push(status.code().unwrap_or(-1));
    }
    
    Ok(exit_codes)
}

// Register all NIFs
rustler::init!(
    "Elixir.BashParser",
    [
        // Existing parser NIFs
        parse,
        create_parser,
        append_fragment,
        reset_parser,
        
        // NEW: Pipeline NIFs
        spawn_pipeline,
        pipeline_write,
        pipeline_read_line,
        pipeline_close_stdin,
        pipeline_wait,
    ]
);
```

---

## Elixir Pipeline Module

```elixir
# lib/r_shell/pipeline.ex

defmodule RShell.Pipeline do
  @moduledoc """
  Manages external command pipelines with streaming I/O.
  
  Uses Rust NIF to spawn processes connected by OS-level pipes.
  Provides Stream interface for Elixir code.
  """

  defmodule StreamWriter do
    @moduledoc false
    defstruct [:handle]
  end

  @doc """
  Spawn a pipeline of external commands.
  
  ## Example
      {:ok, handle} = Pipeline.spawn([
        ["ls", "-la"],
        ["grep", "foo"],
        ["wc", "-l"]
      ])
  """
  @spec spawn([[String.t()]]) :: {:ok, reference()} | {:error, String.t()}
  def spawn(commands) when is_list(commands) do
    BashParser.spawn_pipeline(commands)
  end

  @doc """
  Create a Stream that writes to the pipeline's stdin.
  
  Returns a Collectable for use with Stream.into/2.
  
  ## Example
      stream = Stream.map(data, &process/1)
      Stream.into(stream, Pipeline.stdin_writer(handle))
      |> Stream.run()
  """
  @spec stdin_writer(reference()) :: %StreamWriter{}
  def stdin_writer(handle) do
    %StreamWriter{handle: handle}
  end

  @doc """
  Create a Stream that reads from the pipeline's stdout.
  
  Returns a lazy Stream that reads line-by-line from the last process.
  
  ## Example
      Pipeline.stdout_reader(handle)
      |> Stream.map(&String.trim/1)
      |> Enum.to_list()
  """
  @spec stdout_reader(reference()) :: Enumerable.t()
  def stdout_reader(handle) do
    Stream.resource(
      fn -> handle end,
      fn h ->
        case BashParser.pipeline_read_line(h) do
          {:ok, ""} -> {:halt, h}  # EOF
          {:ok, line} -> {[line], h}
          {:error, reason} -> 
            IO.warn("Pipeline read error: #{reason}")
            {:halt, h}
        end
      end,
      fn _h -> :ok end
    )
  end

  @doc """
  Close the pipeline's stdin to signal end of input.
  """
  @spec close_stdin(reference()) :: :ok | {:error, String.t()}
  def close_stdin(handle) do
    case BashParser.pipeline_close_stdin(handle) do
      {:ok, _} -> :ok
      error -> error
    end
  end

  @doc """
  Wait for all processes in the pipeline to complete.
  
  Returns a list of exit codes (one per process).
  """
  @spec wait(reference()) :: {:ok, [integer()]} | {:error, String.t()}
  def wait(handle) do
    BashParser.pipeline_wait(handle)
  end
end

# Implement Collectable for StreamWriter
defimpl Collectable, for: RShell.Pipeline.StreamWriter do
  def into(%{handle: handle} = writer) do
    collector = fn
      acc, {:cont, chunk} ->
        case BashParser.pipeline_write(handle, to_string(chunk)) do
          {:ok, _} -> acc
          {:error, reason} -> throw({:write_error, reason})
        end
        acc
      
      acc, :done ->
        RShell.Pipeline.close_stdin(handle)
        acc
      
      _acc, :halt ->
        :ok
    end
    
    {writer, collector}
  end
end
```

---

## Runtime Integration

```elixir
# lib/r_shell/runtime.ex

defmodule RShell.Runtime do
  # ... existing code ...

  @doc """
  Execute a pipeline node from the AST.
  """
  defp execute_pipeline_node(%Types.Pipeline{} = pipeline, context, session_id) do
    # Extract commands from AST
    commands = extract_pipeline_commands(pipeline)
    
    # Classify each command
    classified = Enum.map(commands, fn cmd ->
      {cmd, is_builtin?(cmd.name)}
    end)
    
    # Route based on composition
    cond do
      all_builtins?(classified) ->
        execute_builtin_pipeline(commands, context, session_id)
      
      all_externals?(classified) ->
        execute_external_pipeline(commands, context, session_id)
      
      true ->
        execute_mixed_pipeline(classified, context, session_id)
    end
  end

  defp execute_builtin_pipeline(commands, context, session_id) do
    Enum.reduce(commands, {context, Stream.concat([])}, fn cmd, {ctx, input_stream} ->
      {name, args} = extract_command_parts(cmd)
      {new_ctx, output_stream, _stderr, _code} = 
        RShell.Builtins.execute(name, args, input_stream, ctx)
      {new_ctx, output_stream}
    end)
  end

  defp execute_external_pipeline(commands, context, session_id) do
    # Convert to command lists
    cmd_lists = Enum.map(commands, fn cmd ->
      {name, args} = extract_command_parts(cmd)
      [name | args]
    end)
    
    # Spawn pipeline
    {:ok, handle} = RShell.Pipeline.spawn(cmd_lists)
    
    # Read output
    output_stream = RShell.Pipeline.stdout_reader(handle)
    
    # Display
    display_to_terminal(output_stream)
    
    # Wait
    {:ok, exit_codes} = RShell.Pipeline.wait(handle)
    
    {context, List.last(exit_codes)}
  end

  defp execute_mixed_pipeline(classified_cmds, context, session_id) do
    segments = segment_pipeline(classified_cmds)
    
    Enum.reduce(segments, {context, Stream.concat([])}, fn segment, {ctx, input} ->
      case segment do
        {:builtin, cmd} ->
          execute_builtin_command(cmd, input, ctx)
        
        {:external_run, ext_cmds} ->
          execute_external_run(ext_cmds, input, ctx)
      end
    end)
  end

  defp execute_external_run(ext_cmds, input_stream, context) do
    # Build command lists
    cmd_lists = Enum.map(ext_cmds, fn cmd ->
      {name, args} = extract_command_parts(cmd)
      [name | args]
    end)
    
    # Spawn
    {:ok, handle} = RShell.Pipeline.spawn(cmd_lists)
    
    # Feed input in background
    Task.start(fn ->
      input_stream
      |> Stream.map(&RShell.Streamable.to_text/1)
      |> Stream.into(RShell.Pipeline.stdin_writer(handle))
      |> Stream.run()
    end)
    
    # Get output stream
    output_stream = RShell.Pipeline.stdout_reader(handle)
    
    {context, output_stream}
  end

  defp display_to_terminal(stream) do
    stream
    |> Stream.map(&RShell.Streamable.to_text/1)
    |> Enum.each(&IO.write/1)
  end
end
```

---

## Redirection Support

### File Redirections

```bash
# Output redirection
command > file.txt      # Overwrite
command >> file.txt     # Append
command 2> error.txt    # Stderr
command &> all.txt      # Both stdout and stderr

# Input redirection
command < input.txt
```

### Implementation Strategy

```elixir
defp handle_redirects(%Types.Command{redirect: redirects}, stream, context) do
  Enum.reduce(redirects, stream, fn redirect, acc_stream ->
    case redirect do
      %Types.FileRedirect{operator: ">", file: file} ->
        # Write stream to file (overwrite)
        write_stream_to_file(acc_stream, file, [:write])
        Stream.concat([])  # Empty stream (consumed)
      
      %Types.FileRedirect{operator: ">>", file: file} ->
        # Append stream to file
        write_stream_to_file(acc_stream, file, [:append])
        Stream.concat([])
      
      %Types.FileRedirect{operator: "<", file: file} ->
        # Read file as stream
        File.stream!(file)
      
      _ ->
        acc_stream
    end
  end)
end

defp write_stream_to_file(stream, filename, modes) do
  {:ok, file} = File.open(filename, modes)
  
  stream
  |> Stream.map(&RShell.Streamable.to_text/1)
  |> Stream.into(IO.stream(file, :line))
  |> Stream.run()
  
  File.close(file)
end
```

---

## Complete Example: Mixed Pipeline

```elixir
# Example: ls_struct | grep foo | external_wc -l | builtin_parse

# 1. ls_struct produces FileInfo structs
def shell_ls([], _stdin, context) do
  files = File.ls!(".")
  stream = Stream.map(files, fn name ->
    stat = File.stat!(name)
    %FileInfo{name: name, size: stat.size, ...}
  end)
  {context, stream, Stream.concat([]), 0}
end

# 2. grep works on ANY stream type
def shell_grep([pattern], stdin, context) do
  filtered = Stream.filter(stdin, fn item ->
    text = RShell.Streamable.to_text(item)
    String.contains?(text, pattern)
  end)
  {context, filtered, Stream.concat([]), 0}
end

# 3. External wc receives text (auto-converted)
# Runtime converts FileInfo stream → text stream → wc stdin

# 4. builtin_parse receives text stream from wc
def shell_parse([], stdin, context) do
  result = stdin
    |> Enum.to_list()
    |> List.first()
    |> String.trim()
    |> String.to_integer()
  
  {context, stream("Parsed: #{result}\n"), stream(""), 0}
end
```

**Data flow**:
1. `ls_struct` → Stream of `%FileInfo{}`
2. `grep` → Filtered Stream of `%FileInfo{}`
3. Runtime → Converts `%FileInfo{}` to text via `to_text/1`
4. `wc` → Receives text, outputs "5\n"
5. `parse` → Receives text stream, parses integer

---

## Summary

### Key Design Decisions

| Decision | Rationale |
|----------|-----------|
| **Stream-only I/O** | Uniform type, no conversion between builtins |
| **Protocol conversion** | Automatic text conversion only at boundaries |
| **Rust NIF for pipes** | OS-level efficiency, file descriptor control |
| **Lazy evaluation** | Memory-efficient for large datasets |
| **Structured data support** | PowerShell-like rich object pipelines |

### Implementation Checklist

- [x] Design Stream-only architecture
- [x] Design Protocol for type conversion
- [ ] Implement `RShell.Pipeline` Elixir module
- [ ] Implement Rust pipeline NIF functions
- [ ] Update `RShell.Builtins` to use Stream helpers
- [ ] Implement `RShell.Streamable` protocol
- [ ] Add redirection support
- [ ] Write integration tests
- [ ] Document builtin creation guide

This design provides the foundation for efficient, flexible pipelines that support both traditional text streams and modern structured data!