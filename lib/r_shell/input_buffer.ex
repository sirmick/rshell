defmodule RShell.InputBuffer do
  @moduledoc """
  Determines when accumulated input is ready for parsing.

  Uses lightweight lexical analysis to detect incomplete structures without
  relying on tree-sitter AST analysis. This matches bash's approach of having
  separate lexer/parser phases.

  Checks for:
  - Line continuations (backslash-newline)
  - Unclosed quotes (single, double)
  - Unclosed heredocs
  - Open control structures (unclosed braces { } for if/while/for blocks)
  """

  @doc """
  Checks if accumulated input is ready for parsing.

  Returns `true` if input is complete and ready to send to parser.
  Returns `false` if input is incomplete and needs more lines.

  ## Examples

      iex> RShell.InputBuffer.ready_to_parse?("echo hello")
      true

      iex> RShell.InputBuffer.ready_to_parse?("echo hello\\\\")
      false

      iex> RShell.InputBuffer.ready_to_parse?("if (true) {")
      false

      iex> RShell.InputBuffer.ready_to_parse?("if (true) { echo hi }")
      true
  """
  @spec ready_to_parse?(String.t()) :: boolean()
  def ready_to_parse?(input) when is_binary(input) do
    not incomplete?(input)
  end

  @doc """
  Determines what type of continuation is needed (if any).

  Returns one of:
  - `:complete` - Ready to parse
  - `:line_continuation` - Ends with backslash
  - `:quote_continuation` - Unclosed quote
  - `:heredoc_continuation` - Unclosed heredoc
  - `:structure_continuation` - Open control structure
  """
  @spec continuation_type(String.t()) ::
          :complete
          | :line_continuation
          | :quote_continuation
          | :heredoc_continuation
          | :structure_continuation
  def continuation_type(input) when is_binary(input) do
    cond do
      has_line_continuation?(input) -> :line_continuation
      has_unclosed_quote?(input) -> :quote_continuation
      has_unclosed_heredoc?(input) -> :heredoc_continuation
      has_open_control_structure?(input) -> :structure_continuation
      true -> :complete
    end
  end

  # Private helper functions

  defp incomplete?(input) do
    has_line_continuation?(input) or
      has_unclosed_quote?(input) or
      has_unclosed_heredoc?(input) or
      has_open_control_structure?(input)
  end

  defp has_line_continuation?(input) do
    # Check if input ends with backslash-newline (line continuation)
    # In bash, backslash must be IMMEDIATELY before newline to continue
    #
    # Cases:
    # "echo hello\\" (no newline yet) -> true (waiting for newline)
    # "echo hello\\\n" -> true (continuation active)
    # "echo hello\\\ndude\\" -> true (continuation active)
    # "echo hello\\\ndude\\\n\n" -> false (empty line breaks continuation)

    # First, remove ONLY newlines to get the actual last content
    without_newlines = String.trim_trailing(input, "\n")

    # If after removing newlines we end with backslash, it's a continuation
    # UNLESS there are multiple trailing newlines (empty line breaks it)
    if String.ends_with?(without_newlines, "\\") do
      # Count trailing newlines in original input
      trailing_newlines = String.length(input) - String.length(without_newlines)
      # If more than 1 newline, empty line breaks continuation
      trailing_newlines <= 1
    else
      false
    end
  end

  defp has_unclosed_quote?(input) do
    # Count unescaped quotes
    {single_open, double_open} = count_quotes(input)
    single_open or double_open
  end

  defp count_quotes(input) do
    # State machine to track quote context
    # Returns {single_quote_open?, double_quote_open?}
    input
    |> String.graphemes()
    |> Enum.reduce({false, false, false}, fn char, {in_single, in_double, escaped} ->
      cond do
        escaped ->
          # Previous char was backslash, skip this char
          {in_single, in_double, false}

        char == "\\" and not in_single ->
          # Backslash escapes next char (except in single quotes)
          {in_single, in_double, true}

        char == "'" and not in_double ->
          # Toggle single quote
          {not in_single, in_double, false}

        char == "\"" and not in_single ->
          # Toggle double quote
          {in_single, not in_double, false}

        true ->
          {in_single, in_double, false}
      end
    end)
    |> then(fn {single, double, _escaped} -> {single, double} end)
  end

  defp has_unclosed_heredoc?(input) do
    # Check for << followed by delimiter without matching end delimiter
    # This is a simplified check - full heredoc parsing is complex
    lines = String.split(input, "\n")

    # Find heredoc starts (<<MARKER or <<-MARKER)
    heredoc_markers =
      Enum.flat_map(lines, fn line ->
        case Regex.scan(~r/<<-?\s*(\w+)/, line) do
          [] -> []
          matches -> Enum.map(matches, fn [_, marker] -> marker end)
        end
      end)

    # Check if all markers have matching end lines
    Enum.any?(heredoc_markers, fn marker ->
      not Enum.any?(lines, fn line ->
        String.trim(line) == marker
      end)
    end)
  end

  defp has_open_control_structure?(input) do
    # RShell uses brace-based syntax: if (...) { }, for (x in y) { }, while (...) { }
    # Count opening and closing braces, accounting for quote context

    # State: {brace_depth, in_single_quote, in_double_quote, escaped}
    {brace_depth, _, _, _} =
      input
      |> String.graphemes()
      |> Enum.reduce({0, false, false, false}, fn char, {depth, in_single, in_double, escaped} ->
        cond do
          escaped ->
            # Previous char was backslash, skip this char
            {depth, in_single, in_double, false}

          char == "\\" and not in_single ->
            # Backslash escapes next char (except in single quotes)
            {depth, in_single, in_double, true}

          char == "'" and not in_double ->
            # Toggle single quote
            {depth, not in_single, in_double, false}

          char == "\"" and not in_single ->
            # Toggle double quote
            {depth, in_single, not in_double, false}

          char == "{" and not in_single and not in_double ->
            # Opening brace (outside quotes)
            {depth + 1, in_single, in_double, false}

          char == "}" and not in_single and not in_double ->
            # Closing brace (outside quotes)
            {depth - 1, in_single, in_double, false}

          true ->
            {depth, in_single, in_double, false}
        end
      end)

    # If brace depth > 0, we have unclosed braces
    brace_depth > 0
  end
end
