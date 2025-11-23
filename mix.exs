defmodule RShell.MixProject do
  use Mix.Project

  def project do
    [
      app: :rshell,
      version: "0.1.0",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      # Exclude helper files from test pattern to suppress warnings
      test_pattern: "*_test.exs",
      test_ignore_filters: ["test/support/*", "test/test_helpers/*"]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {RShell.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:rustler, "~> 0.30.0"},
      {:rustler_precompiled, "~> 0.7.0"},
      {:jason, "~> 1.4"},
      {:phoenix_pubsub, "~> 2.1"},
      {:warpath, "~> 0.6"},
      {:ex_readline, "~> 0.1.0"}
    ]
  end
end
