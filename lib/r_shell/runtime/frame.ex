defmodule RShell.Runtime.Frame do
  @moduledoc """
  Represents an execution frame with scope, output mode, and metadata.

  Frames are the building blocks of the execution stack. Each frame represents
  a distinct execution context such as:
  - Global/interactive commands
  - Loop iterations
  - Function calls
  - Subshell execution
  - Command substitution

  ## Frame Types

  - `:global` - Top-level execution context
  - `:loop` - For/while loop iteration
  - `:function` - Function call (future)
  - `:subshell` - Subshell execution (future)
  - `:command_substitution` - Command substitution `$(cmd)` (future)

  ## Output Modes

  - `:isolate` - Each command clears previous output (default for interactive)
  - `:accumulate` - Collect all outputs (for loops and blocks)
  - `:pipe` - Chain output to next command (future)
  - `:capture` - Capture output for substitution (future)
  """

  @type frame_type ::
          :global | :loop | :function | :subshell | :command_substitution

  @type output_mode ::
          :isolate | :accumulate | :pipe | :capture

  @type t :: %__MODULE__{
          type: frame_type(),
          output_mode: output_mode(),
          scope: map(),
          accumulated: map(),
          metadata: map(),
          parent_scope: map() | nil
        }

  defstruct type: :global,
            output_mode: :isolate,
            scope: %{},
            accumulated: %{stdout: [], stderr: []},
            metadata: %{},
            parent_scope: nil

  @doc """
  Create a new execution frame.

  ## Examples

      iex> frame = RShell.Runtime.Frame.new(:global, :isolate)
      iex> frame.type
      :global
      iex> frame.output_mode
      :isolate

      iex> frame = RShell.Runtime.Frame.new(:loop, :accumulate, %{iteration: 0})
      iex> frame.metadata.iteration
      0
  """
  @spec new(frame_type(), output_mode(), map()) :: t()
  def new(type, output_mode, metadata \\ %{}) do
    %__MODULE__{
      type: type,
      output_mode: output_mode,
      metadata: metadata,
      scope: %{},
      accumulated: %{stdout: [], stderr: []}
    }
  end
end
