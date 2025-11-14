defmodule RShell.CLI.ExecutionRecord do
  @moduledoc """
  Complete record of a single execution with metrics and results.

  Captures everything: input, AST, metrics, output, context.

  ## Fields

  - `fragment` - Input script fragment
  - `timestamp` - DateTime.utc_now()
  - `parse_metrics` - Metrics.t()
  - `exec_metrics` - Metrics.t()
  - `incremental_ast` - Just the new AST nodes
  - `full_ast` - Complete accumulated AST
  - `execution_result` - Raw {:execution_result, ...} event
  - `exit_code` - Integer exit code
  - `stdout` - [any()] - Native terms
  - `stderr` - [any()] - Native terms
  - `context` - Final runtime context
  """

  alias RShell.CLI.Metrics

  defstruct [
    :fragment,           # Input script fragment
    :timestamp,          # DateTime.utc_now()
    :parse_metrics,      # Metrics.t()
    :exec_metrics,       # Metrics.t()
    :incremental_ast,    # Just the new AST nodes
    :full_ast,           # Complete accumulated AST
    :execution_result,   # Raw {:execution_result, ...} event
    :exit_code,          # Integer exit code
    :stdout,             # [any()] - Native terms
    :stderr,             # [any()] - Native terms
    :context             # Final runtime context
  ]

  @type t :: %__MODULE__{
    fragment: String.t(),
    timestamp: DateTime.t(),
    parse_metrics: Metrics.t(),
    exec_metrics: Metrics.t(),
    incremental_ast: term(),
    full_ast: term(),
    execution_result: map(),
    exit_code: integer(),
    stdout: [any()],
    stderr: [any()],
    context: map()
  }
end
