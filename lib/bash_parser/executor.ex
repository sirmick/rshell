defmodule BashParser.Executor do
  @moduledoc """
  Execution engine for Bash AST.

  Provides an interpreter that walks the AST and executes commands,
  maintaining execution context including variables, functions, and exit codes.

  ## Features

  - Variable assignment and expansion
  - Command execution (with configurable execution mode)
  - Function definitions and calls
  - Control flow (if/while/for/case)
  - Exit code tracking
  - Execution modes: :simulate (dry-run), :capture (collect output), :real (execute)

  ## Usage

      # Parse and execute
      {:ok, ast} = RShell.parse("NAME='test'; echo $NAME")
      {:ok, result} = Executor.execute(ast)

      # With custom options
      {:ok, result} = Executor.execute(ast,
        mode: :simulate,
        initial_env: %{"USER" => "admin"}
      )

      # Access execution context
      IO.inspect(result.variables)
      IO.inspect(result.exit_code)
      IO.inspect(result.output)
  """

  alias BashParser.AST.{Walker, Types}
  alias BashParser.Executor.{Context, Builtins}

  @type execution_mode :: :simulate | :capture | :real
  @type execution_result :: %{
    context: Context.t(),
    exit_code: non_neg_integer(),
    output: [String.t()],
    errors: [String.t()]
  }

  @doc """
  Execute a parsed AST.

  Options:
  - `:mode` - Execution mode (:simulate, :capture, :real). Default: :simulate
  - `:initial_env` - Initial environment variables as a map. Default: %{}
  - `:strict` - Stop on first error. Default: false
  """
  @spec execute(Types.Program.t(), keyword()) :: {:ok, execution_result()} | {:error, String.t()}
  def execute(%Types.Program{} = ast, opts \\ []) do
    mode = Keyword.get(opts, :mode, :simulate)
    initial_env = Keyword.get(opts, :initial_env, %{})
    strict = Keyword.get(opts, :strict, false)

    context = Context.new(mode: mode, env: initial_env, strict: strict)

    try do
      final_context = execute_node(ast, context)

      {:ok, %{
        context: final_context,
        exit_code: final_context.exit_code,
        output: Enum.reverse(final_context.output),
        errors: Enum.reverse(final_context.errors)
      }}
    rescue
      e -> {:error, "Execution error: #{inspect(e)}"}
    end
  end

  @doc """
  Execute a single node with the given context.
  """
  @spec execute_node(struct(), Context.t()) :: Context.t()

  # Program node - execute all children sequentially
  def execute_node(%Types.Program{children: children}, context) do
    execute_children(children, context)
  end

  # Variable assignment
  def execute_node(%Types.VariableAssignment{name: name, value: value}, context) do
    var_name = extract_text(name)
    var_value = expand_value(value, context)
    Context.set_variable(context, var_name, var_value)
  end

  # Command execution
  def execute_node(%Types.Command{name: name, argument: args}, context) do
    cmd_name = extract_command_name(name)
    cmd_args = Enum.map(args || [], fn arg -> expand_value(arg, context) end)

    execute_command(cmd_name, cmd_args, context)
  end

  # If statement
  def execute_node(%Types.IfStatement{condition: condition, children: children}, context) do
    # Execute condition
    cond_context = execute_children(condition, context)

    # Check exit code (0 = true in bash)
    if cond_context.exit_code == 0 do
      # Execute then branch (first child is typically a do_group or compound_statement)
      execute_children(children, cond_context)
    else
      # Look for else clause
      else_clause = Enum.find(children, fn child ->
        is_struct(child, Types.ElseClause) or is_struct(child, Types.ElifClause)
      end)

      if else_clause do
        execute_node(else_clause, cond_context)
      else
        cond_context
      end
    end
  end

  # While statement
  def execute_node(%Types.WhileStatement{condition: condition, body: body}, context) do
    execute_while_loop(condition, body, context, 0)
  end

  # For statement
  def execute_node(%Types.ForStatement{variable: variable, value: values, body: body}, context) do
    var_name = extract_text(variable)
    items = Enum.map(values || [], fn val -> expand_value(val, context) end)

    Enum.reduce(items, context, fn item, ctx ->
      ctx_with_var = Context.set_variable(ctx, var_name, item)
      execute_node(body, ctx_with_var)
    end)
  end

  # Case statement
  def execute_node(%Types.CaseStatement{value: value, children: children}, context) do
    case_value = expand_value(value, context)

    # Find matching case item
    matching_item = Enum.find(children, fn child ->
      case child do
        %Types.CaseItem{value: patterns} ->
          Enum.any?(patterns, fn pattern ->
            pattern_str = expand_value(pattern, context)
            matches_pattern?(case_value, pattern_str)
          end)
        _ -> false
      end
    end)

    if matching_item do
      execute_node(matching_item, context)
    else
      context
    end
  end

  # Case item
  def execute_node(%Types.CaseItem{children: children}, context) do
    execute_children(children, context)
  end

  # Function definition
  def execute_node(%Types.FunctionDefinition{name: name, body: body}, context) do
    func_name = extract_text(name)
    Context.define_function(context, func_name, body)
  end

  # Compound statement, do_group, subshell
  def execute_node(%Types.CompoundStatement{children: children}, context) do
    execute_children(children, context)
  end

  def execute_node(%Types.DoGroup{children: children}, context) do
    execute_children(children, context)
  end

  def execute_node(%Types.Subshell{children: children}, context) do
    # Create new scope for subshell
    subshell_context = Context.push_scope(context)
    result_context = execute_children(children, subshell_context)
    Context.pop_scope(result_context)
  end

  # Pipeline
  def execute_node(%Types.Pipeline{children: children}, context) do
    # Execute commands in pipeline (simplified - just execute sequentially for now)
    execute_children(children, context)
  end

  # List (command sequences with && || ;)
  def execute_node(%Types.List{children: children}, context) do
    execute_children(children, context)
  end

  # Else clause
  def execute_node(%Types.ElseClause{children: children}, context) do
    execute_children(children, context)
  end

  # Elif clause
  def execute_node(%Types.ElifClause{children: children}, context) do
    # Similar to if statement logic
    execute_children(children, context)
  end

  # Comment - skip
  def execute_node(%Types.Comment{}, context), do: context

  # Redirected statement
  def execute_node(%Types.RedirectedStatement{body: body}, context) do
    # Simplified: just execute the body, ignore redirects for now
    if body, do: execute_node(body, context), else: context
  end

  # String and literals
  def execute_node(%Types.String{}, context), do: context
  def execute_node(%Types.Word{}, context), do: context
  def execute_node(%Types.Number{}, context), do: context
  def execute_node(%Types.StringContent{}, context), do: context

  # Default - skip unknown nodes
  def execute_node(_node, context), do: context

  # Private Helpers

  defp execute_children(children, context) when is_list(children) do
    Enum.reduce(children, context, fn child, ctx ->
      if ctx.strict and ctx.exit_code != 0 do
        ctx
      else
        execute_node(child, ctx)
      end
    end)
  end

  defp execute_children(nil, context), do: context
  defp execute_children(child, context), do: execute_node(child, context)

  defp execute_while_loop(condition, body, context, iteration) when iteration < 1000 do
    cond_context = execute_children(condition, context)

    if cond_context.exit_code == 0 do
      body_context = execute_node(body, cond_context)
      execute_while_loop(condition, body, body_context, iteration + 1)
    else
      cond_context
    end
  end

  defp execute_while_loop(_condition, _body, context, _iteration) do
    # Max iterations reached
    Context.add_error(context, "While loop exceeded maximum iterations (1000)")
  end

  defp execute_command(cmd_name, args, context) do
    # Use the extensible builtin system
    Builtins.execute(cmd_name, args, context)
  end

  defp extract_command_name(name) when is_struct(name) do
    case name do
      %Types.CommandName{source_info: info} -> info.text
      %Types.Word{source_info: info} -> info.text
      node -> extract_text(node)
    end
  end

  defp extract_command_name(name), do: to_string(name)

  defp extract_text(nil), do: ""
  defp extract_text(%{source_info: %{text: text}}) when is_binary(text), do: text
  defp extract_text(value) when is_binary(value), do: value
  defp extract_text(_), do: ""

  defp expand_value(nil, _context), do: ""

  defp expand_value(%Types.SimpleExpansion{children: children}, context) do
    # Variable expansion: $VAR
    var_name = case children do
      [%Types.VariableName{source_info: info} | _] -> info.text
      [%{source_info: info} | _] -> info.text
      _ -> ""
    end
    Context.get_variable(context, var_name, "")
  end

  defp expand_value(%Types.String{source_info: info}, _context) do
    # Remove quotes
    text = info.text
    String.trim(text, "\"")
  end

  defp expand_value(%Types.RawString{source_info: info}, _context) do
    text = info.text
    String.trim(text, "'")
  end

  defp expand_value(%Types.Word{source_info: info}, _context) do
    info.text
  end

  defp expand_value(%{source_info: %{text: text}}, _context) when is_binary(text) do
    text
  end

  defp expand_value(value, _context) when is_binary(value), do: value
  defp expand_value(_value, _context), do: ""

  defp matches_pattern?(value, pattern) do
    # Simple pattern matching (can be enhanced with glob patterns)
    value == pattern or pattern == "*"
  end
end
