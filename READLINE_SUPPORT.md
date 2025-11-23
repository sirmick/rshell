# Readline Support in RShell

**Status**: ✅ Implemented (v0.1.0)
**Last Updated**: 2025-11-22

---

## Overview

RShell CLI now includes **readline-like support** for command history and line editing in interactive mode. This provides a familiar bash-like experience with:

- ✅ **Command history** - Use arrow keys to navigate previous commands
- ✅ **Persistent history** - Commands saved across sessions in `~/.rshell_history`
- ✅ **Line editing** - Edit commands with standard keyboard shortcuts
- ✅ **History search** - Search through command history

## Features

### Command History

- **Up/Down arrows**: Navigate through command history
- **Ctrl+R**: Reverse search through history (if supported by terminal)
- **Automatic persistence**: History saved to `~/.rshell_history` after each command

### Line Editing

Standard GNU Readline keybindings:

- **Left/Right arrows**: Move cursor
- **Ctrl+A**: Move to beginning of line
- **Ctrl+E**: Move to end of line
- **Ctrl+K**: Delete from cursor to end of line
- **Ctrl+U**: Delete from cursor to beginning of line
- **Backspace/Delete**: Delete characters

### History Management

- **History file**: `~/.rshell_history` in your home directory
- **Auto-save**: Each command automatically appended to history file
- **Smart filtering**: Dot commands (`.help`, `.quit`, etc.) are NOT saved to history
- **Empty lines ignored**: Only actual commands are saved

## Implementation Details

### Technology Stack

