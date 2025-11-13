defmodule BashParser.AST.Types do
  @moduledoc """
  Typed AST structures for Bash scripts.

  Auto-generated from tree-sitter-bash grammar (59 node types).

  All node types are defined as nested modules within this file.
  """

  defmodule SourceInfo do
    @moduledoc """
    Source location information for AST nodes.

    Includes tree-sitter node metadata flags:
    - `is_missing`: Node is expected but not present (parser anticipates it)
    - `is_extra`: Node is extra (not part of grammar but can appear anywhere)
    - `is_error`: Node represents a syntax error
    """
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


  # COMMANDS
  # ==============================================================================

  defmodule Command do
    @moduledoc """
    Node type: command
    """
    @enforce_keys [:source_info, :name]
    defstruct [:source_info, :argument, :name, :redirect, :children]

    @type t :: %__MODULE__{
            source_info: BashParser.AST.Types.SourceInfo.t(),
          argument: list(any()),
          name: any(),
          redirect: list(any()),
          children: list(any())
          }

    @spec from_map(map()) :: t()
    def from_map(data) do
      %__MODULE__{
        source_info: BashParser.AST.Types.SourceInfo.from_map(data),
          argument: BashParser.AST.Types.extract_children(data, "argument"),
          name: BashParser.AST.Types.extract_field(data, "name"),
          redirect: BashParser.AST.Types.extract_children(data, "redirect"),
          children: BashParser.AST.Types.extract_children(data, "children")
      }
    end

    @spec node_type() :: String.t()
    def node_type, do: "command"
  end


  defmodule CommandName do
    @moduledoc """
    Node type: command_name
    """
    @enforce_keys [:source_info]
    defstruct [:source_info, :children]

    @type t :: %__MODULE__{
            source_info: BashParser.AST.Types.SourceInfo.t(),
          children: list(any())
          }

    @spec from_map(map()) :: t()
    def from_map(data) do
      %__MODULE__{
        source_info: BashParser.AST.Types.SourceInfo.from_map(data),
          children: BashParser.AST.Types.extract_children(data, "children")
      }
    end

    @spec node_type() :: String.t()
    def node_type, do: "command_name"
  end


  defmodule CommandSubstitution do
    @moduledoc """
    Node type: command_substitution
    """
    @enforce_keys [:source_info]
    defstruct [:source_info, :redirect, :children]

    @type t :: %__MODULE__{
            source_info: BashParser.AST.Types.SourceInfo.t(),
          redirect: any() | nil,
          children: list(any())
          }

    @spec from_map(map()) :: t()
    def from_map(data) do
      %__MODULE__{
        source_info: BashParser.AST.Types.SourceInfo.from_map(data),
          redirect: BashParser.AST.Types.extract_field(data, "redirect"),
          children: BashParser.AST.Types.extract_children(data, "children")
      }
    end

    @spec node_type() :: String.t()
    def node_type, do: "command_substitution"
  end


  defmodule DeclarationCommand do
    @moduledoc """
    Node type: declaration_command
    """
    @enforce_keys [:source_info]
    defstruct [:source_info, :children]

    @type t :: %__MODULE__{
            source_info: BashParser.AST.Types.SourceInfo.t(),
          children: list(any())
          }

    @spec from_map(map()) :: t()
    def from_map(data) do
      %__MODULE__{
        source_info: BashParser.AST.Types.SourceInfo.from_map(data),
          children: BashParser.AST.Types.extract_children(data, "children")
      }
    end

    @spec node_type() :: String.t()
    def node_type, do: "declaration_command"
  end


  defmodule TestCommand do
    @moduledoc """
    Node type: test_command
    """
    @enforce_keys [:source_info]
    defstruct [:source_info, :children]

    @type t :: %__MODULE__{
            source_info: BashParser.AST.Types.SourceInfo.t(),
          children: list(any())
          }

    @spec from_map(map()) :: t()
    def from_map(data) do
      %__MODULE__{
        source_info: BashParser.AST.Types.SourceInfo.from_map(data),
          children: BashParser.AST.Types.extract_children(data, "children")
      }
    end

    @spec node_type() :: String.t()
    def node_type, do: "test_command"
  end


  defmodule UnsetCommand do
    @moduledoc """
    Node type: unset_command
    """
    @enforce_keys [:source_info]
    defstruct [:source_info, :children]

    @type t :: %__MODULE__{
            source_info: BashParser.AST.Types.SourceInfo.t(),
          children: list(any())
          }

    @spec from_map(map()) :: t()
    def from_map(data) do
      %__MODULE__{
        source_info: BashParser.AST.Types.SourceInfo.from_map(data),
          children: BashParser.AST.Types.extract_children(data, "children")
      }
    end

    @spec node_type() :: String.t()
    def node_type, do: "unset_command"
  end


  # EXPRESSIONS
  # ==============================================================================

  defmodule BinaryExpression do
    @moduledoc """
    Node type: binary_expression
    """
    @enforce_keys [:source_info, :operator]
    defstruct [:source_info, :left, :operator, :right, :children]

    @type t :: %__MODULE__{
            source_info: BashParser.AST.Types.SourceInfo.t(),
          left: any() | nil,
          operator: any(),
          right: list(any()),
          children: list(any())
          }

    @spec from_map(map()) :: t()
    def from_map(data) do
      %__MODULE__{
        source_info: BashParser.AST.Types.SourceInfo.from_map(data),
          left: BashParser.AST.Types.extract_field(data, "left"),
          operator: BashParser.AST.Types.extract_field(data, "operator"),
          right: BashParser.AST.Types.extract_children(data, "right"),
          children: BashParser.AST.Types.extract_children(data, "children")
      }
    end

    @spec node_type() :: String.t()
    def node_type, do: "binary_expression"
  end


  defmodule ParenthesizedExpression do
    @moduledoc """
    Node type: parenthesized_expression
    """
    @enforce_keys [:source_info]
    defstruct [:source_info, :children]

    @type t :: %__MODULE__{
            source_info: BashParser.AST.Types.SourceInfo.t(),
          children: list(any())
          }

    @spec from_map(map()) :: t()
    def from_map(data) do
      %__MODULE__{
        source_info: BashParser.AST.Types.SourceInfo.from_map(data),
          children: BashParser.AST.Types.extract_children(data, "children")
      }
    end

    @spec node_type() :: String.t()
    def node_type, do: "parenthesized_expression"
  end


  defmodule PostfixExpression do
    @moduledoc """
    Node type: postfix_expression
    """
    @enforce_keys [:source_info, :operator]
    defstruct [:source_info, :operator, :children]

    @type t :: %__MODULE__{
            source_info: BashParser.AST.Types.SourceInfo.t(),
          operator: any(),
          children: list(any())
          }

    @spec from_map(map()) :: t()
    def from_map(data) do
      %__MODULE__{
        source_info: BashParser.AST.Types.SourceInfo.from_map(data),
          operator: BashParser.AST.Types.extract_field(data, "operator"),
          children: BashParser.AST.Types.extract_children(data, "children")
      }
    end

    @spec node_type() :: String.t()
    def node_type, do: "postfix_expression"
  end


  defmodule TernaryExpression do
    @moduledoc """
    Node type: ternary_expression
    """
    @enforce_keys [:source_info, :alternative, :condition, :consequence]
    defstruct [:source_info, :alternative, :condition, :consequence]

    @type t :: %__MODULE__{
            source_info: BashParser.AST.Types.SourceInfo.t(),
          alternative: any(),
          condition: any(),
          consequence: any()
          }

    @spec from_map(map()) :: t()
    def from_map(data) do
      %__MODULE__{
        source_info: BashParser.AST.Types.SourceInfo.from_map(data),
          alternative: BashParser.AST.Types.extract_field(data, "alternative"),
          condition: BashParser.AST.Types.extract_field(data, "condition"),
          consequence: BashParser.AST.Types.extract_field(data, "consequence")
      }
    end

    @spec node_type() :: String.t()
    def node_type, do: "ternary_expression"
  end


  defmodule UnaryExpression do
    @moduledoc """
    Node type: unary_expression
    """
    @enforce_keys [:source_info, :operator]
    defstruct [:source_info, :operator, :children]

    @type t :: %__MODULE__{
            source_info: BashParser.AST.Types.SourceInfo.t(),
          operator: any(),
          children: list(any())
          }

    @spec from_map(map()) :: t()
    def from_map(data) do
      %__MODULE__{
        source_info: BashParser.AST.Types.SourceInfo.from_map(data),
          operator: BashParser.AST.Types.extract_field(data, "operator"),
          children: BashParser.AST.Types.extract_children(data, "children")
      }
    end

    @spec node_type() :: String.t()
    def node_type, do: "unary_expression"
  end


  # LITERALS
  # ==============================================================================

  defmodule AnsiCString do
    @moduledoc """
    Node type: ansi_c_string
    """
    @enforce_keys [:source_info]
    defstruct [:source_info]

    @type t :: %__MODULE__{
            source_info: BashParser.AST.Types.SourceInfo.t()

          }

    @spec from_map(map()) :: t()
    def from_map(data) do
      %__MODULE__{
        source_info: BashParser.AST.Types.SourceInfo.from_map(data)

      }
    end

    @spec node_type() :: String.t()
    def node_type, do: "ansi_c_string"
  end


  defmodule Array do
    @moduledoc """
    Node type: array
    """
    @enforce_keys [:source_info]
    defstruct [:source_info, :children]

    @type t :: %__MODULE__{
            source_info: BashParser.AST.Types.SourceInfo.t(),
          children: list(any())
          }

    @spec from_map(map()) :: t()
    def from_map(data) do
      %__MODULE__{
        source_info: BashParser.AST.Types.SourceInfo.from_map(data),
          children: BashParser.AST.Types.extract_children(data, "children")
      }
    end

    @spec node_type() :: String.t()
    def node_type, do: "array"
  end


  defmodule Concatenation do
    @moduledoc """
    Node type: concatenation
    """
    @enforce_keys [:source_info]
    defstruct [:source_info, :children]

    @type t :: %__MODULE__{
            source_info: BashParser.AST.Types.SourceInfo.t(),
          children: list(any())
          }

    @spec from_map(map()) :: t()
    def from_map(data) do
      %__MODULE__{
        source_info: BashParser.AST.Types.SourceInfo.from_map(data),
          children: BashParser.AST.Types.extract_children(data, "children")
      }
    end

    @spec node_type() :: String.t()
    def node_type, do: "concatenation"
  end


  defmodule Number do
    @moduledoc """
    Node type: number
    """
    @enforce_keys [:source_info]
    defstruct [:source_info, :children]

    @type t :: %__MODULE__{
            source_info: BashParser.AST.Types.SourceInfo.t(),
          children: list(any())
          }

    @spec from_map(map()) :: t()
    def from_map(data) do
      %__MODULE__{
        source_info: BashParser.AST.Types.SourceInfo.from_map(data),
          children: BashParser.AST.Types.extract_children(data, "children")
      }
    end

    @spec node_type() :: String.t()
    def node_type, do: "number"
  end


  defmodule RawString do
    @moduledoc """
    Node type: raw_string
    """
    @enforce_keys [:source_info]
    defstruct [:source_info]

    @type t :: %__MODULE__{
            source_info: BashParser.AST.Types.SourceInfo.t()

          }

    @spec from_map(map()) :: t()
    def from_map(data) do
      %__MODULE__{
        source_info: BashParser.AST.Types.SourceInfo.from_map(data)

      }
    end

    @spec node_type() :: String.t()
    def node_type, do: "raw_string"
  end


  defmodule SpecialVariableName do
    @moduledoc """
    Node type: special_variable_name
    """
    @enforce_keys [:source_info]
    defstruct [:source_info]

    @type t :: %__MODULE__{
            source_info: BashParser.AST.Types.SourceInfo.t()

          }

    @spec from_map(map()) :: t()
    def from_map(data) do
      %__MODULE__{
        source_info: BashParser.AST.Types.SourceInfo.from_map(data)

      }
    end

    @spec node_type() :: String.t()
    def node_type, do: "special_variable_name"
  end


  defmodule String do
    @moduledoc """
    Node type: string
    """
    @enforce_keys [:source_info]
    defstruct [:source_info, :children]

    @type t :: %__MODULE__{
            source_info: BashParser.AST.Types.SourceInfo.t(),
          children: list(any())
          }

    @spec from_map(map()) :: t()
    def from_map(data) do
      %__MODULE__{
        source_info: BashParser.AST.Types.SourceInfo.from_map(data),
          children: BashParser.AST.Types.extract_children(data, "children")
      }
    end

    @spec node_type() :: String.t()
    def node_type, do: "string"
  end


  defmodule StringContent do
    @moduledoc """
    Node type: string_content
    """
    @enforce_keys [:source_info]
    defstruct [:source_info]

    @type t :: %__MODULE__{
            source_info: BashParser.AST.Types.SourceInfo.t()

          }

    @spec from_map(map()) :: t()
    def from_map(data) do
      %__MODULE__{
        source_info: BashParser.AST.Types.SourceInfo.from_map(data)

      }
    end

    @spec node_type() :: String.t()
    def node_type, do: "string_content"
  end


  defmodule TranslatedString do
    @moduledoc """
    Node type: translated_string
    """
    @enforce_keys [:source_info]
    defstruct [:source_info, :children]

    @type t :: %__MODULE__{
            source_info: BashParser.AST.Types.SourceInfo.t(),
          children: list(any())
          }

    @spec from_map(map()) :: t()
    def from_map(data) do
      %__MODULE__{
        source_info: BashParser.AST.Types.SourceInfo.from_map(data),
          children: BashParser.AST.Types.extract_children(data, "children")
      }
    end

    @spec node_type() :: String.t()
    def node_type, do: "translated_string"
  end


  defmodule VariableName do
    @moduledoc """
    Node type: variable_name
    """
    @enforce_keys [:source_info]
    defstruct [:source_info]

    @type t :: %__MODULE__{
            source_info: BashParser.AST.Types.SourceInfo.t()

          }

    @spec from_map(map()) :: t()
    def from_map(data) do
      %__MODULE__{
        source_info: BashParser.AST.Types.SourceInfo.from_map(data)

      }
    end

    @spec node_type() :: String.t()
    def node_type, do: "variable_name"
  end


  defmodule Word do
    @moduledoc """
    Node type: word
    """
    @enforce_keys [:source_info]
    defstruct [:source_info]

    @type t :: %__MODULE__{
            source_info: BashParser.AST.Types.SourceInfo.t()

          }

    @spec from_map(map()) :: t()
    def from_map(data) do
      %__MODULE__{
        source_info: BashParser.AST.Types.SourceInfo.from_map(data)

      }
    end

    @spec node_type() :: String.t()
    def node_type, do: "word"
  end


  # OTHERS
  # ==============================================================================

  defmodule ArithmeticExpansion do
    @moduledoc """
    Node type: arithmetic_expansion
    """
    @enforce_keys [:source_info]
    defstruct [:source_info, :children]

    @type t :: %__MODULE__{
            source_info: BashParser.AST.Types.SourceInfo.t(),
          children: list(any())
          }

    @spec from_map(map()) :: t()
    def from_map(data) do
      %__MODULE__{
        source_info: BashParser.AST.Types.SourceInfo.from_map(data),
          children: BashParser.AST.Types.extract_children(data, "children")
      }
    end

    @spec node_type() :: String.t()
    def node_type, do: "arithmetic_expansion"
  end


  defmodule BraceExpression do
    @moduledoc """
    Node type: brace_expression
    """
    @enforce_keys [:source_info]
    defstruct [:source_info, :children]

    @type t :: %__MODULE__{
            source_info: BashParser.AST.Types.SourceInfo.t(),
          children: list(any())
          }

    @spec from_map(map()) :: t()
    def from_map(data) do
      %__MODULE__{
        source_info: BashParser.AST.Types.SourceInfo.from_map(data),
          children: BashParser.AST.Types.extract_children(data, "children")
      }
    end

    @spec node_type() :: String.t()
    def node_type, do: "brace_expression"
  end


  defmodule Comment do
    @moduledoc """
    Node type: comment
    """
    @enforce_keys [:source_info]
    defstruct [:source_info]

    @type t :: %__MODULE__{
            source_info: BashParser.AST.Types.SourceInfo.t()

          }

    @spec from_map(map()) :: t()
    def from_map(data) do
      %__MODULE__{
        source_info: BashParser.AST.Types.SourceInfo.from_map(data)

      }
    end

    @spec node_type() :: String.t()
    def node_type, do: "comment"
  end


  defmodule Expansion do
    @moduledoc """
    Node type: expansion
    """
    @enforce_keys [:source_info]
    defstruct [:source_info, :operator, :children]

    @type t :: %__MODULE__{
            source_info: BashParser.AST.Types.SourceInfo.t(),
          operator: list(any()),
          children: list(any())
          }

    @spec from_map(map()) :: t()
    def from_map(data) do
      %__MODULE__{
        source_info: BashParser.AST.Types.SourceInfo.from_map(data),
          operator: BashParser.AST.Types.extract_children(data, "operator"),
          children: BashParser.AST.Types.extract_children(data, "children")
      }
    end

    @spec node_type() :: String.t()
    def node_type, do: "expansion"
  end


  defmodule ExtglobPattern do
    @moduledoc """
    Node type: extglob_pattern
    """
    @enforce_keys [:source_info]
    defstruct [:source_info]

    @type t :: %__MODULE__{
            source_info: BashParser.AST.Types.SourceInfo.t()

          }

    @spec from_map(map()) :: t()
    def from_map(data) do
      %__MODULE__{
        source_info: BashParser.AST.Types.SourceInfo.from_map(data)

      }
    end

    @spec node_type() :: String.t()
    def node_type, do: "extglob_pattern"
  end


  defmodule FileDescriptor do
    @moduledoc """
    Node type: file_descriptor
    """
    @enforce_keys [:source_info]
    defstruct [:source_info]

    @type t :: %__MODULE__{
            source_info: BashParser.AST.Types.SourceInfo.t()

          }

    @spec from_map(map()) :: t()
    def from_map(data) do
      %__MODULE__{
        source_info: BashParser.AST.Types.SourceInfo.from_map(data)

      }
    end

    @spec node_type() :: String.t()
    def node_type, do: "file_descriptor"
  end


  defmodule HeredocBody do
    @moduledoc """
    Node type: heredoc_body
    """
    @enforce_keys [:source_info]
    defstruct [:source_info, :children]

    @type t :: %__MODULE__{
            source_info: BashParser.AST.Types.SourceInfo.t(),
          children: list(any())
          }

    @spec from_map(map()) :: t()
    def from_map(data) do
      %__MODULE__{
        source_info: BashParser.AST.Types.SourceInfo.from_map(data),
          children: BashParser.AST.Types.extract_children(data, "children")
      }
    end

    @spec node_type() :: String.t()
    def node_type, do: "heredoc_body"
  end


  defmodule HeredocContent do
    @moduledoc """
    Node type: heredoc_content
    """
    @enforce_keys [:source_info]
    defstruct [:source_info]

    @type t :: %__MODULE__{
            source_info: BashParser.AST.Types.SourceInfo.t()

          }

    @spec from_map(map()) :: t()
    def from_map(data) do
      %__MODULE__{
        source_info: BashParser.AST.Types.SourceInfo.from_map(data)

      }
    end

    @spec node_type() :: String.t()
    def node_type, do: "heredoc_content"
  end


  defmodule HeredocEnd do
    @moduledoc """
    Node type: heredoc_end
    """
    @enforce_keys [:source_info]
    defstruct [:source_info]

    @type t :: %__MODULE__{
            source_info: BashParser.AST.Types.SourceInfo.t()

          }

    @spec from_map(map()) :: t()
    def from_map(data) do
      %__MODULE__{
        source_info: BashParser.AST.Types.SourceInfo.from_map(data)

      }
    end

    @spec node_type() :: String.t()
    def node_type, do: "heredoc_end"
  end


  defmodule HeredocStart do
    @moduledoc """
    Node type: heredoc_start
    """
    @enforce_keys [:source_info]
    defstruct [:source_info]

    @type t :: %__MODULE__{
            source_info: BashParser.AST.Types.SourceInfo.t()

          }

    @spec from_map(map()) :: t()
    def from_map(data) do
      %__MODULE__{
        source_info: BashParser.AST.Types.SourceInfo.from_map(data)

      }
    end

    @spec node_type() :: String.t()
    def node_type, do: "heredoc_start"
  end


  defmodule ProcessSubstitution do
    @moduledoc """
    Node type: process_substitution
    """
    @enforce_keys [:source_info]
    defstruct [:source_info, :children]

    @type t :: %__MODULE__{
            source_info: BashParser.AST.Types.SourceInfo.t(),
          children: list(any())
          }

    @spec from_map(map()) :: t()
    def from_map(data) do
      %__MODULE__{
        source_info: BashParser.AST.Types.SourceInfo.from_map(data),
          children: BashParser.AST.Types.extract_children(data, "children")
      }
    end

    @spec node_type() :: String.t()
    def node_type, do: "process_substitution"
  end


  defmodule Program do
    @moduledoc """
    Node type: program
    """
    @enforce_keys [:source_info]
    defstruct [:source_info, :children]

    @type t :: %__MODULE__{
            source_info: BashParser.AST.Types.SourceInfo.t(),
          children: list(any())
          }

    @spec from_map(map()) :: t()
    def from_map(data) do
      %__MODULE__{
        source_info: BashParser.AST.Types.SourceInfo.from_map(data),
          children: BashParser.AST.Types.extract_children(data, "children")
      }
    end

    @spec node_type() :: String.t()
    def node_type, do: "program"
  end


  defmodule Regex do
    @moduledoc """
    Node type: regex
    """
    @enforce_keys [:source_info]
    defstruct [:source_info]

    @type t :: %__MODULE__{
            source_info: BashParser.AST.Types.SourceInfo.t()

          }

    @spec from_map(map()) :: t()
    def from_map(data) do
      %__MODULE__{
        source_info: BashParser.AST.Types.SourceInfo.from_map(data)

      }
    end

    @spec node_type() :: String.t()
    def node_type, do: "regex"
  end


  defmodule SimpleExpansion do
    @moduledoc """
    Node type: simple_expansion
    """
    @enforce_keys [:source_info]
    defstruct [:source_info, :children]

    @type t :: %__MODULE__{
            source_info: BashParser.AST.Types.SourceInfo.t(),
          children: list(any())
          }

    @spec from_map(map()) :: t()
    def from_map(data) do
      %__MODULE__{
        source_info: BashParser.AST.Types.SourceInfo.from_map(data),
          children: BashParser.AST.Types.extract_children(data, "children")
      }
    end

    @spec node_type() :: String.t()
    def node_type, do: "simple_expansion"
  end


  defmodule Subscript do
    @moduledoc """
    Node type: subscript
    """
    @enforce_keys [:source_info, :index, :name]
    defstruct [:source_info, :index, :name]

    @type t :: %__MODULE__{
            source_info: BashParser.AST.Types.SourceInfo.t(),
          index: any(),
          name: any()
          }

    @spec from_map(map()) :: t()
    def from_map(data) do
      %__MODULE__{
        source_info: BashParser.AST.Types.SourceInfo.from_map(data),
          index: BashParser.AST.Types.extract_field(data, "index"),
          name: BashParser.AST.Types.extract_field(data, "name")
      }
    end

    @spec node_type() :: String.t()
    def node_type, do: "subscript"
  end


  defmodule TestOperator do
    @moduledoc """
    Node type: test_operator
    """
    @enforce_keys [:source_info]
    defstruct [:source_info]

    @type t :: %__MODULE__{
            source_info: BashParser.AST.Types.SourceInfo.t()

          }

    @spec from_map(map()) :: t()
    def from_map(data) do
      %__MODULE__{
        source_info: BashParser.AST.Types.SourceInfo.from_map(data)

      }
    end

    @spec node_type() :: String.t()
    def node_type, do: "test_operator"
  end


  # REDIRECTS
  # ==============================================================================

  defmodule FileRedirect do
    @moduledoc """
    Node type: file_redirect
    """
    @enforce_keys [:source_info]
    defstruct [:source_info, :descriptor, :destination]

    @type t :: %__MODULE__{
            source_info: BashParser.AST.Types.SourceInfo.t(),
          descriptor: any() | nil,
          destination: list(any())
          }

    @spec from_map(map()) :: t()
    def from_map(data) do
      %__MODULE__{
        source_info: BashParser.AST.Types.SourceInfo.from_map(data),
          descriptor: BashParser.AST.Types.extract_field(data, "descriptor"),
          destination: BashParser.AST.Types.extract_children(data, "destination")
      }
    end

    @spec node_type() :: String.t()
    def node_type, do: "file_redirect"
  end


  defmodule HeredocRedirect do
    @moduledoc """
    Node type: heredoc_redirect
    """
    @enforce_keys [:source_info]
    defstruct [:source_info, :argument, :descriptor, :operator, :redirect, :right, :children]

    @type t :: %__MODULE__{
            source_info: BashParser.AST.Types.SourceInfo.t(),
          argument: list(any()),
          descriptor: any() | nil,
          operator: any() | nil,
          redirect: list(any()),
          right: any() | nil,
          children: list(any())
          }

    @spec from_map(map()) :: t()
    def from_map(data) do
      %__MODULE__{
        source_info: BashParser.AST.Types.SourceInfo.from_map(data),
          argument: BashParser.AST.Types.extract_children(data, "argument"),
          descriptor: BashParser.AST.Types.extract_field(data, "descriptor"),
          operator: BashParser.AST.Types.extract_field(data, "operator"),
          redirect: BashParser.AST.Types.extract_children(data, "redirect"),
          right: BashParser.AST.Types.extract_field(data, "right"),
          children: BashParser.AST.Types.extract_children(data, "children")
      }
    end

    @spec node_type() :: String.t()
    def node_type, do: "heredoc_redirect"
  end


  defmodule HerestringRedirect do
    @moduledoc """
    Node type: herestring_redirect
    """
    @enforce_keys [:source_info]
    defstruct [:source_info, :descriptor, :children]

    @type t :: %__MODULE__{
            source_info: BashParser.AST.Types.SourceInfo.t(),
          descriptor: any() | nil,
          children: list(any())
          }

    @spec from_map(map()) :: t()
    def from_map(data) do
      %__MODULE__{
        source_info: BashParser.AST.Types.SourceInfo.from_map(data),
          descriptor: BashParser.AST.Types.extract_field(data, "descriptor"),
          children: BashParser.AST.Types.extract_children(data, "children")
      }
    end

    @spec node_type() :: String.t()
    def node_type, do: "herestring_redirect"
  end


  # STATEMENTS
  # ==============================================================================

  defmodule CStyleForStatement do
    @moduledoc """
    Node type: c_style_for_statement
    """
    @enforce_keys [:source_info, :body]
    defstruct [:source_info, :body, :condition, :initializer, :update]

    @type t :: %__MODULE__{
            source_info: BashParser.AST.Types.SourceInfo.t(),
          body: any(),
          condition: list(any()),
          initializer: list(any()),
          update: list(any())
          }

    @spec from_map(map()) :: t()
    def from_map(data) do
      %__MODULE__{
        source_info: BashParser.AST.Types.SourceInfo.from_map(data),
          body: BashParser.AST.Types.extract_field(data, "body"),
          condition: BashParser.AST.Types.extract_children(data, "condition"),
          initializer: BashParser.AST.Types.extract_children(data, "initializer"),
          update: BashParser.AST.Types.extract_children(data, "update")
      }
    end

    @spec node_type() :: String.t()
    def node_type, do: "c_style_for_statement"
  end


  defmodule CaseItem do
    @moduledoc """
    Node type: case_item
    """
    @enforce_keys [:source_info, :value]
    defstruct [:source_info, :fallthrough, :termination, :value, :children]

    @type t :: %__MODULE__{
            source_info: BashParser.AST.Types.SourceInfo.t(),
          fallthrough: any() | nil,
          termination: any() | nil,
          value: list(any()),
          children: list(any())
          }

    @spec from_map(map()) :: t()
    def from_map(data) do
      %__MODULE__{
        source_info: BashParser.AST.Types.SourceInfo.from_map(data),
          fallthrough: BashParser.AST.Types.extract_field(data, "fallthrough"),
          termination: BashParser.AST.Types.extract_field(data, "termination"),
          value: BashParser.AST.Types.extract_children(data, "value"),
          children: BashParser.AST.Types.extract_children(data, "children")
      }
    end

    @spec node_type() :: String.t()
    def node_type, do: "case_item"
  end


  defmodule CaseStatement do
    @moduledoc """
    Node type: case_statement
    """
    @enforce_keys [:source_info, :value]
    defstruct [:source_info, :value, :children]

    @type t :: %__MODULE__{
            source_info: BashParser.AST.Types.SourceInfo.t(),
          value: any(),
          children: list(any())
          }

    @spec from_map(map()) :: t()
    def from_map(data) do
      %__MODULE__{
        source_info: BashParser.AST.Types.SourceInfo.from_map(data),
          value: BashParser.AST.Types.extract_field(data, "value"),
          children: BashParser.AST.Types.extract_children(data, "children")
      }
    end

    @spec node_type() :: String.t()
    def node_type, do: "case_statement"
  end


  defmodule CompoundStatement do
    @moduledoc """
    Node type: compound_statement
    """
    @enforce_keys [:source_info]
    defstruct [:source_info, :children]

    @type t :: %__MODULE__{
            source_info: BashParser.AST.Types.SourceInfo.t(),
          children: list(any())
          }

    @spec from_map(map()) :: t()
    def from_map(data) do
      %__MODULE__{
        source_info: BashParser.AST.Types.SourceInfo.from_map(data),
          children: BashParser.AST.Types.extract_children(data, "children")
      }
    end

    @spec node_type() :: String.t()
    def node_type, do: "compound_statement"
  end


  defmodule DoGroup do
    @moduledoc """
    Node type: do_group
    """
    @enforce_keys [:source_info]
    defstruct [:source_info, :children]

    @type t :: %__MODULE__{
            source_info: BashParser.AST.Types.SourceInfo.t(),
          children: list(any())
          }

    @spec from_map(map()) :: t()
    def from_map(data) do
      %__MODULE__{
        source_info: BashParser.AST.Types.SourceInfo.from_map(data),
          children: BashParser.AST.Types.extract_children(data, "children")
      }
    end

    @spec node_type() :: String.t()
    def node_type, do: "do_group"
  end


  defmodule ElifClause do
    @moduledoc """
    Node type: elif_clause
    """
    @enforce_keys [:source_info]
    defstruct [:source_info, :children]

    @type t :: %__MODULE__{
            source_info: BashParser.AST.Types.SourceInfo.t(),
          children: list(any())
          }

    @spec from_map(map()) :: t()
    def from_map(data) do
      %__MODULE__{
        source_info: BashParser.AST.Types.SourceInfo.from_map(data),
          children: BashParser.AST.Types.extract_children(data, "children")
      }
    end

    @spec node_type() :: String.t()
    def node_type, do: "elif_clause"
  end


  defmodule ElseClause do
    @moduledoc """
    Node type: else_clause
    """
    @enforce_keys [:source_info]
    defstruct [:source_info, :children]

    @type t :: %__MODULE__{
            source_info: BashParser.AST.Types.SourceInfo.t(),
          children: list(any())
          }

    @spec from_map(map()) :: t()
    def from_map(data) do
      %__MODULE__{
        source_info: BashParser.AST.Types.SourceInfo.from_map(data),
          children: BashParser.AST.Types.extract_children(data, "children")
      }
    end

    @spec node_type() :: String.t()
    def node_type, do: "else_clause"
  end


  defmodule ForStatement do
    @moduledoc """
    Node type: for_statement
    """
    @enforce_keys [:source_info, :body, :variable]
    defstruct [:source_info, :body, :value, :variable]

    @type t :: %__MODULE__{
            source_info: BashParser.AST.Types.SourceInfo.t(),
          body: any(),
          value: list(any()),
          variable: any()
          }

    @spec from_map(map()) :: t()
    def from_map(data) do
      %__MODULE__{
        source_info: BashParser.AST.Types.SourceInfo.from_map(data),
          body: BashParser.AST.Types.extract_field(data, "body"),
          value: BashParser.AST.Types.extract_children(data, "value"),
          variable: BashParser.AST.Types.extract_field(data, "variable")
      }
    end

    @spec node_type() :: String.t()
    def node_type, do: "for_statement"
  end


  defmodule FunctionDefinition do
    @moduledoc """
    Node type: function_definition
    """
    @enforce_keys [:source_info, :body, :name]
    defstruct [:source_info, :body, :name, :redirect]

    @type t :: %__MODULE__{
            source_info: BashParser.AST.Types.SourceInfo.t(),
          body: any(),
          name: any(),
          redirect: any() | nil
          }

    @spec from_map(map()) :: t()
    def from_map(data) do
      %__MODULE__{
        source_info: BashParser.AST.Types.SourceInfo.from_map(data),
          body: BashParser.AST.Types.extract_field(data, "body"),
          name: BashParser.AST.Types.extract_field(data, "name"),
          redirect: BashParser.AST.Types.extract_field(data, "redirect")
      }
    end

    @spec node_type() :: String.t()
    def node_type, do: "function_definition"
  end


  defmodule IfStatement do
    @moduledoc """
    Node type: if_statement
    """
    @enforce_keys [:source_info, :condition]
    defstruct [:source_info, :condition, :children]

    @type t :: %__MODULE__{
            source_info: BashParser.AST.Types.SourceInfo.t(),
          condition: list(any()),
          children: list(any())
          }

    @spec from_map(map()) :: t()
    def from_map(data) do
      %__MODULE__{
        source_info: BashParser.AST.Types.SourceInfo.from_map(data),
          condition: BashParser.AST.Types.extract_children(data, "condition"),
          children: BashParser.AST.Types.extract_children(data, "children")
      }
    end

    @spec node_type() :: String.t()
    def node_type, do: "if_statement"
  end


  defmodule List do
    @moduledoc """
    Node type: list
    """
    @enforce_keys [:source_info]
    defstruct [:source_info, :children]

    @type t :: %__MODULE__{
            source_info: BashParser.AST.Types.SourceInfo.t(),
          children: list(any())
          }

    @spec from_map(map()) :: t()
    def from_map(data) do
      %__MODULE__{
        source_info: BashParser.AST.Types.SourceInfo.from_map(data),
          children: BashParser.AST.Types.extract_children(data, "children")
      }
    end

    @spec node_type() :: String.t()
    def node_type, do: "list"
  end


  defmodule NegatedCommand do
    @moduledoc """
    Node type: negated_command
    """
    @enforce_keys [:source_info]
    defstruct [:source_info, :children]

    @type t :: %__MODULE__{
            source_info: BashParser.AST.Types.SourceInfo.t(),
          children: list(any())
          }

    @spec from_map(map()) :: t()
    def from_map(data) do
      %__MODULE__{
        source_info: BashParser.AST.Types.SourceInfo.from_map(data),
          children: BashParser.AST.Types.extract_children(data, "children")
      }
    end

    @spec node_type() :: String.t()
    def node_type, do: "negated_command"
  end


  defmodule Pipeline do
    @moduledoc """
    Node type: pipeline
    """
    @enforce_keys [:source_info]
    defstruct [:source_info, :children]

    @type t :: %__MODULE__{
            source_info: BashParser.AST.Types.SourceInfo.t(),
          children: list(any())
          }

    @spec from_map(map()) :: t()
    def from_map(data) do
      %__MODULE__{
        source_info: BashParser.AST.Types.SourceInfo.from_map(data),
          children: BashParser.AST.Types.extract_children(data, "children")
      }
    end

    @spec node_type() :: String.t()
    def node_type, do: "pipeline"
  end


  defmodule RedirectedStatement do
    @moduledoc """
    Node type: redirected_statement
    """
    @enforce_keys [:source_info]
    defstruct [:source_info, :body, :redirect, :children]

    @type t :: %__MODULE__{
            source_info: BashParser.AST.Types.SourceInfo.t(),
          body: any() | nil,
          redirect: list(any()),
          children: list(any())
          }

    @spec from_map(map()) :: t()
    def from_map(data) do
      %__MODULE__{
        source_info: BashParser.AST.Types.SourceInfo.from_map(data),
          body: BashParser.AST.Types.extract_field(data, "body"),
          redirect: BashParser.AST.Types.extract_children(data, "redirect"),
          children: BashParser.AST.Types.extract_children(data, "children")
      }
    end

    @spec node_type() :: String.t()
    def node_type, do: "redirected_statement"
  end


  defmodule Subshell do
    @moduledoc """
    Node type: subshell
    """
    @enforce_keys [:source_info]
    defstruct [:source_info, :children]

    @type t :: %__MODULE__{
            source_info: BashParser.AST.Types.SourceInfo.t(),
          children: list(any())
          }

    @spec from_map(map()) :: t()
    def from_map(data) do
      %__MODULE__{
        source_info: BashParser.AST.Types.SourceInfo.from_map(data),
          children: BashParser.AST.Types.extract_children(data, "children")
      }
    end

    @spec node_type() :: String.t()
    def node_type, do: "subshell"
  end


  defmodule VariableAssignment do
    @moduledoc """
    Node type: variable_assignment
    """
    @enforce_keys [:source_info, :name, :value]
    defstruct [:source_info, :name, :value]

    @type t :: %__MODULE__{
            source_info: BashParser.AST.Types.SourceInfo.t(),
          name: any(),
          value: any()
          }

    @spec from_map(map()) :: t()
    def from_map(data) do
      %__MODULE__{
        source_info: BashParser.AST.Types.SourceInfo.from_map(data),
          name: BashParser.AST.Types.extract_field(data, "name"),
          value: BashParser.AST.Types.extract_field(data, "value")
      }
    end

    @spec node_type() :: String.t()
    def node_type, do: "variable_assignment"
  end


  defmodule VariableAssignments do
    @moduledoc """
    Node type: variable_assignments
    """
    @enforce_keys [:source_info]
    defstruct [:source_info, :children]

    @type t :: %__MODULE__{
            source_info: BashParser.AST.Types.SourceInfo.t(),
          children: list(any())
          }

    @spec from_map(map()) :: t()
    def from_map(data) do
      %__MODULE__{
        source_info: BashParser.AST.Types.SourceInfo.from_map(data),
          children: BashParser.AST.Types.extract_children(data, "children")
      }
    end

    @spec node_type() :: String.t()
    def node_type, do: "variable_assignments"
  end


  defmodule WhileStatement do
    @moduledoc """
    Node type: while_statement
    """
    @enforce_keys [:source_info, :body, :condition]
    defstruct [:source_info, :body, :condition]

    @type t :: %__MODULE__{
            source_info: BashParser.AST.Types.SourceInfo.t(),
          body: any(),
          condition: list(any())
          }

    @spec from_map(map()) :: t()
    def from_map(data) do
      %__MODULE__{
        source_info: BashParser.AST.Types.SourceInfo.from_map(data),
          body: BashParser.AST.Types.extract_field(data, "body"),
          condition: BashParser.AST.Types.extract_children(data, "condition")
      }
    end

    @spec node_type() :: String.t()
    def node_type, do: "while_statement"
  end


  # OTHERS
  # ==============================================================================

  defmodule ErrorNode do
    @moduledoc """
    Node type: ERROR

    Special node type created by tree-sitter when it encounters syntax errors.
    These nodes indicate actual syntax problems, not incomplete structures.
    """
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


  @type t ::
                  AnsiCString.t()
      |         ArithmeticExpansion.t()
      |         Array.t()
      |         BinaryExpression.t()
      |         BraceExpression.t()
      |         CStyleForStatement.t()
      |         CaseItem.t()
      |         CaseStatement.t()
      |         Command.t()
      |         CommandName.t()
      |         CommandSubstitution.t()
      |         Comment.t()
      |         CompoundStatement.t()
      |         Concatenation.t()
      |         DeclarationCommand.t()
      |         DoGroup.t()
      |         ElifClause.t()
      |         ElseClause.t()
      |         Expansion.t()
      |         ExtglobPattern.t()
      |         FileDescriptor.t()
      |         FileRedirect.t()
      |         ForStatement.t()
      |         FunctionDefinition.t()
      |         HeredocBody.t()
      |         HeredocContent.t()
      |         HeredocEnd.t()
      |         HeredocRedirect.t()
      |         HeredocStart.t()
      |         HerestringRedirect.t()
      |         IfStatement.t()
      |         List.t()
      |         NegatedCommand.t()
      |         Number.t()
      |         ParenthesizedExpression.t()
      |         Pipeline.t()
      |         PostfixExpression.t()
      |         ProcessSubstitution.t()
      |         Program.t()
      |         RawString.t()
      |         RedirectedStatement.t()
      |         Regex.t()
      |         SimpleExpansion.t()
      |         SpecialVariableName.t()
      |         String.t()
      |         StringContent.t()
      |         Subscript.t()
      |         Subshell.t()
      |         TernaryExpression.t()
      |         TestCommand.t()
      |         TestOperator.t()
      |         TranslatedString.t()
      |         UnaryExpression.t()
      |         UnsetCommand.t()
      |         VariableAssignment.t()
      |         VariableAssignments.t()
      |         VariableName.t()
      |         WhileStatement.t()
      |         Word.t()
  |         ErrorNode.t()


  @doc """
  Converts a tree-sitter map to the appropriate typed struct.
  """
  @spec from_map(map()) :: t()
  def from_map(%{"type" => type} = data) do
    case type do
      "ansi_c_string" -> AnsiCString.from_map(data)
      "arithmetic_expansion" -> ArithmeticExpansion.from_map(data)
      "array" -> Array.from_map(data)
      "binary_expression" -> BinaryExpression.from_map(data)
      "brace_expression" -> BraceExpression.from_map(data)
      "c_style_for_statement" -> CStyleForStatement.from_map(data)
      "case_item" -> CaseItem.from_map(data)
      "case_statement" -> CaseStatement.from_map(data)
      "command" -> Command.from_map(data)
      "command_name" -> CommandName.from_map(data)
      "command_substitution" -> CommandSubstitution.from_map(data)
      "comment" -> Comment.from_map(data)
      "compound_statement" -> CompoundStatement.from_map(data)
      "concatenation" -> Concatenation.from_map(data)
      "declaration_command" -> DeclarationCommand.from_map(data)
      "do_group" -> DoGroup.from_map(data)
      "elif_clause" -> ElifClause.from_map(data)
      "else_clause" -> ElseClause.from_map(data)
      "expansion" -> Expansion.from_map(data)
      "extglob_pattern" -> ExtglobPattern.from_map(data)
      "file_descriptor" -> FileDescriptor.from_map(data)
      "file_redirect" -> FileRedirect.from_map(data)
      "for_statement" -> ForStatement.from_map(data)
      "function_definition" -> FunctionDefinition.from_map(data)
      "heredoc_body" -> HeredocBody.from_map(data)
      "heredoc_content" -> HeredocContent.from_map(data)
      "heredoc_end" -> HeredocEnd.from_map(data)
      "heredoc_redirect" -> HeredocRedirect.from_map(data)
      "heredoc_start" -> HeredocStart.from_map(data)
      "herestring_redirect" -> HerestringRedirect.from_map(data)
      "if_statement" -> IfStatement.from_map(data)
      "list" -> List.from_map(data)
      "negated_command" -> NegatedCommand.from_map(data)
      "number" -> Number.from_map(data)
      "parenthesized_expression" -> ParenthesizedExpression.from_map(data)
      "pipeline" -> Pipeline.from_map(data)
      "postfix_expression" -> PostfixExpression.from_map(data)
      "process_substitution" -> ProcessSubstitution.from_map(data)
      "program" -> Program.from_map(data)
      "raw_string" -> RawString.from_map(data)
      "redirected_statement" -> RedirectedStatement.from_map(data)
      "regex" -> Regex.from_map(data)
      "simple_expansion" -> SimpleExpansion.from_map(data)
      "special_variable_name" -> SpecialVariableName.from_map(data)
      "string" -> String.from_map(data)
      "string_content" -> StringContent.from_map(data)
      "subscript" -> Subscript.from_map(data)
      "subshell" -> Subshell.from_map(data)
      "ternary_expression" -> TernaryExpression.from_map(data)
      "test_command" -> TestCommand.from_map(data)
      "test_operator" -> TestOperator.from_map(data)
      "translated_string" -> TranslatedString.from_map(data)
      "unary_expression" -> UnaryExpression.from_map(data)
      "unset_command" -> UnsetCommand.from_map(data)
      "variable_assignment" -> VariableAssignment.from_map(data)
      "variable_assignments" -> VariableAssignments.from_map(data)
      "variable_name" -> VariableName.from_map(data)
      "while_statement" -> WhileStatement.from_map(data)
      "word" -> Word.from_map(data)
      "ERROR" -> ErrorNode.from_map(data)
      _ -> raise "Unknown node type: #{type}"
    end
  end


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


end
