defmodule Mix.Tasks.Gen.AstTypes do
  @moduledoc """
  Generates typed Elixir structs from tree-sitter-bash node-types.json schema.

  Outputs all types to a single file: lib/bash_parser/ast/types.ex

  ## Usage

      mix gen.ast_types

  ## Options

      --schema PATH     Path to node-types.json (default: vendor/tree-sitter-bash/src/node-types.json)
      --output PATH     Output file path (default: lib/bash_parser/ast/types.ex)
  """

  use Mix.Task

  @shortdoc "Generate typed AST structures from tree-sitter grammar"

  @default_schema_path "vendor/tree-sitter-bash/src/node-types.json"
  @default_output_path "lib/bash_parser/ast/types.ex"

  @impl Mix.Task
  def run(args) do
    {opts, _args, _invalid} = OptionParser.parse(args,
      strict: [schema: :string, output: :string],
      aliases: [s: :schema, o: :output]
    )

    schema_path = opts[:schema] || @default_schema_path
    output_path = opts[:output] || @default_output_path

    Mix.shell().info("🔧 RShell AST Type Generator")
    Mix.shell().info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    Mix.shell().info("Schema: #{schema_path}")
    Mix.shell().info("Output: #{output_path}")

    unless File.exists?(schema_path) do
      Mix.raise("Schema file not found: #{schema_path}")
    end

    # Parse the schema
    Mix.shell().info("\n📖 Parsing schema...")
    schema = parse_schema(schema_path)

    # Categorize nodes
    Mix.shell().info("📊 Categorizing #{length(schema)} node types...")
    categorized = categorize_nodes(schema)

    print_statistics(categorized)

    # Generate single file
    Mix.shell().info("\n✨ Generating types file...")
    generate_types_file(categorized, output_path)

    Mix.shell().info("\n✅ Generation complete!")
  end

  # Parse node-types.json
  defp parse_schema(path) do
    path
    |> File.read!()
    |> Jason.decode!()
    |> Enum.reject(&is_abstract_node?/1)
    |> Enum.filter(&has_named_type?/1)
  end

  defp is_abstract_node?(%{"type" => type}) do
    String.starts_with?(type, "_")
  end

  defp has_named_type?(%{"named" => true}), do: true
  defp has_named_type?(_), do: false

  # Categorize nodes into type families
  defp categorize_nodes(schema) do
    Enum.reduce(schema, %{
      statements: [],
      expressions: [],
      literals: [],
      redirects: [],
      commands: [],
      others: []
    }, fn node, acc ->
      category = determine_category(node)
      Map.update!(acc, category, &[node | &1])
    end)
    |> Map.new(fn {k, v} -> {k, Enum.reverse(v)} end)
  end

  defp determine_category(%{"type" => type}) do
    cond do
      type in ["if_statement", "while_statement", "for_statement", "c_style_for_statement",
               "case_statement", "function_definition", "pipeline", "list", "subshell",
               "compound_statement", "redirected_statement", "negated_command",
               "variable_assignment", "variable_assignments", "do_group",
               "elif_clause", "else_clause", "case_item"] ->
        :statements

      type in ["binary_expression", "unary_expression", "ternary_expression",
               "parenthesized_expression", "postfix_expression"] ->
        :expressions

      type in ["word", "string", "number", "raw_string", "ansi_c_string",
               "translated_string", "string_content", "concatenation",
               "variable_name", "special_variable_name", "array"] ->
        :literals

      type in ["file_redirect", "heredoc_redirect", "herestring_redirect"] ->
        :redirects

      type in ["command", "command_name", "command_substitution", "declaration_command",
               "unset_command", "test_command"] ->
        :commands

      true ->
        :others
    end
  end

  defp print_statistics(categorized) do
    Mix.shell().info("\nNode Type Distribution:")
    Enum.each(categorized, fn {category, nodes} ->
      count = length(nodes)
      if count > 0 do
        Mix.shell().info("  #{category |> to_string() |> String.pad_trailing(12)}: #{count} types")
      end
    end)

    total = categorized |> Map.values() |> Enum.map(&length/1) |> Enum.sum()
    Mix.shell().info("  #{"Total" |> String.pad_trailing(12)}: #{total} types")
  end

  defp generate_types_file(categorized, output_path) do
    all_nodes = categorized
      |> Enum.flat_map(fn {_category, nodes} -> nodes end)
      |> Enum.sort_by(& &1["type"])

    content = """
    defmodule BashParser.AST.Types do
      @moduledoc \"\"\"
      Typed AST structures for Bash scripts.

      Auto-generated from tree-sitter-bash grammar (#{length(all_nodes)} node types).

      All node types are defined as nested modules within this file.
      \"\"\"

    #{generate_source_info()}

    #{generate_all_node_modules(categorized)}

    #{generate_type_union(all_nodes)}

    #{generate_from_map_function(all_nodes)}

    #{generate_helper_functions()}
    end
    """

    File.mkdir_p!(Path.dirname(output_path))
    File.write!(output_path, content)

    Mix.shell().info("  ✓ Generated #{output_path} with #{length(all_nodes)} node types")
  end

  defp generate_source_info do
    """
      defmodule SourceInfo do
        @moduledoc \"\"\"
        Source location information for AST nodes.

        Includes tree-sitter node metadata flags:
        - `is_missing`: Node is expected but not present (parser anticipates it)
        - `is_extra`: Node is extra (not part of grammar but can appear anywhere)
        - `is_error`: Node represents a syntax error
        \"\"\"
        @enforce_keys [:start_line, :start_column, :end_line, :end_column]
        defstruct [
          :start_line,
          :start_column,
          :end_line,
          :end_column,
          :text,
          is_missing: false,
          is_extra: false,
          is_error: false
        ]

        @type t :: %__MODULE__{
                start_line: non_neg_integer(),
                start_column: non_neg_integer(),
                end_line: non_neg_integer(),
                end_column: non_neg_integer(),
                text: String.t() | nil,
                is_missing: boolean(),
                is_extra: boolean(),
                is_error: boolean()
              }

        @spec from_map(map()) :: t()
        def from_map(data) do
          %__MODULE__{
            start_line: data["start_line"] || data["start_row"] || 0,
            start_column: data["start_column"] || data["start_col"] || 0,
            end_line: data["end_line"] || data["end_row"] || 0,
            end_column: data["end_column"] || data["end_col"] || 0,
            text: data["text"],
            is_missing: data["is_missing"] || false,
            is_extra: data["is_extra"] || false,
            is_error: data["is_error"] || false
          }
        end
      end
    """
  end

  defp generate_all_node_modules(categorized) do
    # Generate modules for all categories
    category_modules = categorized
    |> Enum.sort()
    |> Enum.map(fn {category, nodes} ->
      nodes_sorted = Enum.sort_by(nodes, & &1["type"])

      category_comment = """
        # #{category |> to_string() |> String.upcase()}
        # #{String.duplicate("=", 78)}
      """

      modules = nodes_sorted
        |> Enum.map(&generate_node_module/1)
        |> Enum.join("\n\n")

      category_comment <> "\n" <> modules
    end)
    |> Enum.join("\n\n")

    # Add special ErrorNode module (not in grammar but generated by tree-sitter)
    error_node_module = """
      # OTHERS
      # #{String.duplicate("=", 78)}

      defmodule ErrorNode do
        @moduledoc \"\"\"
        Node type: ERROR

        Special node type created by tree-sitter when it encounters syntax errors.
        These nodes indicate actual syntax problems, not incomplete structures.
        \"\"\"
        @enforce_keys [:source_info]
        defstruct [:source_info, :text, :children]

        @type t :: %__MODULE__{
                source_info: BashParser.AST.Types.SourceInfo.t(),
              text: String.t() | nil,
              children: list(any())
              }

        @spec from_map(map()) :: t()
        def from_map(data) do
          %__MODULE__{
            source_info: BashParser.AST.Types.SourceInfo.from_map(data),
              text: Map.get(data, "text"),
              children: BashParser.AST.Types.extract_children(data, "children")
          }
        end

        @spec node_type() :: String.t()
        def node_type, do: "ERROR"
      end
    """

    category_modules <> "\n\n" <> error_node_module
  end

  defp generate_node_module(node) do
    type_name = node["type"]
    module_name = type_to_module_name(type_name)
    fields = extract_fields(node)
    has_unnamed_children = has_unnamed_children?(node)

    required_field_names = fields
      |> Enum.filter(&(&1.required))
      |> Enum.map(&(&1.name))

    required_keys = [:source_info | required_field_names]
    # Add :children field if node has unnamed children
    struct_fields = if has_unnamed_children do
      [:source_info | Enum.map(fields, &(&1.name))] ++ [:children] |> Enum.uniq()
    else
      [:source_info | Enum.map(fields, &(&1.name))] |> Enum.uniq()
    end

    """
      defmodule #{module_name} do
        @moduledoc \"\"\"
        Node type: #{type_name}
        \"\"\"
        @enforce_keys #{inspect(required_keys)}
        defstruct #{inspect(struct_fields)}

        @type t :: %__MODULE__{
                source_info: BashParser.AST.Types.SourceInfo.t()#{if fields != [] or has_unnamed_children, do: ",", else: ""}
    #{generate_field_type_specs(fields)}#{if has_unnamed_children and fields != [], do: ",\n", else: ""}#{if has_unnamed_children, do: "          children: list(any())", else: ""}
              }

        @spec from_map(map()) :: t()
        def from_map(data) do
          %__MODULE__{
            source_info: BashParser.AST.Types.SourceInfo.from_map(data)#{if fields != [] or has_unnamed_children, do: ",", else: ""}
    #{generate_field_from_map(fields)}#{if has_unnamed_children and fields != [], do: ",\n", else: ""}#{if has_unnamed_children, do: "          children: BashParser.AST.Types.extract_children(data, \"children\")", else: ""}
          }
        end

        @spec node_type() :: String.t()
        def node_type, do: "#{type_name}"
      end
    """
  end

  defp extract_fields(node) do
    fields_map = Map.get(node, "fields", %{})

    Enum.map(fields_map, fn {name, field_spec} ->
      %{
        name: String.to_atom(name),
        required: field_spec["required"] || false,
        multiple: field_spec["multiple"] || false
      }
    end)
  end

  # Check if a node has unnamed children (as opposed to named fields)
  defp has_unnamed_children?(node) do
    Map.has_key?(node, "children")
  end

  defp generate_field_type_specs(fields) do
    fields
    |> Enum.map(fn field ->
      type = cond do
        field.multiple -> "list(any())"
        field.required -> "any()"
        true -> "any() | nil"
      end
      "          #{field.name}: #{type}"
    end)
    |> Enum.join(",\n")
  end

  defp generate_field_from_map(fields) do
    fields
    |> Enum.map(fn field ->
      value = if field.multiple do
        "BashParser.AST.Types.extract_children(data, \"#{field.name}\")"
      else
        "BashParser.AST.Types.extract_field(data, \"#{field.name}\")"
      end
      "          #{field.name}: #{value}"
    end)
    |> Enum.join(",\n")
  end

  defp generate_type_union(nodes) do
    type_refs = nodes
      |> Enum.map(fn node ->
        "        #{type_to_module_name(node["type"])}.t()"
      end)
      |> Enum.join("\n      | ")

    """
      @type t ::
              #{type_refs}
      |         ErrorNode.t()
    """
  end

  defp generate_from_map_function(nodes) do
    cases = nodes
      |> Enum.map(fn node ->
        type_name = node["type"]
        module_name = type_to_module_name(type_name)
        "      \"#{type_name}\" -> #{module_name}.from_map(data)"
      end)
      |> Enum.join("\n")

    """
      @doc \"\"\"
      Converts a tree-sitter map to the appropriate typed struct.
      \"\"\"
      @spec from_map(map()) :: t()
      def from_map(%{"type" => type} = data) do
        case type do
    #{cases}
          "ERROR" -> ErrorNode.from_map(data)
          _ -> raise "Unknown node type: \#{type}"
        end
      end
    """
  end

  defp generate_helper_functions do
    """
      # Helper functions for field extraction
      @doc false
      def extract_field(data, field_name) do
        case Map.get(data, field_name) do
          nil -> nil
          value when is_map(value) ->
            # Recursively convert nested maps to typed structs
            from_map(value)
          value -> value
        end
      end

      @doc false
      def extract_children(data, field_name) do
        case Map.get(data, field_name) do
          nil -> []
          list when is_list(list) ->
            # Recursively convert all items in the list
            Enum.map(list, fn item ->
              if is_map(item), do: from_map(item), else: item
            end)
          value when is_map(value) ->
            # Single map value, convert and wrap in list
            [from_map(value)]
          value -> [value]
        end
      end

    """
  end

  defp type_to_module_name(type) do
    type
    |> String.split("_")
    |> Enum.map(&String.capitalize/1)
    |> Enum.join("")
  end
end
