defmodule BashParser.AST.RShellTypes do
  @moduledoc """
  Typed AST structures for RShell scripts.

  Auto-generated from tree-sitter-rshell grammar (45 node types).

  This module includes RShell-specific extensions like list literals, map literals,
  boolean literals, and RShell-style assignments alongside bash-compatible constructs.

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
    defstruct [:source_info, :argument, :name]

    @type t :: %__MODULE__{
            source_info: BashParser.AST.RShellTypes.SourceInfo.t(),
          argument: list(any()),
          name: any()
          }

    @spec from_map(map()) :: t()
    def from_map(data) do
      %__MODULE__{
        source_info: BashParser.AST.RShellTypes.SourceInfo.from_map(data),
          argument: BashParser.AST.RShellTypes.extract_children(data, "argument"),
          name: BashParser.AST.RShellTypes.extract_field(data, "name")
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
            source_info: BashParser.AST.RShellTypes.SourceInfo.t(),
          children: list(any())
          }

    @spec from_map(map()) :: t()
    def from_map(data) do
      %__MODULE__{
        source_info: BashParser.AST.RShellTypes.SourceInfo.from_map(data),
          children: BashParser.AST.RShellTypes.extract_children(data, "children")
      }
    end

    @spec node_type() :: String.t()
    def node_type, do: "command_name"
  end


  # EXPRESSIONS
  # ==============================================================================

  defmodule BinaryExpression do
    @moduledoc """
    Node type: binary_expression
    """
    @enforce_keys [:source_info]
    defstruct [:source_info, :children]

    @type t :: %__MODULE__{
            source_info: BashParser.AST.RShellTypes.SourceInfo.t(),
          children: list(any())
          }

    @spec from_map(map()) :: t()
    def from_map(data) do
      %__MODULE__{
        source_info: BashParser.AST.RShellTypes.SourceInfo.from_map(data),
          children: BashParser.AST.RShellTypes.extract_children(data, "children")
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
            source_info: BashParser.AST.RShellTypes.SourceInfo.t(),
          children: list(any())
          }

    @spec from_map(map()) :: t()
    def from_map(data) do
      %__MODULE__{
        source_info: BashParser.AST.RShellTypes.SourceInfo.from_map(data),
          children: BashParser.AST.RShellTypes.extract_children(data, "children")
      }
    end

    @spec node_type() :: String.t()
    def node_type, do: "parenthesized_expression"
  end


  defmodule UnaryExpression do
    @moduledoc """
    Node type: unary_expression
    """
    @enforce_keys [:source_info]
    defstruct [:source_info, :children]

    @type t :: %__MODULE__{
            source_info: BashParser.AST.RShellTypes.SourceInfo.t(),
          children: list(any())
          }

    @spec from_map(map()) :: t()
    def from_map(data) do
      %__MODULE__{
        source_info: BashParser.AST.RShellTypes.SourceInfo.from_map(data),
          children: BashParser.AST.RShellTypes.extract_children(data, "children")
      }
    end

    @spec node_type() :: String.t()
    def node_type, do: "unary_expression"
  end


  # LITERALS
  # ==============================================================================

  defmodule Array do
    @moduledoc """
    Node type: array
    """
    @enforce_keys [:source_info]
    defstruct [:source_info, :children]

    @type t :: %__MODULE__{
            source_info: BashParser.AST.RShellTypes.SourceInfo.t(),
          children: list(any())
          }

    @spec from_map(map()) :: t()
    def from_map(data) do
      %__MODULE__{
        source_info: BashParser.AST.RShellTypes.SourceInfo.from_map(data),
          children: BashParser.AST.RShellTypes.extract_children(data, "children")
      }
    end

    @spec node_type() :: String.t()
    def node_type, do: "array"
  end


  defmodule Number do
    @moduledoc """
    Node type: number
    """
    @enforce_keys [:source_info]
    defstruct [:source_info]

    @type t :: %__MODULE__{
            source_info: BashParser.AST.RShellTypes.SourceInfo.t()

          }

    @spec from_map(map()) :: t()
    def from_map(data) do
      %__MODULE__{
        source_info: BashParser.AST.RShellTypes.SourceInfo.from_map(data)

      }
    end

    @spec node_type() :: String.t()
    def node_type, do: "number"
  end


  defmodule String do
    @moduledoc """
    Node type: string
    """
    @enforce_keys [:source_info]
    defstruct [:source_info]

    @type t :: %__MODULE__{
            source_info: BashParser.AST.RShellTypes.SourceInfo.t()

          }

    @spec from_map(map()) :: t()
    def from_map(data) do
      %__MODULE__{
        source_info: BashParser.AST.RShellTypes.SourceInfo.from_map(data)

      }
    end

    @spec node_type() :: String.t()
    def node_type, do: "string"
  end


  defmodule Word do
    @moduledoc """
    Node type: word
    """
    @enforce_keys [:source_info]
    defstruct [:source_info]

    @type t :: %__MODULE__{
            source_info: BashParser.AST.RShellTypes.SourceInfo.t()

          }

    @spec from_map(map()) :: t()
    def from_map(data) do
      %__MODULE__{
        source_info: BashParser.AST.RShellTypes.SourceInfo.from_map(data)

      }
    end

    @spec node_type() :: String.t()
    def node_type, do: "word"
  end


  # OTHERS
  # ==============================================================================

  defmodule Assignment do
    @moduledoc """
    Node type: assignment
    """
    @enforce_keys [:source_info, :name, :operator, :value]
    defstruct [:source_info, :name, :operator, :value]

    @type t :: %__MODULE__{
            source_info: BashParser.AST.RShellTypes.SourceInfo.t(),
          name: any(),
          operator: any(),
          value: any()
          }

    @spec from_map(map()) :: t()
    def from_map(data) do
      %__MODULE__{
        source_info: BashParser.AST.RShellTypes.SourceInfo.from_map(data),
          name: BashParser.AST.RShellTypes.extract_field(data, "name"),
          operator: BashParser.AST.RShellTypes.extract_field(data, "operator"),
          value: BashParser.AST.RShellTypes.extract_field(data, "value")
      }
    end

    @spec node_type() :: String.t()
    def node_type, do: "assignment"
  end


  defmodule Block do
    @moduledoc """
    Node type: block
    """
    @enforce_keys [:source_info]
    defstruct [:source_info, :children]

    @type t :: %__MODULE__{
            source_info: BashParser.AST.RShellTypes.SourceInfo.t(),
          children: list(any())
          }

    @spec from_map(map()) :: t()
    def from_map(data) do
      %__MODULE__{
        source_info: BashParser.AST.RShellTypes.SourceInfo.from_map(data),
          children: BashParser.AST.RShellTypes.extract_children(data, "children")
      }
    end

    @spec node_type() :: String.t()
    def node_type, do: "block"
  end


  defmodule Boolean do
    @moduledoc """
    Node type: boolean
    """
    @enforce_keys [:source_info]
    defstruct [:source_info]

    @type t :: %__MODULE__{
            source_info: BashParser.AST.RShellTypes.SourceInfo.t()

          }

    @spec from_map(map()) :: t()
    def from_map(data) do
      %__MODULE__{
        source_info: BashParser.AST.RShellTypes.SourceInfo.from_map(data)

      }
    end

    @spec node_type() :: String.t()
    def node_type, do: "boolean"
  end


  defmodule BreakStatement do
    @moduledoc """
    Node type: break_statement
    """
    @enforce_keys [:source_info]
    defstruct [:source_info]

    @type t :: %__MODULE__{
            source_info: BashParser.AST.RShellTypes.SourceInfo.t()

          }

    @spec from_map(map()) :: t()
    def from_map(data) do
      %__MODULE__{
        source_info: BashParser.AST.RShellTypes.SourceInfo.from_map(data)

      }
    end

    @spec node_type() :: String.t()
    def node_type, do: "break_statement"
  end


  defmodule CmdExecution do
    @moduledoc """
    Node type: cmd_execution
    """
    @enforce_keys [:source_info]
    defstruct [:source_info, :children]

    @type t :: %__MODULE__{
            source_info: BashParser.AST.RShellTypes.SourceInfo.t(),
          children: list(any())
          }

    @spec from_map(map()) :: t()
    def from_map(data) do
      %__MODULE__{
        source_info: BashParser.AST.RShellTypes.SourceInfo.from_map(data),
          children: BashParser.AST.RShellTypes.extract_children(data, "children")
      }
    end

    @spec node_type() :: String.t()
    def node_type, do: "cmd_execution"
  end


  defmodule CmdLine do
    @moduledoc """
    Node type: cmd_line
    """
    @enforce_keys [:source_info]
    defstruct [:source_info, :children]

    @type t :: %__MODULE__{
            source_info: BashParser.AST.RShellTypes.SourceInfo.t(),
          children: list(any())
          }

    @spec from_map(map()) :: t()
    def from_map(data) do
      %__MODULE__{
        source_info: BashParser.AST.RShellTypes.SourceInfo.from_map(data),
          children: BashParser.AST.RShellTypes.extract_children(data, "children")
      }
    end

    @spec node_type() :: String.t()
    def node_type, do: "cmd_line"
  end


  defmodule CmdSubstitution do
    @moduledoc """
    Node type: cmd_substitution
    """
    @enforce_keys [:source_info]
    defstruct [:source_info, :children]

    @type t :: %__MODULE__{
            source_info: BashParser.AST.RShellTypes.SourceInfo.t(),
          children: list(any())
          }

    @spec from_map(map()) :: t()
    def from_map(data) do
      %__MODULE__{
        source_info: BashParser.AST.RShellTypes.SourceInfo.from_map(data),
          children: BashParser.AST.RShellTypes.extract_children(data, "children")
      }
    end

    @spec node_type() :: String.t()
    def node_type, do: "cmd_substitution"
  end


  defmodule CommandArgument do
    @moduledoc """
    Node type: command_argument
    """
    @enforce_keys [:source_info]
    defstruct [:source_info, :children]

    @type t :: %__MODULE__{
            source_info: BashParser.AST.RShellTypes.SourceInfo.t(),
          children: list(any())
          }

    @spec from_map(map()) :: t()
    def from_map(data) do
      %__MODULE__{
        source_info: BashParser.AST.RShellTypes.SourceInfo.from_map(data),
          children: BashParser.AST.RShellTypes.extract_children(data, "children")
      }
    end

    @spec node_type() :: String.t()
    def node_type, do: "command_argument"
  end


  defmodule CommandFlag do
    @moduledoc """
    Node type: command_flag
    """
    @enforce_keys [:source_info]
    defstruct [:source_info]

    @type t :: %__MODULE__{
            source_info: BashParser.AST.RShellTypes.SourceInfo.t()

          }

    @spec from_map(map()) :: t()
    def from_map(data) do
      %__MODULE__{
        source_info: BashParser.AST.RShellTypes.SourceInfo.from_map(data)

      }
    end

    @spec node_type() :: String.t()
    def node_type, do: "command_flag"
  end


  defmodule Comment do
    @moduledoc """
    Node type: comment
    """
    @enforce_keys [:source_info]
    defstruct [:source_info]

    @type t :: %__MODULE__{
            source_info: BashParser.AST.RShellTypes.SourceInfo.t()

          }

    @spec from_map(map()) :: t()
    def from_map(data) do
      %__MODULE__{
        source_info: BashParser.AST.RShellTypes.SourceInfo.from_map(data)

      }
    end

    @spec node_type() :: String.t()
    def node_type, do: "comment"
  end


  defmodule ContinueStatement do
    @moduledoc """
    Node type: continue_statement
    """
    @enforce_keys [:source_info]
    defstruct [:source_info]

    @type t :: %__MODULE__{
            source_info: BashParser.AST.RShellTypes.SourceInfo.t()

          }

    @spec from_map(map()) :: t()
    def from_map(data) do
      %__MODULE__{
        source_info: BashParser.AST.RShellTypes.SourceInfo.from_map(data)

      }
    end

    @spec node_type() :: String.t()
    def node_type, do: "continue_statement"
  end


  defmodule ControlFlow do
    @moduledoc """
    Node type: control_flow
    """
    @enforce_keys [:source_info]
    defstruct [:source_info, :children]

    @type t :: %__MODULE__{
            source_info: BashParser.AST.RShellTypes.SourceInfo.t(),
          children: list(any())
          }

    @spec from_map(map()) :: t()
    def from_map(data) do
      %__MODULE__{
        source_info: BashParser.AST.RShellTypes.SourceInfo.from_map(data),
          children: BashParser.AST.RShellTypes.extract_children(data, "children")
      }
    end

    @spec node_type() :: String.t()
    def node_type, do: "control_flow"
  end


  defmodule ExprBlock do
    @moduledoc """
    Node type: expr_block
    """
    @enforce_keys [:source_info]
    defstruct [:source_info, :children]

    @type t :: %__MODULE__{
            source_info: BashParser.AST.RShellTypes.SourceInfo.t(),
          children: list(any())
          }

    @spec from_map(map()) :: t()
    def from_map(data) do
      %__MODULE__{
        source_info: BashParser.AST.RShellTypes.SourceInfo.from_map(data),
          children: BashParser.AST.RShellTypes.extract_children(data, "children")
      }
    end

    @spec node_type() :: String.t()
    def node_type, do: "expr_block"
  end


  defmodule ExprInterpolation do
    @moduledoc """
    Node type: expr_interpolation
    """
    @enforce_keys [:source_info]
    defstruct [:source_info, :children]

    @type t :: %__MODULE__{
            source_info: BashParser.AST.RShellTypes.SourceInfo.t(),
          children: list(any())
          }

    @spec from_map(map()) :: t()
    def from_map(data) do
      %__MODULE__{
        source_info: BashParser.AST.RShellTypes.SourceInfo.from_map(data),
          children: BashParser.AST.RShellTypes.extract_children(data, "children")
      }
    end

    @spec node_type() :: String.t()
    def node_type, do: "expr_interpolation"
  end


  defmodule ExprLine do
    @moduledoc """
    Node type: expr_line
    """
    @enforce_keys [:source_info]
    defstruct [:source_info, :children]

    @type t :: %__MODULE__{
            source_info: BashParser.AST.RShellTypes.SourceInfo.t(),
          children: list(any())
          }

    @spec from_map(map()) :: t()
    def from_map(data) do
      %__MODULE__{
        source_info: BashParser.AST.RShellTypes.SourceInfo.from_map(data),
          children: BashParser.AST.RShellTypes.extract_children(data, "children")
      }
    end

    @spec node_type() :: String.t()
    def node_type, do: "expr_line"
  end


  defmodule Expression do
    @moduledoc """
    Node type: expression
    """
    @enforce_keys [:source_info]
    defstruct [:source_info, :children]

    @type t :: %__MODULE__{
            source_info: BashParser.AST.RShellTypes.SourceInfo.t(),
          children: list(any())
          }

    @spec from_map(map()) :: t()
    def from_map(data) do
      %__MODULE__{
        source_info: BashParser.AST.RShellTypes.SourceInfo.from_map(data),
          children: BashParser.AST.RShellTypes.extract_children(data, "children")
      }
    end

    @spec node_type() :: String.t()
    def node_type, do: "expression"
  end


  defmodule FunctionCall do
    @moduledoc """
    Node type: function_call
    """
    @enforce_keys [:source_info, :name]
    defstruct [:source_info, :name, :children]

    @type t :: %__MODULE__{
            source_info: BashParser.AST.RShellTypes.SourceInfo.t(),
          name: any(),
          children: list(any())
          }

    @spec from_map(map()) :: t()
    def from_map(data) do
      %__MODULE__{
        source_info: BashParser.AST.RShellTypes.SourceInfo.from_map(data),
          name: BashParser.AST.RShellTypes.extract_field(data, "name"),
          children: BashParser.AST.RShellTypes.extract_children(data, "children")
      }
    end

    @spec node_type() :: String.t()
    def node_type, do: "function_call"
  end


  defmodule Identifier do
    @moduledoc """
    Node type: identifier
    """
    @enforce_keys [:source_info]
    defstruct [:source_info]

    @type t :: %__MODULE__{
            source_info: BashParser.AST.RShellTypes.SourceInfo.t()

          }

    @spec from_map(map()) :: t()
    def from_map(data) do
      %__MODULE__{
        source_info: BashParser.AST.RShellTypes.SourceInfo.from_map(data)

      }
    end

    @spec node_type() :: String.t()
    def node_type, do: "identifier"
  end


  defmodule Literal do
    @moduledoc """
    Node type: literal
    """
    @enforce_keys [:source_info]
    defstruct [:source_info, :children]

    @type t :: %__MODULE__{
            source_info: BashParser.AST.RShellTypes.SourceInfo.t(),
          children: list(any())
          }

    @spec from_map(map()) :: t()
    def from_map(data) do
      %__MODULE__{
        source_info: BashParser.AST.RShellTypes.SourceInfo.from_map(data),
          children: BashParser.AST.RShellTypes.extract_children(data, "children")
      }
    end

    @spec node_type() :: String.t()
    def node_type, do: "literal"
  end


  defmodule Newline do
    @moduledoc """
    Node type: newline
    """
    @enforce_keys [:source_info]
    defstruct [:source_info]

    @type t :: %__MODULE__{
            source_info: BashParser.AST.RShellTypes.SourceInfo.t()

          }

    @spec from_map(map()) :: t()
    def from_map(data) do
      %__MODULE__{
        source_info: BashParser.AST.RShellTypes.SourceInfo.from_map(data)

      }
    end

    @spec node_type() :: String.t()
    def node_type, do: "newline"
  end


  defmodule Object do
    @moduledoc """
    Node type: object
    """
    @enforce_keys [:source_info]
    defstruct [:source_info, :children]

    @type t :: %__MODULE__{
            source_info: BashParser.AST.RShellTypes.SourceInfo.t(),
          children: list(any())
          }

    @spec from_map(map()) :: t()
    def from_map(data) do
      %__MODULE__{
        source_info: BashParser.AST.RShellTypes.SourceInfo.from_map(data),
          children: BashParser.AST.RShellTypes.extract_children(data, "children")
      }
    end

    @spec node_type() :: String.t()
    def node_type, do: "object"
  end


  defmodule ObjectEntry do
    @moduledoc """
    Node type: object_entry
    """
    @enforce_keys [:source_info, :key, :value]
    defstruct [:source_info, :key, :value]

    @type t :: %__MODULE__{
            source_info: BashParser.AST.RShellTypes.SourceInfo.t(),
          key: any(),
          value: any()
          }

    @spec from_map(map()) :: t()
    def from_map(data) do
      %__MODULE__{
        source_info: BashParser.AST.RShellTypes.SourceInfo.from_map(data),
          key: BashParser.AST.RShellTypes.extract_field(data, "key"),
          value: BashParser.AST.RShellTypes.extract_field(data, "value")
      }
    end

    @spec node_type() :: String.t()
    def node_type, do: "object_entry"
  end


  defmodule Parenthesized do
    @moduledoc """
    Node type: parenthesized
    """
    @enforce_keys [:source_info]
    defstruct [:source_info, :children]

    @type t :: %__MODULE__{
            source_info: BashParser.AST.RShellTypes.SourceInfo.t(),
          children: list(any())
          }

    @spec from_map(map()) :: t()
    def from_map(data) do
      %__MODULE__{
        source_info: BashParser.AST.RShellTypes.SourceInfo.from_map(data),
          children: BashParser.AST.RShellTypes.extract_children(data, "children")
      }
    end

    @spec node_type() :: String.t()
    def node_type, do: "parenthesized"
  end


  defmodule Path do
    @moduledoc """
    Node type: path
    """
    @enforce_keys [:source_info]
    defstruct [:source_info]

    @type t :: %__MODULE__{
            source_info: BashParser.AST.RShellTypes.SourceInfo.t()

          }

    @spec from_map(map()) :: t()
    def from_map(data) do
      %__MODULE__{
        source_info: BashParser.AST.RShellTypes.SourceInfo.from_map(data)

      }
    end

    @spec node_type() :: String.t()
    def node_type, do: "path"
  end


  defmodule Program do
    @moduledoc """
    Node type: program
    """
    @enforce_keys [:source_info]
    defstruct [:source_info, :children]

    @type t :: %__MODULE__{
            source_info: BashParser.AST.RShellTypes.SourceInfo.t(),
          children: list(any())
          }

    @spec from_map(map()) :: t()
    def from_map(data) do
      %__MODULE__{
        source_info: BashParser.AST.RShellTypes.SourceInfo.from_map(data),
          children: BashParser.AST.RShellTypes.extract_children(data, "children")
      }
    end

    @spec node_type() :: String.t()
    def node_type, do: "program"
  end


  defmodule PropertyAccess do
    @moduledoc """
    Node type: property_access
    """
    @enforce_keys [:source_info, :object]
    defstruct [:source_info, :object, :children]

    @type t :: %__MODULE__{
            source_info: BashParser.AST.RShellTypes.SourceInfo.t(),
          object: any(),
          children: list(any())
          }

    @spec from_map(map()) :: t()
    def from_map(data) do
      %__MODULE__{
        source_info: BashParser.AST.RShellTypes.SourceInfo.from_map(data),
          object: BashParser.AST.RShellTypes.extract_field(data, "object"),
          children: BashParser.AST.RShellTypes.extract_children(data, "children")
      }
    end

    @spec node_type() :: String.t()
    def node_type, do: "property_access"
  end


  defmodule PropertyChain do
    @moduledoc """
    Node type: property_chain
    """
    @enforce_keys [:source_info]
    defstruct [:source_info, :property, :children]

    @type t :: %__MODULE__{
            source_info: BashParser.AST.RShellTypes.SourceInfo.t(),
          property: list(any()),
          children: list(any())
          }

    @spec from_map(map()) :: t()
    def from_map(data) do
      %__MODULE__{
        source_info: BashParser.AST.RShellTypes.SourceInfo.from_map(data),
          property: BashParser.AST.RShellTypes.extract_children(data, "property"),
          children: BashParser.AST.RShellTypes.extract_children(data, "children")
      }
    end

    @spec node_type() :: String.t()
    def node_type, do: "property_chain"
  end


  defmodule RawArgument do
    @moduledoc """
    Node type: raw_argument
    """
    @enforce_keys [:source_info]
    defstruct [:source_info, :children]

    @type t :: %__MODULE__{
            source_info: BashParser.AST.RShellTypes.SourceInfo.t(),
          children: list(any())
          }

    @spec from_map(map()) :: t()
    def from_map(data) do
      %__MODULE__{
        source_info: BashParser.AST.RShellTypes.SourceInfo.from_map(data),
          children: BashParser.AST.RShellTypes.extract_children(data, "children")
      }
    end

    @spec node_type() :: String.t()
    def node_type, do: "raw_argument"
  end


  defmodule ReturnStatement do
    @moduledoc """
    Node type: return_statement
    """
    @enforce_keys [:source_info]
    defstruct [:source_info, :children]

    @type t :: %__MODULE__{
            source_info: BashParser.AST.RShellTypes.SourceInfo.t(),
          children: list(any())
          }

    @spec from_map(map()) :: t()
    def from_map(data) do
      %__MODULE__{
        source_info: BashParser.AST.RShellTypes.SourceInfo.from_map(data),
          children: BashParser.AST.RShellTypes.extract_children(data, "children")
      }
    end

    @spec node_type() :: String.t()
    def node_type, do: "return_statement"
  end


  defmodule VariableReference do
    @moduledoc """
    Node type: variable_reference
    """
    @enforce_keys [:source_info]
    defstruct [:source_info, :children]

    @type t :: %__MODULE__{
            source_info: BashParser.AST.RShellTypes.SourceInfo.t(),
          children: list(any())
          }

    @spec from_map(map()) :: t()
    def from_map(data) do
      %__MODULE__{
        source_info: BashParser.AST.RShellTypes.SourceInfo.from_map(data),
          children: BashParser.AST.RShellTypes.extract_children(data, "children")
      }
    end

    @spec node_type() :: String.t()
    def node_type, do: "variable_reference"
  end


  # REDIRECTS
  # ==============================================================================



  # RSHELL_SPECIFIC
  # ==============================================================================



  # STATEMENTS
  # ==============================================================================

  defmodule ElifClause do
    @moduledoc """
    Node type: elif_clause
    """
    @enforce_keys [:source_info, :body, :condition]
    defstruct [:source_info, :body, :condition]

    @type t :: %__MODULE__{
            source_info: BashParser.AST.RShellTypes.SourceInfo.t(),
          body: any(),
          condition: any()
          }

    @spec from_map(map()) :: t()
    def from_map(data) do
      %__MODULE__{
        source_info: BashParser.AST.RShellTypes.SourceInfo.from_map(data),
          body: BashParser.AST.RShellTypes.extract_field(data, "body"),
          condition: BashParser.AST.RShellTypes.extract_field(data, "condition")
      }
    end

    @spec node_type() :: String.t()
    def node_type, do: "elif_clause"
  end


  defmodule ElseClause do
    @moduledoc """
    Node type: else_clause
    """
    @enforce_keys [:source_info, :body]
    defstruct [:source_info, :body]

    @type t :: %__MODULE__{
            source_info: BashParser.AST.RShellTypes.SourceInfo.t(),
          body: any()
          }

    @spec from_map(map()) :: t()
    def from_map(data) do
      %__MODULE__{
        source_info: BashParser.AST.RShellTypes.SourceInfo.from_map(data),
          body: BashParser.AST.RShellTypes.extract_field(data, "body")
      }
    end

    @spec node_type() :: String.t()
    def node_type, do: "else_clause"
  end


  defmodule ForStatement do
    @moduledoc """
    Node type: for_statement
    """
    @enforce_keys [:source_info, :body, :iterable, :variable]
    defstruct [:source_info, :body, :iterable, :variable]

    @type t :: %__MODULE__{
            source_info: BashParser.AST.RShellTypes.SourceInfo.t(),
          body: any(),
          iterable: any(),
          variable: any()
          }

    @spec from_map(map()) :: t()
    def from_map(data) do
      %__MODULE__{
        source_info: BashParser.AST.RShellTypes.SourceInfo.from_map(data),
          body: BashParser.AST.RShellTypes.extract_field(data, "body"),
          iterable: BashParser.AST.RShellTypes.extract_field(data, "iterable"),
          variable: BashParser.AST.RShellTypes.extract_field(data, "variable")
      }
    end

    @spec node_type() :: String.t()
    def node_type, do: "for_statement"
  end


  defmodule IfStatement do
    @moduledoc """
    Node type: if_statement
    """
    @enforce_keys [:source_info, :body, :condition]
    defstruct [:source_info, :alternative, :body, :condition]

    @type t :: %__MODULE__{
            source_info: BashParser.AST.RShellTypes.SourceInfo.t(),
          alternative: list(any()),
          body: any(),
          condition: any()
          }

    @spec from_map(map()) :: t()
    def from_map(data) do
      %__MODULE__{
        source_info: BashParser.AST.RShellTypes.SourceInfo.from_map(data),
          alternative: BashParser.AST.RShellTypes.extract_children(data, "alternative"),
          body: BashParser.AST.RShellTypes.extract_field(data, "body"),
          condition: BashParser.AST.RShellTypes.extract_field(data, "condition")
      }
    end

    @spec node_type() :: String.t()
    def node_type, do: "if_statement"
  end


  defmodule Pipeline do
    @moduledoc """
    Node type: pipeline
    """
    @enforce_keys [:source_info]
    defstruct [:source_info, :children]

    @type t :: %__MODULE__{
            source_info: BashParser.AST.RShellTypes.SourceInfo.t(),
          children: list(any())
          }

    @spec from_map(map()) :: t()
    def from_map(data) do
      %__MODULE__{
        source_info: BashParser.AST.RShellTypes.SourceInfo.from_map(data),
          children: BashParser.AST.RShellTypes.extract_children(data, "children")
      }
    end

    @spec node_type() :: String.t()
    def node_type, do: "pipeline"
  end


  defmodule WhileStatement do
    @moduledoc """
    Node type: while_statement
    """
    @enforce_keys [:source_info, :body, :condition]
    defstruct [:source_info, :body, :condition]

    @type t :: %__MODULE__{
            source_info: BashParser.AST.RShellTypes.SourceInfo.t(),
          body: any(),
          condition: any()
          }

    @spec from_map(map()) :: t()
    def from_map(data) do
      %__MODULE__{
        source_info: BashParser.AST.RShellTypes.SourceInfo.from_map(data),
          body: BashParser.AST.RShellTypes.extract_field(data, "body"),
          condition: BashParser.AST.RShellTypes.extract_field(data, "condition")
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
            source_info: BashParser.AST.RShellTypes.SourceInfo.t(),
          text: String.t() | nil,
          children: list(any())
          }

    @spec from_map(map()) :: t()
    def from_map(data) do
      %__MODULE__{
        source_info: BashParser.AST.RShellTypes.SourceInfo.from_map(data),
          text: Map.get(data, "text"),
          children: BashParser.AST.RShellTypes.extract_children(data, "children")
      }
    end

    @spec node_type() :: String.t()
    def node_type, do: "ERROR"
  end


  @type t ::
                  Array.t()
      |         Assignment.t()
      |         BinaryExpression.t()
      |         Block.t()
      |         Boolean.t()
      |         BreakStatement.t()
      |         CmdExecution.t()
      |         CmdLine.t()
      |         CmdSubstitution.t()
      |         Command.t()
      |         CommandArgument.t()
      |         CommandFlag.t()
      |         CommandName.t()
      |         Comment.t()
      |         ContinueStatement.t()
      |         ControlFlow.t()
      |         ElifClause.t()
      |         ElseClause.t()
      |         ExprBlock.t()
      |         ExprInterpolation.t()
      |         ExprLine.t()
      |         Expression.t()
      |         ForStatement.t()
      |         FunctionCall.t()
      |         Identifier.t()
      |         IfStatement.t()
      |         Literal.t()
      |         Newline.t()
      |         Number.t()
      |         Object.t()
      |         ObjectEntry.t()
      |         Parenthesized.t()
      |         ParenthesizedExpression.t()
      |         Path.t()
      |         Pipeline.t()
      |         Program.t()
      |         PropertyAccess.t()
      |         PropertyChain.t()
      |         RawArgument.t()
      |         ReturnStatement.t()
      |         String.t()
      |         UnaryExpression.t()
      |         VariableReference.t()
      |         WhileStatement.t()
      |         Word.t()
  |         ErrorNode.t()


  @doc """
  Converts a tree-sitter map to the appropriate typed struct.
  """
  @spec from_map(map()) :: t()
  def from_map(%{"type" => type} = data) do
    case type do
      "array" -> Array.from_map(data)
      "assignment" -> Assignment.from_map(data)
      "binary_expression" -> BinaryExpression.from_map(data)
      "block" -> Block.from_map(data)
      "boolean" -> Boolean.from_map(data)
      "break_statement" -> BreakStatement.from_map(data)
      "cmd_execution" -> CmdExecution.from_map(data)
      "cmd_line" -> CmdLine.from_map(data)
      "cmd_substitution" -> CmdSubstitution.from_map(data)
      "command" -> Command.from_map(data)
      "command_argument" -> CommandArgument.from_map(data)
      "command_flag" -> CommandFlag.from_map(data)
      "command_name" -> CommandName.from_map(data)
      "comment" -> Comment.from_map(data)
      "continue_statement" -> ContinueStatement.from_map(data)
      "control_flow" -> ControlFlow.from_map(data)
      "elif_clause" -> ElifClause.from_map(data)
      "else_clause" -> ElseClause.from_map(data)
      "expr_block" -> ExprBlock.from_map(data)
      "expr_interpolation" -> ExprInterpolation.from_map(data)
      "expr_line" -> ExprLine.from_map(data)
      "expression" -> Expression.from_map(data)
      "for_statement" -> ForStatement.from_map(data)
      "function_call" -> FunctionCall.from_map(data)
      "identifier" -> Identifier.from_map(data)
      "if_statement" -> IfStatement.from_map(data)
      "literal" -> Literal.from_map(data)
      "newline" -> Newline.from_map(data)
      "number" -> Number.from_map(data)
      "object" -> Object.from_map(data)
      "object_entry" -> ObjectEntry.from_map(data)
      "parenthesized" -> Parenthesized.from_map(data)
      "parenthesized_expression" -> ParenthesizedExpression.from_map(data)
      "path" -> Path.from_map(data)
      "pipeline" -> Pipeline.from_map(data)
      "program" -> Program.from_map(data)
      "property_access" -> PropertyAccess.from_map(data)
      "property_chain" -> PropertyChain.from_map(data)
      "raw_argument" -> RawArgument.from_map(data)
      "return_statement" -> ReturnStatement.from_map(data)
      "string" -> String.from_map(data)
      "unary_expression" -> UnaryExpression.from_map(data)
      "variable_reference" -> VariableReference.from_map(data)
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
