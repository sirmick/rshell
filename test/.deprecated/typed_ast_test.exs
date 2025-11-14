defmodule TypedASTTest do
  use ExUnit.Case

  test "convert generic AST to typed AST" do
    script = """
    USER="admin"
    if [ "$USER" = "admin" ]; then
        echo "Admin access"
    fi
    """

    # RShell.parse now returns typed structs directly
    {:ok, typed_ast} = RShell.parse(script)

    # Verify it's a typed struct
    assert is_struct(typed_ast)
    assert typed_ast.__struct__ == BashParser.AST.Types.Program
    assert is_struct(typed_ast.source_info)
    assert typed_ast.source_info.__struct__ == BashParser.AST.Types.SourceInfo
  end

  test "typed AST preserves all information" do
    script = "NAME=\"test\""

    {:ok, typed_ast} = RShell.parse(script)

    # Verify it's a Program struct
    assert is_struct(typed_ast)
    assert typed_ast.__struct__ == BashParser.AST.Types.Program

    # Source info should be present
    assert is_struct(typed_ast.source_info)
    assert typed_ast.source_info.start_line >= 0
    assert typed_ast.source_info.end_line >= 0
    assert is_binary(typed_ast.source_info.text)
  end

  test "nested structure conversion" do
    script = """
    if [ "$DEBUG" = "true" ]; then
        echo "Debug mode"
    fi
    """

    {:ok, typed_ast} = RShell.parse(script)

    # Verify it's properly typed
    assert is_struct(typed_ast)
    assert typed_ast.__struct__ == BashParser.AST.Types.Program
  end
end
