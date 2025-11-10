defmodule EnhancedASTSimpleTest do
  use ExUnit.Case

  def print_ast_recursive(ast, indent \\ 0) do
    padding = String.duplicate("  ", indent)

    # Print current node with position info
    if is_struct(ast) and Map.has_key?(ast, :source_info) do
      source_info = ast.source_info
      node_type = ast.__struct__.node_type()
      IO.puts("#{padding}#{node_type} [#{source_info.start_line}:#{source_info.start_column}-#{source_info.end_line}:#{source_info.end_column}] text='#{String.slice(source_info.text, 0, 30)}'")

      # If this has children that we can traverse, do so
      if Map.has_key?(ast, :children) and is_list(ast.children) do
        Enum.each(ast.children, fn child ->
          print_ast_recursive(child, indent + 1)
        end)
      end
    else
      # For basic types, just print them
      IO.puts("#{padding}#{inspect(ast, limit: 5)}")
    end
  end

  test "comprehensive multiline if then else example" do
    # Complex multi-line script with if/then/else
    script = """
    #!/bin/bash

    USER="admin"
    if [ "$USER" = "admin" ]; then
        echo "Admin access"
    elif [ "$USER" = "guest" ]; then
        echo "Guest access"
    else
        echo "Regular access"
    fi
    """

    case RShell.parse(script) do
      {:ok, ast} ->
        IO.puts("\n🟢 Multi-line Conditional Test:")
        IO.puts("Script: #{script}")
        print_ast_recursive(ast)

        # Basic verification
        assert ast.__struct__ == BashParser.AST.Types.Program
        assert is_struct(ast.source_info, BashParser.AST.Types.SourceInfo)
        assert ast.source_info.text != nil

      {:error, error} ->
        IO.puts("Multi-line parse failed: #{inspect(error)}")
        flunk("Should have parsed successfully")
    end
  end

  test "comprehensive multi-line build script example" do
    script = """
    #!/bin/bash

    # Setup environment
    PROJECT_DIR="/tmp/project"

    # Build process with conditionals
    if [ -d "$PROJECT_DIR" ]; then
        echo "Directory exists"

        # Remove old files
        rm -rf "$PROJECT_DIR/_build"
    else
        echo "Creating directory"
        mkdir -p "$PROJECT_DIR"
    fi

    echo "Build completed"
    """

    case RShell.parse(script) do
      {:ok, ast} ->
        IO.puts("\n🟢 Build Script Multi-line Test:")
        IO.puts("AST shows: #{inspect(ast)}")

        # Verify large script
        assert ast.__struct__ == BashParser.AST.Types.Program
        assert String.length(ast.source_info.text) > 100

        IO.puts("✅ SUCCESS: Complex multi-line parsing")

      {:error, reason} ->
        IO.puts("Parse error: #{reason}")
        flunk("Build script should parse successfully")
    end
  end

  test "real-world comprehensive example" do
    script = """
    #!/bin/bash

    # Real world comprehensive example
    USER_TYPE="admin"

    # Function definition
    setup_environment() {
        local user="$1"
        local mode="$2"

        echo "Setting up environment for $user"
    }

    # Complex conditional with nested logic
    case "$USER_TYPE" in
        admin)
            echo "Admin configuration"

            if [ "$DEBUG" = "true" ]; then
                echo "Debug mode enabled"
            fi
            ;;
        user)
            echo "User configuration"
            ;;
    esac

    # Process with comprehensive control flow
    for item in $(ls); do
        if [ -f "$item" ]; then
            process_file "$item"
        else
            echo "Directory: $item"
        fi
    done
    """

    case RShell.parse(script) do
      {:ok, ast} ->
        IO.puts("\n🟢 Comprehensive Real-world Test:")
        IO.puts("Script length: #{String.length(script)} chars")
        IO.puts("Final AST: #{inspect(ast, limit: 15)}")

        # Large multi-line script verification
        assert ast.__struct__ == BashParser.AST.Types.Program
        assert String.length(ast.source_info.text) > 500

        # Demonstrate analysis
        analysis = RShell.analyze_types(ast)
        IO.puts("Node diversity found: #{analysis.total_diverse_types}")

        IO.puts("🎉 REAL-WORLD SUCCESS: Comprehensive multi-line parsing complete!")

      {:error, error} ->
        flunk("Real-world example failed: #{inspect(error)}")
    end
  end

  test "simple multiline with if/then/else" do
    script = """
    if true; then
      echo "then branch"
    else
      echo "else branch"
    fi
    """

    {:ok, ast} = RShell.parse(script)

    IO.puts("\n🟢 Simple If/Then/Else Test:")
    IO.puts("AST: #{inspect(ast)}")

    assert ast.__struct__ == BashParser.AST.Types.Program
    assert is_struct(ast.source_info, BashParser.AST.Types.SourceInfo)

    IO.puts("✅ Simple conditional parsing successful!")
  end
end
