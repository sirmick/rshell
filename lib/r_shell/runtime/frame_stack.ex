defmodule RShell.Runtime.FrameStack do
  @moduledoc """
  Manages a stack of execution frames with variable scoping and output handling.

  The FrameStack maintains:
  - A stack of execution frames (current frame on top)
  - Global context (env, cwd, exit_code, command_count)
  - Frame-based variable scoping with parent chain lookup
  - Output accumulation based on current frame's mode

  ## Usage

      # Initialize with global frame
      stack = FrameStack.new(output_mode: :isolate, context: context)

      # Push a loop frame
      stack = FrameStack.push_frame(stack, :loop, :accumulate)

      # Execute commands and accumulate output...

      # Pop frame to get accumulated output
      {stack, output} = FrameStack.pop_frame(stack)
  """

  alias RShell.Runtime.Frame

  @type t :: %__MODULE__{
          frames: [Frame.t()],
          global_context: map()
        }

  defstruct frames: [],
            global_context: %{}

  @doc """
  Create a new frame stack with a global frame.

  ## Options

  - `:output_mode` - Output mode for global frame (default: `:isolate`)
  - `:context` - Initial context map with `env`, `cwd`, `exit_code`, `command_count`

  ## Examples

      iex> stack = RShell.Runtime.FrameStack.new()
      iex> length(stack.frames)
      1
      iex> stack.global_context.cwd
      "/"
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    output_mode = Keyword.get(opts, :output_mode, :isolate)

    context =
      Keyword.get(opts, :context, %{
        env: %{},
        cwd: "/",
        exit_code: 0,
        command_count: 0
      })

    # Start with a global frame
    global_frame = Frame.new(:global, output_mode)

    %__MODULE__{
      frames: [global_frame],
      global_context: context
    }
  end

  @doc """
  Push a new frame onto the stack.

  ## Examples

      iex> stack = RShell.Runtime.FrameStack.new()
      iex> stack = RShell.Runtime.FrameStack.push_frame(stack, :loop, :accumulate)
      iex> length(stack.frames)
      2
      iex> RShell.Runtime.FrameStack.current_frame(stack).type
      :loop
  """
  @spec push_frame(t(), Frame.frame_type(), Frame.output_mode(), map()) :: t()
  def push_frame(%__MODULE__{frames: frames} = stack, type, output_mode, metadata \\ %{}) do
    new_frame = Frame.new(type, output_mode, metadata)
    %{stack | frames: [new_frame | frames]}
  end

  @doc """
  Pop the current frame from the stack and return accumulated output.

  Returns a tuple of {updated_stack, accumulated_output}.

  ## Examples

      iex> stack = RShell.Runtime.FrameStack.new()
      iex> stack = RShell.Runtime.FrameStack.push_frame(stack, :loop, :accumulate)
      iex> {stack, output} = RShell.Runtime.FrameStack.pop_frame(stack)
      iex> length(stack.frames)
      1
      iex> output
      %{stdout: [], stderr: []}
  """
  @spec pop_frame(t()) :: {t(), map()}
  def pop_frame(%__MODULE__{frames: [current | rest]} = stack) do
    # Return stack without current frame and the accumulated output
    {%{stack | frames: rest}, current.accumulated}
  end

  @doc """
  Get the current (top) frame from the stack.

  ## Examples

      iex> stack = RShell.Runtime.FrameStack.new()
      iex> frame = RShell.Runtime.FrameStack.current_frame(stack)
      iex> frame.type
      :global
  """
  @spec current_frame(t()) :: Frame.t()
  def current_frame(%__MODULE__{frames: [current | _]}), do: current

  @doc """
  Get the output mode of the current frame.

  ## Examples

      iex> stack = RShell.Runtime.FrameStack.new(output_mode: :isolate)
      iex> RShell.Runtime.FrameStack.output_mode(stack)
      :isolate
  """
  @spec output_mode(t()) :: Frame.output_mode()
  def output_mode(stack) do
    current_frame(stack).output_mode
  end

  @doc """
  Get a variable value by searching up the scope chain.

  Searches frames from top to bottom (current → parent → ... → global),
  then falls back to global_context.env.

  ## Examples

      iex> stack = RShell.Runtime.FrameStack.new(context: %{env: %{"GLOBAL" => "value"}})
      iex> RShell.Runtime.FrameStack.get_variable(stack, "GLOBAL")
      "value"

      iex> stack = RShell.Runtime.FrameStack.new()
      iex> stack = RShell.Runtime.FrameStack.set_variable(stack, "X", 42)
      iex> RShell.Runtime.FrameStack.get_variable(stack, "X")
      42
  """
  @spec get_variable(t(), String.t()) :: term()
  def get_variable(%__MODULE__{frames: frames, global_context: context}, name) do
    # Search frames from top to bottom (current -> parent -> ... -> global)
    Enum.find_value(frames, fn frame ->
      Map.get(frame.scope, name)
    end) || Map.get(context.env || %{}, name)
  end

  @doc """
  Set a variable in the current frame's scope.

  ## Examples

      iex> stack = RShell.Runtime.FrameStack.new()
      iex> stack = RShell.Runtime.FrameStack.set_variable(stack, "X", 42)
      iex> RShell.Runtime.FrameStack.get_variable(stack, "X")
      42
  """
  @spec set_variable(t(), String.t(), term()) :: t()
  def set_variable(%__MODULE__{frames: [current | rest]} = stack, name, value) do
    # Set in current frame's scope
    new_scope = Map.put(current.scope, name, value)
    updated_frame = %{current | scope: new_scope}
    %{stack | frames: [updated_frame | rest]}
  end

  @doc """
  Update a variable in the global environment.

  This is used for assignments that should persist across frames.

  ## Examples

      iex> stack = RShell.Runtime.FrameStack.new()
      iex> stack = RShell.Runtime.FrameStack.update_global_env(stack, "PATH", "/usr/bin")
      iex> stack.global_context.env["PATH"]
      "/usr/bin"
  """
  @spec update_global_env(t(), String.t(), term()) :: t()
  def update_global_env(%__MODULE__{global_context: context} = stack, name, value) do
    new_env = Map.put(context.env || %{}, name, value)
    %{stack | global_context: %{context | env: new_env}}
  end
end
