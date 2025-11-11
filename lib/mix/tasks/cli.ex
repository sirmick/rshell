defmodule Mix.Tasks.Cli do
  @moduledoc """
  Runs the RShell interactive CLI.

  ## Usage

      mix cli

  This starts the incremental parser and waits for input from stdin.
  Type .help for available commands.
  """

  use Mix.Task

  @shortdoc "Run the RShell interactive CLI"

  def run(_args) do
    # Start the application
    Mix.Task.run("app.start")

    # Run the CLI (which will block on stdin)
    RShell.CLI.main([])
  end
end
