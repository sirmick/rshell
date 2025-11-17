defmodule Mix.Tasks.Test.TreeSitterParse do
  @moduledoc """
  Test tree-sitter parsing directly using the tree-sitter CLI.

  This task provides a formal test harness for verifying that the RShell grammar
  correctly parses RShell syntax and produces the expected AST node types.

  ## Usage

      mix test.tree_sitter_parse [input]

  ## Options

      --input TEXT     Input text to parse (default: predefined test cases)
      --expect NODE    Expected node type to find in the output

  ## Examples

      # Test boolean literal
      mix test.tree_sitter_parse --input "X = true" --expect boolean_literal

      # Test list literal
      mix test.tree_sitter_parse --input "X = [1, 2, 3]" --expect list_literal

      # Test map literal
      mix test.tree_sitter_parse --input 'Y = {"key": "value"}' --expect map_literal

      # Run all predefined tests
      mix test.tree_sitter_parse
  """

  use Mix.Task

  @shortdoc "Test tree-sitter RShell grammar parsing"

  @test_cases [
    %{
      name: "Boolean literal (true)",
      input: "X = true",
      expect: ["boolean_literal", "rshell_assignment"]
    },
    %{
      name: "Boolean literal (false)",
      input: "Y = false",
      expect: ["boolean_literal", "rshell_assignment"]
    },
    %{
      name: "List literal (simple)",
      input: "L = [1, 2, 3]",
      expect: ["list_literal", "rshell_assignment"]
    },
    %{
      name: "List literal (nested)",
      input: "L = [[1, 2], [3, 4]]",
      expect: ["list_literal", "rshell_assignment"]
    },
    %{
      name: "Map literal (simple)",
      input: ~s(M = {"key": "value"}),
      expect: ["map_literal", "rshell_assignment", "map_entry"]
    },
    %{
      name: "Map literal (multiple entries)",
      input: ~s(M = {"name": "test", "port": 8080}),
      expect: ["map_literal", "rshell_assignment", "map_entry"]
    },
    %{
      name: "RShell expression (addition)",
      input: "R = 5 + 3",
      expect: ["rshell_assignment"]
    },
    %{
      name: "Mixed: list with map",
      input: ~s(X = [{"id": 1}, {"id": 2}]),
      expect: ["list_literal", "map_literal", "rshell_assignment"]
    }
  ]

  @grammar_path "vendor/tree-sitter-rshell"

  @impl Mix.Task
  def run(args) do
    {opts, _args, _invalid} =
      OptionParser.parse(args,
        strict: [input: :string, expect: :string],
        aliases: [i: :input, e: :expect]
      )

    if opts[:input] do
      run_single_test(opts[:input], opts[:expect])
    else
      run_all_tests()
    end
  end

  defp run_single_test(input, expected_node) do
    Mix.shell().info("🧪 Testing RShell Grammar Parser")
    Mix.shell().info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    Mix.shell().info("Input: #{input}")

    case parse_with_tree_sitter(input) do
      {:ok, output} ->
        Mix.shell().info("\n✓ Parse successful!")
        Mix.shell().info("\nAST Output:")
        Mix.shell().info(output)

        if expected_node do
          if String.contains?(output, expected_node) do
            Mix.shell().info("\n✅ Found expected node type: #{expected_node}")
          else
            Mix.shell().error("\n❌ Expected node type pNOT found: #{expected_node}")
            Mix.shell().error("Available node types:")
            extract_node_types(output) |> Enum.each(&Mix.shell().error("  - #{&1}"))
            System.halt(1)
          end
        end

      {:error, reason} ->
        Mix.shell().error("❌ Parse failed: #{reason}")
        System.halt(1)
    end
  end

  defp run_all_tests do
    Mix.shell().info("🧪 RShell Grammar Test Suite")
    Mix.shell().info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    Mix.shell().info("Grammar: #{@grammar_path}")
    Mix.shell().info("Test cases: #{length(@test_cases)}\n")

    results =
      Enum.map(@test_cases, fn test_case ->
        run_test_case(test_case)
      end)

    passed = Enum.count(results, & &1)
    failed = Enum.count(results, &(!&1))

    Mix.shell().info("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    Mix.shell().info("Test Results:")
    Mix.shell().info("  ✅ Passed: #{passed}")
    Mix.shell().info("  ❌ Failed: #{failed}")
    Mix.shell().info("  📊 Total:  #{length(results)}")

    if failed > 0 do
      System.halt(1)
    end
  end

  defp run_test_case(%{name: name, input: input, expect: expected_nodes}) do
    Mix.shell().info("Testing: #{name}")
    Mix.shell().info("  Input: #{String.slice(input, 0..50)}#{if String.length(input) > 50, do: "...", else: ""}")

    case parse_with_tree_sitter(input) do
      {:ok, output} ->
        found_nodes = extract_node_types(output)
        missing = Enum.filter(expected_nodes, &(&1 not in found_nodes))

        if Enum.empty?(missing) do
          Mix.shell().info("  ✅ PASS - All expected nodes found: #{inspect(expected_nodes)}\n")
          true
        else
          Mix.shell().error("  ❌ FAIL - Missing nodes: #{inspect(missing)}")
          Mix.shell().error("  Found nodes: #{inspect(found_nodes)}\n")
          false
        end

      {:error, reason} ->
        Mix.shell().error("  ❌ FAIL - Parse error: #{reason}\n")
        false
    end
  end

  defp parse_with_tree_sitter(input) do
    # Create temporary file with input
    tmp_file = Path.join(System.tmp_dir!(), "rshell_test_#{:rand.uniform(99999)}.sh")
    File.write!(tmp_file, input)

    try do
      # Run tree-sitter parse
      case System.cmd("tree-sitter", ["parse", tmp_file],
             cd: @grammar_path,
             stderr_to_stdout: true
           ) do
        {output, 0} ->
          {:ok, output}

        {error, _} ->
          {:error, error}
      end
    after
      File.rm(tmp_file)
    end
  rescue
    e ->
      {:error, Exception.message(e)}
  end

  defp extract_node_types(output) do
    # Extract node types from tree-sitter parse output
    # Format is typically: (node_type [...])
    Regex.scan(~r/\((\w+)/, output)
    |> Enum.map(fn [_, node] -> node end)
    |> Enum.uniq()
    |> Enum.sort()
  end
end
