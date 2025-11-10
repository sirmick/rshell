# Debug script to see raw Rust NIF output
script = """
if [ "$DEBUG" = "true" ]; then
    echo "Debug mode"
fi
"""

# Get raw AST from NIF (before typed conversion)
raw_ast = BashParser.parse_bash(script)

IO.puts("\n🔍 RAW RUST NIF OUTPUT:\n")
IO.inspect(raw_ast, pretty: true, limit: :infinity, width: 120)

# Try typed conversion
{:ok, typed_ast} = RShell.parse(script)

IO.puts("\n\n✨ TYPED AST STRUCT:\n")
IO.inspect(typed_ast, pretty: true, limit: :infinity, width: 120, structs: false)
