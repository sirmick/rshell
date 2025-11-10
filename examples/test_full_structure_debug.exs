# Complete structure test
script = """
if [ "$DEBUG" = "true" ]; then
    echo "Debug mode"
fi
"""

{:ok, typed_ast} = RShell.parse(script)

IO.puts("\n🌳 FULL TYPED AST STRUCTURE:\n")
IO.inspect(typed_ast, pretty: true, limit: :infinity, width: 120)

IO.puts("\n\n📊 CHILDREN FIELD:")
IO.inspect(typed_ast.children, pretty: true, limit: :infinity, width: 120)

if typed_ast.children do
  IO.puts("\n\n✅ Children exist! Let's inspect the if_statement:")
  if_stmt = hd(typed_ast.children)
  IO.inspect(if_stmt, pretty: true, limit: :infinity, width: 120)

  IO.puts("\n\n🔍 Condition field:")
  IO.inspect(if_stmt.condition, pretty: true, limit: :infinity, width: 120)

  IO.puts("\n\n🔍 Children field of if_statement:")
  IO.inspect(if_stmt.children, pretty: true, limit: :infinity, width: 120)
else
  IO.puts("\n\n❌ Children is nil!")

  # Check the raw map
  IO.puts("\n\nLet's check the raw NIF output:")
  {:ok, raw} = BashParser.parse_bash(script)
  IO.inspect(Map.keys(raw), label: "Program keys")
  IO.inspect(raw["children"], label: "Program children from NIF", limit: 2)
end
