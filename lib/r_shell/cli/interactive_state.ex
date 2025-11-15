defmodule RShell.CLI.InteractiveState do
  @moduledoc """
  State for interactive REPL session.

  Manages the state of an interactive RShell session including:
  - Parser and Runtime PIDs
  - Session ID
  - Last AST metadata (for .ast/.last commands)
  - Input buffer (multi-line accumulation)
  - CLI state (for execution history)
  """

  alias RShell.CLI.State

  defstruct [
    :parser_pid,
    :runtime_pid,
    :session_id,
    # For .ast/.last commands - stores metadata from last parse
    :last_ast_metadata,
    # Input buffer for multi-line accumulation
    :input_buffer,
    # Previous children from AST (for tracking incremental changes)
    :previous_children,
    # CLI state with execution history
    :cli_state
  ]

  @type t :: %__MODULE__{
          parser_pid: pid(),
          runtime_pid: pid(),
          session_id: String.t(),
          last_ast_metadata: map() | nil,
          input_buffer: String.t(),
          previous_children: list(),
          cli_state: State.t()
        }

  @doc """
  Create a new interactive state from a CLI state.

  ## Examples

      {:ok, cli_state} = RShell.CLI.State.new()
      istate = RShell.CLI.InteractiveState.new(cli_state)
  """
  @spec new(State.t()) :: t()
  def new(%State{} = cli_state) do
    %__MODULE__{
      parser_pid: cli_state.parser_pid,
      runtime_pid: cli_state.runtime_pid,
      session_id: cli_state.session_id,
      last_ast_metadata: nil,
      input_buffer: "",
      previous_children: [],
      cli_state: cli_state
    }
  end

  @doc """
  Update the CLI state after execution.

  Called after each command execution to update the execution history.
  """
  @spec update_cli_state(t(), State.t()) :: t()
  def update_cli_state(%__MODULE__{} = istate, %State{} = cli_state) do
    %{istate | cli_state: cli_state}
  end

  @doc """
  Update the last AST metadata.

  Called after parsing to store metadata for .ast/.last commands.
  """
  @spec update_ast_metadata(t(), map() | nil) :: t()
  def update_ast_metadata(%__MODULE__{} = istate, metadata) do
    %{istate | last_ast_metadata: metadata}
  end

  @doc """
  Update the input buffer.

  Called when accumulating multi-line input.
  """
  @spec update_input_buffer(t(), String.t()) :: t()
  def update_input_buffer(%__MODULE__{} = istate, buffer) do
    %{istate | input_buffer: buffer}
  end

  @doc """
  Clear the input buffer.

  Called after successful execution or on error.
  """
  @spec clear_input_buffer(t()) :: t()
  def clear_input_buffer(%__MODULE__{} = istate) do
    %{istate | input_buffer: ""}
  end

  @doc """
  Get the last execution record from history.

  Returns the most recent execution record, or nil if no history.
  """
  @spec get_last_record(t()) :: RShell.CLI.ExecutionRecord.t() | nil
  def get_last_record(%__MODULE__{cli_state: %State{history: history}}) do
    List.last(history)
  end

  @doc """
  Reset the interactive state.

  Clears input buffer, AST metadata, and previous children.
  Keeps CLI state (execution history).
  """
  @spec reset(t()) :: t()
  def reset(%__MODULE__{} = istate) do
    %{istate |
      input_buffer: "",
      last_ast_metadata: nil,
      previous_children: []
    }
  end
end
