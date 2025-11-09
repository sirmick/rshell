import Config

config :rshell, RShell.BashParser,
  crate: :rshell_bash_parser,
  mode: if(Mix.env() == :prod, do: :release, else: :debug),
  cargo_features: ""
