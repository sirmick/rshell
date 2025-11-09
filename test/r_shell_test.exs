defmodule RShellTest do
  use ExUnit.Case
  doctest RShell

  test "greets the world" do
    assert RShell.hello() == :world
  end
end
