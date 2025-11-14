defmodule ParserRuntimeIntegrationTest do
  use ExUnit.Case, async: false

  alias RShell.{IncrementalParser, Runtime, PubSub}
  alias RShell.TestHelpers.ExecutionHelper

  setup do
    session_id = "test_#{:rand.uniform(1000000)}"

    {:ok, parser} = IncrementalParser.start_link(
      session_id: session_id,
      broadcast: true
    )
    {:ok, runtime} = Runtime.start_link(
      session_id: session_id,
      auto_execute: true  # Auto-execute for integration
    )

    PubSub.subscribe(session_id, :all)

    {:ok, parser: parser, runtime: runtime, session_id: session_id}
  end

  test "end-to-end: parse and execute simple command", %{parser: parser} do
    # Submit command and collect result
    result = ExecutionHelper.execute_and_get_last(parser, "echo hello\n")

    # Verify execution succeeded with expected output
    ExecutionHelper.assert_execution_success(result)
    stdout_str = ExecutionHelper.output_to_string(result.stdout)
    assert stdout_str =~ "hello"
  end

  # DeclarationCommand execution not yet implemented

  test "multiple commands execute in sequence", %{parser: parser, runtime: runtime} do
    # Execute three commands
    ExecutionHelper.execute_and_get_last(parser, "echo first\n")
    ExecutionHelper.execute_and_get_last(parser, "echo second\n")
    result = ExecutionHelper.execute_and_get_last(parser, "echo third\n")

    # Verify last command executed successfully
    ExecutionHelper.assert_execution_success(result)
    stdout_str = ExecutionHelper.output_to_string(result.stdout)
    assert stdout_str =~ "third"

    # Check command count
    context = Runtime.get_context(runtime)
    assert context.command_count == 3
  end

  test "incomplete structures don't execute", %{parser: parser} do
    # Submit incomplete if statement
    IncrementalParser.append_fragment(parser, "if true; then\n")

    # Should get incremental AST update but no executable node
    assert_receive {:ast_incremental, _}, 1000
    refute_receive {:executable_node, _, _}, 500
    refute_receive {:execution_result, _}, 100
  end
end
