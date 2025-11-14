defmodule RShell.CLI.State do
  @moduledoc """
  CLI state tracking all executions and metrics.

  Maintains:
  - Session components (parser, runtime PIDs)
  - Execution history (ordered list)
  - Options and configuration

  ## Example

      {:ok, state} = State.new()
      # ... use state ...
      {:ok, state} = State.reset(state)
  """

  alias RShell.CLI.ExecutionRecord

  defstruct [
    :session_id,
    :parser_pid,
    :runtime_pid,
    :history,          # [ExecutionRecord.t()]
    :options,          # Keyword list
    :initial_env,      # For reset
    :initial_cwd       # For reset
  ]

  @type t :: %__MODULE__{
    session_id: String.t(),
    parser_pid: pid(),
    runtime_pid: pid(),
    history: [ExecutionRecord.t()],
    options: keyword(),
    initial_env: map(),
    initial_cwd: String.t()
  }

  @doc "Create new CLI state"
  @spec new(keyword()) :: {:ok, t()} | {:error, term()}
  def new(opts \\ []) do
    session_id = Keyword.get(opts, :session_id, generate_session_id())
    env = Keyword.get(opts, :env, System.get_env())
    cwd = Keyword.get(opts, :cwd, System.get_env("PWD") || File.cwd!())

    # Start parser and runtime
    {:ok, parser} = RShell.IncrementalParser.start_link(
      session_id: session_id,
      broadcast: true
    )

    {:ok, runtime} = RShell.Runtime.start_link(
      session_id: session_id,
      auto_execute: true,
      env: env,
      cwd: cwd
    )

    # Subscribe to events
    RShell.PubSub.subscribe(session_id, :all)

    {:ok, %__MODULE__{
      session_id: session_id,
      parser_pid: parser,
      runtime_pid: runtime,
      history: [],
      options: opts,
      initial_env: env,
      initial_cwd: cwd
    }}
  end

  # Generate a unique session ID
  @spec generate_session_id() :: String.t()
  defp generate_session_id do
    "cli_#{System.unique_integer([:positive, :monotonic])}"
  end
end