- **Library**: [ExReadline](https://hex.pm/packages/ex_readline) v0.1.0
- **Backend**: GNU Readline (system library)
- **Platform**: Linux/macOS (requires GNU Readline installed)

### How It Works

1. **Startup**: RShell loads history from `~/.rshell_history` on launch
2. **Input**: ExReadline provides readline functionality via NIF bindings
3. **History**: Each command is added to in-memory history AND appended to file
4. **Filtering**: Only regular commands are saved (no dot commands, no empty lines)

### Code Changes

**Files Modified**:
- [`mix.exs`](mix.exs:30) - Added `{:ex_readline, "~> 0.1.0"}` dependency
- [`lib/r_shell/cli.ex`](lib/r_shell/cli.ex:524-541) - Replaced `IO.gets/1` with `ExReadline.read_line/1`
- [`lib/r_shell/cli.ex`](lib/r_shell/cli.ex:382-408) - Added history initialization and persistence

**Key Functions**:
- `setup_readline_history/1` - Load history from file on startup
- `save_to_history_file/1` - Append command to history file
- `loop/1` - Main REPL loop using ExReadline

## Installation

### System Requirements

ExReadline requires GNU Readline to be installed on your system.

**Linux**:
```bash
# Debian/Ubuntu
sudo apt-get install libreadline-dev

# Fedora/RHEL
sudo dnf install readline-devel

# Arch
sudo pacman -S readline
```

**macOS**:
```bash
# Usually pre-installed, but if needed:
brew install readline
```

**Windows**:
- GNU Readline support is limited on Windows
- Consider using WSL2 for full readline functionality

## Interactive Commands

Besides executing bash scripts, RShell provides several dot commands:

- `.help` - Show available commands
- `.help <builtin>` - Show help for a specific builtin (e.g., `.help echo`)
- `.status` - Show parser and runtime status
- `.ast` - Show full accumulated AST
- `.last` - Show incremental changes from last parse
- `.result` - Show last execution result with full details
- `.stdout` - Show stdout from last execution
- `.stderr` - Show stderr from last execution
- `.debug` - Toggle debug logging on/off (default: OFF)
- `.reset` - Clear parser state
- `.quit` / `.exit` - Exit the shell

## Debug Mode

By default, RShell runs with debug logging disabled (logger level: `:warning`). To see detailed execution information, use the `.debug` command:

```bash
rshell> .debug
🔧 Debug logging is now ON
   Logger level: debug

rshell> echo hello
05:12:13.410 [debug] ExecutionPipeline.run_execution: do_execute_node returned context.exit_code=0
hello

rshell> .debug
🔧 Debug logging is now OFF
   Logger level: warning

rshell> echo world
world
```

Debug mode shows:
- Parser initialization details
- AST node processing
- Execution flow through control structures
- Context updates and state changes
- Performance metrics

**Recommendation**: Keep debug mode off during normal use for cleaner output.

### Project Setup

1. **Fetch dependencies**:
   ```bash
   mix deps.get
   ```

2. **Compile project**:
   ```bash
   mix compile
   ```

3. **Run interactive shell**:
   ```bash
   mix cli
   # or
   ./rshell
   ```

## Usage Examples

### Basic Usage

```bash
$ mix cli

🐚 RShell - Interactive Bash Shell
==================================================
Type bash commands. Built-in commands start with '.'
Type .help for available commands

✅ Parser started (PID: #PID<0.123.0>)
✅ Runtime started (PID: #PID<0.124.0>)
📡 Session ID: cli_123456

rshell> echo "Hello World"
Hello World

rshell> pwd
/home/user/rshell

# Press UP arrow to recall previous command
rshell> pwd    # (recalled from history)
/home/user/rshell

# Press UP again to go back further
rshell> echo "Hello World"    # (two commands back)
Hello World

rshell> .quit
👋 Goodbye!
```

### History Persistence

Commands are saved to `~/.rshell_history`:

```bash
$ cat ~/.rshell_history
echo "Hello World"
pwd
X=5
echo $X
for i in 1 2 3; do echo $i; done
```

**Note**: Dot commands (`.help`, `.quit`, etc.) are NOT saved to history.

### Multi-Line Commands

Multi-line commands (like control structures) are saved as complete units:

```bash
rshell> for i in 1 2 3; do
     >   echo $i
     > done
1
2
3

# Entire for loop is saved as one history entry
```

## Troubleshooting

### "ExReadline not found" Error

**Cause**: GNU Readline not installed or not in library path

**Solution**:
```bash
# Install readline development libraries
sudo apt-get install libreadline-dev  # Debian/Ubuntu
sudo dnf install readline-devel        # Fedora/RHEL

# Recompile dependencies
mix deps.clean ex_readline
mix deps.get
mix compile
```

### History Not Saving

**Check permissions**:
```bash
ls -la ~/.rshell_history
# Should be writable by current user
```

**Check file location**:
```bash
# History file should exist after first command
ls -la ~/.rshell_history
```

### History Not Loading

**Verify file exists**:
```bash
cat ~/.rshell_history
```

**Check for errors in CLI startup**:
- Errors loading history are silently ignored
- File is created on first command if it doesn't exist

## Configuration

Currently, history configuration is hardcoded:

- **History file**: `~/.rshell_history` (fixed location)
- **Max history size**: Unlimited (all commands saved)
- **Filtering**: Dot commands and empty lines excluded

### Future Enhancements

Planned features:
- [ ] Configurable history file location via env var
- [ ] Max history size limit
- [ ] History search command (`.history`)
- [ ] Clear history command (`.clear-history`)
- [ ] Tab completion for builtins and files

## Architecture

### Component Interaction

```
┌─────────────────────────────────────────┐
│         RShell CLI (Interactive)         │
│                                          │
│  ┌────────────────────────────────────┐ │
│  │   ExReadline (NIF wrapper)          │ │
│  │   - readline() for input            │ │
│  │   - add_to_history() for storage    │ │
│  └─────────┬──────────────────────────┘ │
│            │                              │
│            ↓                              │
│  ┌────────────────────────────────────┐ │
│  │   GNU Readline (C library)          │ │
│  │   - Line editing                    │ │
│  │   - History management              │ │
│  │   - Keybindings                     │ │
│  └────────────────────────────────────┘ │
└─────────────────────────────────────────┘
            │
            ↓
  ┌──────────────────┐
  │ ~/.rshell_history│  (Persistent storage)
  └──────────────────┘
```

### Data Flow

1. **User presses key** → Terminal
2. **GNU Readline** → Processes keypress (editing, history navigation)
3. **ExReadline NIF** → Wraps readline call
4. **RShell CLI** → Receives complete line
5. **History saved** → Appended to `~/.rshell_history`
6. **Command executed** → Parser → Runtime

## Comparison with Other Shells

| Feature | Bash | RShell | Notes |
|---------|------|--------|-------|
| Command history | ✅ | ✅ | Via ExReadline |
| History search (Ctrl+R) | ✅ | ✅ | Terminal-dependent |
| Persistent history | ✅ | ✅ | `~/.rshell_history` |
| Tab completion | ✅ | ⏳ | Planned |
| History size limit | ✅ | ❌ | Not yet configured |
| History deduplication | ✅ | ❌ | Future enhancement |

## Related Documentation

- [CLI Implementation](lib/r_shell/cli.ex) - Main CLI module
- [ExReadline Documentation](https://hexdocs.pm/ex_readline/) - Library docs
- [GNU Readline Manual](https://tiswww.case.edu/php/chet/readline/rltop.html) - Readline docs

---

**Implementation Status**: ✅ Complete - readline support is fully functional in RShell interactive mode!