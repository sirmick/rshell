defmodule RShell.Runtime.ExecutionState do
  @moduledoc """
  Unified execution state containing both context and frame stack.

  This struct is passed through execution functions, providing a clean
  way to access both legacy context and the new frame-based execution model.

  ## Fields

  - `context` - Legacy execution context (env, cwd, exit_code, last_output)
  - `frame_stack` - Frame-based execution stack
  - `session_id` - Session identifier for PubSub broadcasting
  """

  alias RShell.Runtime.FrameStack

  @type t :: %__MODULE__{
          context: map(),
          frame_stack: FrameStack.t(),
          session_id: String.t()
        }

  defstruct [:context, :frame_stack, :session_id]

  @doc """
  Create a new execution state from Runtime GenServer state.

  ## Examples

      iex> runtime_state = %{context: context, frame_stack: stack, session_id: "test"}
      iex> exec_state = RShell.Runtime.ExecutionState.from_runtime_state(runtime_state)
      iex> exec_state.session_id
      "test"
  """
  @spec from_runtime_state(map()) :: t()
  def from_runtime_state(runtime_state) do
    %__MODULE__{
      context: runtime_state.context,
      frame_stack: runtime_state.frame_stack,
      session_id: runtime_state.session_id
    }
  end

  @doc """
  Extract context and frame_stack to update Runtime GenServer state.

  Returns a map with :context and :frame_stack keys suitable for
  updating the Runtime GenServer state.

  ## Examples

      iex> exec_state = %ExecutionState{context: ctx, frame_stack: stack, session_id: "test"}
      iex> updates = ExecutionState.to_runtime_updates(exec_state)
      iex> Map.keys(updates)
      [:context, :frame_stack]
  """
  @spec to_runtime_updates(t()) :: %{context: map(), frame_stack: FrameStack.t()}
  def to_runtime_updates(state) do
    %{
      context: state.context,
      frame_stack: state.frame_stack
    }
  end
end
