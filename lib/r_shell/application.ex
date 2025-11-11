defmodule RShell.Application do
  @moduledoc """
  RShell application supervisor.

  Starts and supervises the Phoenix.PubSub process for event-driven
  communication between Parser and Runtime components.
  """

  use Application

  require Logger

  @impl true
  def start(_type, _args) do
    children = [
      # PubSub for event-driven communication
      {Phoenix.PubSub, name: RShell.PubSub.pubsub_name()}
    ]

    opts = [strategy: :one_for_one, name: RShell.Supervisor]

    Logger.info("Starting RShell.Application with PubSub")
    Supervisor.start_link(children, opts)
  end
end
