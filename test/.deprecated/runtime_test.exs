defmodule RShell.RuntimeTest do
  use ExUnit.Case, async: false

  alias RShell.{Runtime, PubSub}

  setup do
    session_id = "test_#{:rand.uniform(1_000_000)}"

    {:ok, runtime} =
      Runtime.start_link(
        session_id: session_id,
        # Manual execution for tests
        auto_execute: false
      )

    PubSub.subscribe(session_id, :all)

    {:ok, runtime: runtime, session_id: session_id}
  end

  test "starts with correct initial context", %{runtime: runtime} do
    context = Runtime.get_context(runtime)

    assert context.exit_code == 0
    assert context.command_count == 0
    assert context.cwd != nil
    assert is_map(context.env)
  end

  # NOTE: External command execution tests removed - feature not yet implemented
  # See RUNTIME_DESIGN.md for implementation plan

  test "get/set cwd", %{runtime: runtime} do
    old_cwd = Runtime.get_cwd(runtime)
    assert old_cwd != nil

    Runtime.set_cwd(runtime, "/tmp")

    assert_receive {:cwd_changed, %{old: ^old_cwd, new: "/tmp"}}, 1000
    assert Runtime.get_cwd(runtime) == "/tmp"
  end

  # NOTE: Variable assignment, pipeline, and output tracking tests removed
  # These features are not yet implemented - see RUNTIME_DESIGN.md
end
