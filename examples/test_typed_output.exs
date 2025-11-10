# Test script to demonstrate typed AST with nested structure
script = """
if [ "$DEBUG" = "true" ]; then
    echo "Debug mode"
fi
"""

{:ok, typed_ast} = RShell.parse(script)

defmodule ASTInspector do
  def print_typed(node, indent \\ 0) do
    prefix = String.duplicate("  ", indent)
    
    # Get module name and type
    module = node.__struct__
    type_name = String.replace_prefix(to_string(module), "Elixir.BashParser.AST.Types.", "")
    
    # Print node header
    src = node.source_info
    IO.puts("#{prefix}[#{type_name}] (#{src.start_line}:#{src.start_column}-#{src.end_line}:#{src.end_column})")
    
    # Print all fields (excluding source_info and __struct__)
    node
    |> Map.from_struct()
    |> Map.delete(:source_info)
    |> Enum.each(fn {field, value} ->
      case value do
        nil -> :skip
        list when is_list(list) and list != [] ->
          IO.puts("#{prefix}  .#{field}:")
          Enum.each(list, fn item ->
            if is_struct(item) do
              print_typed(item, indent + 2)
            else
              IO.puts("#{prefix}    #{inspect(item)}")
            end
          end)
        val when is_struct(val) ->
          IO.puts("#{prefix}  .#{field}:")
          print_typed(val, indent + 2)
        _ -> :skip
      end
    end)
  end
end

IO.puts("\n🌳 COMPLETE TYPED AST WITH NESTED FIELDS:\n")
ASTInspector.print_typed(typed_ast)
