defmodule RShell.CLI.Metrics do
  @moduledoc """
  Elegant metrics collection for parsing and execution.

  Uses start/stop pattern for clean measurement.

  ## Example

      m = Metrics.start()
      # ... do work ...
      m = Metrics.stop(m)
      IO.puts("Duration: \#{m.duration_us}μs")
      IO.puts("Memory: \#{m.memory_delta} bytes")
  """

  defstruct [
    # System.monotonic_time(:microsecond)
    :start_time,
    # System.monotonic_time(:microsecond)
    :end_time,
    # end_time - start_time
    :duration_us,
    # :erlang.memory(:total)
    :memory_before,
    # :erlang.memory(:total)
    :memory_after,
    # memory_after - memory_before
    :memory_delta
  ]

  @type t :: %__MODULE__{
          start_time: integer() | nil,
          end_time: integer() | nil,
          duration_us: integer() | nil,
          memory_before: integer() | nil,
          memory_after: integer() | nil,
          memory_delta: integer() | nil
        }

  @doc "Start measuring"
  @spec start() :: t()
  def start do
    %__MODULE__{
      start_time: System.monotonic_time(:microsecond),
      memory_before: :erlang.memory(:total)
    }
  end

  @doc "Stop measuring and compute deltas"
  @spec stop(t()) :: t()
  def stop(%__MODULE__{} = metrics) do
    end_time = System.monotonic_time(:microsecond)
    memory_after = :erlang.memory(:total)

    %{
      metrics
      | end_time: end_time,
        duration_us: end_time - metrics.start_time,
        memory_after: memory_after,
        memory_delta: memory_after - metrics.memory_before
    }
  end
end
