defmodule TypedASTTest do
  use ExUnit.Case

  def print_typed_ast(ast, indent \\ 0) do
    padding = String.duplicate("  ", indent)

    cond do
      # Check if it's a typed struct by looking for __struct__
      is_struct(ast) ->
        module_name = ast.__struct__ |> Module.split() |> List.last()
        source = ast.source_info
        text_preview = String.slice(source.text || "", 0, 30)

        IO.puts("#{padding}[#{module_name}] (#{source.start_line}:#{source.start_column}-#{source.end_line}:#{source.end_column}) '#{text_preview}'")

        # Recursively print all fields (excluding source_info and __struct__)
        ast
        |> Map.from_struct()
        |> Map.drop([:source_info, :__struct__])
        |> Enum.each(fn {field, value} ->
          case value do
            nil -> :skip
            [] -> :skip
            list when is_list(list) ->
              IO.puts("#{padding}  .#{field}:")
              Enum.each(list, &print_typed_ast(&1, indent + 2))
            val when is_struct(val) ->
              IO.puts("#{padding}  .#{field}:")
              print_typed_ast(val, indent + 2)
            val when is_map(val) ->
              IO.puts("#{padding}  .#{field}:")
              print_typed_ast(val, indent + 2)
            _ ->
              IO.puts("#{padding}  .#{field}: #{inspect(value, limit: 3)}")
          end
        end)

      is_map(ast) ->
        # Fallback for untyped maps
        IO.puts("#{padding}[map] #{inspect(ast.type || "unknown", limit: 3)}")

      true ->
        IO.puts("#{padding}#{inspect(ast, limit: 3)}")
    end
  end

  test "convert generic AST to typed AST" do
    script = """
    USER="admin"
    if [ "$USER" = "admin" ]; then
        echo "Admin access"
    fi
    """

    # RShell.parse now returns typed structs directly
    {:ok, typed_ast} = RShell.parse(script)

    IO.puts("\n✨ TYPED AST (from RShell.parse):")
    IO.puts("Type: #{inspect(typed_ast.__struct__)}")
    print_typed_ast(typed_ast)

    # Verify it's a typed struct
    assert is_struct(typed_ast)
    assert typed_ast.__struct__ == BashParser.AST.Types.Program
    assert is_struct(typed_ast.source_info)
    assert typed_ast.source_info.__struct__ == BashParser.AST.Types.SourceInfo
  end

  test "typed AST preserves all information" do
    script = "NAME=\"test\""

    {:ok, typed_ast} = RShell.parse(script)

    IO.puts("\n🔍 Typed AST Information:")
    IO.puts("Typed module: #{typed_ast.__struct__}")

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

    IO.puts("\n🌳 NESTED TYPED AST STRUCTURE:")
    print_typed_ast(typed_ast)

    # Verify it's properly typed
    assert is_struct(typed_ast)
    assert typed_ast.__struct__ == BashParser.AST.Types.Program
  end
end
