defmodule RShell.Builtins.Helpers do
  @moduledoc """
  Compile-time macro helpers for builtin commands.

  Provides `use RShell.Builtins.Helpers` which generates:
  - `__builtin_options__/1` - Returns parsed option specs from docstrings
  - `__builtin_help__/1` - Returns formatted help text
  - `parse_builtin_options/2` - Helper to parse argv
  """

  alias RShell.Builtins.{DocParser, OptionParser}

  defmacro __using__(_opts) do
    quote do
      @before_compile RShell.Builtins.Helpers
    end
  end

  defmacro __before_compile__(env) do
    # Collect all function definitions with their docs during compilation
    # We need to use Module.definitions_in/2 to get defined functions
    definitions = Module.definitions_in(env.module, :def)

    # Build list of {name, docstring} for shell_* functions
    builtin_docs =
      definitions
      |> Enum.filter(fn {name, _arity} ->
        String.starts_with?(Atom.to_string(name), "shell_")
      end)
      |> Enum.map(fn {name, arity} ->
        if arity == 3 do
          builtin_name = name
            |> Atom.to_string()
            |> String.trim_leading("shell_")
            |> String.to_atom()

          # Get docstring from accumulated attributes
          # This is a limitation - we need to manually associate docs
          # For now, we'll use a simpler runtime approach
          {builtin_name, nil}
        else
          nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    # Generate stub functions that will be populated at runtime
    option_clauses = Enum.map(builtin_docs, fn {name, _doc} ->
      quote do
        defp __builtin_options__(unquote(name)) do
          # Parse options from runtime docstring lookup
          case Code.fetch_docs(__MODULE__) do
            {:docs_v1, _, _, _, _, _, docs} ->
              shell_func = unquote(String.to_atom("shell_#{name}"))
              case Enum.find(docs, fn {{:function, fname, 3}, _, _, _, _} -> fname == shell_func; _ -> false end) do
                {_, _, _, %{"en" => doc_string}, _} when is_binary(doc_string) ->
                  RShell.Builtins.DocParser.parse_options(doc_string)
                _ ->
                  []
              end
            _ ->
              []
          end
        end

        defp __builtin_help__(unquote(name)) do
          case Code.fetch_docs(__MODULE__) do
            {:docs_v1, _, _, _, _, _, docs} ->
              shell_func = unquote(String.to_atom("shell_#{name}"))
              case Enum.find(docs, fn {{:function, fname, 3}, _, _, _, _} -> fname == shell_func; _ -> false end) do
                {_, _, _, %{"en" => doc_string}, _} when is_binary(doc_string) ->
                  RShell.Builtins.DocParser.extract_help_text(doc_string)
                _ ->
                  "#{unquote(name)} - no documentation available"
              end
            _ ->
              "#{unquote(name)} - no documentation available"
          end
        end
      end
    end)

    # Generate fallback and helper functions
    helper_functions = quote do
      defp __builtin_options__(_unknown), do: []
      defp __builtin_help__(_unknown), do: "No help available"

      @doc """
      Parse builtin options using the generated option specs.

      Returns `{:ok, options_map, remaining_args}` or `{:error, reason}`.
      """
      defp parse_builtin_options(name, argv) do
        RShell.Builtins.OptionParser.parse(argv, __builtin_options__(name))
      end

      @doc """
      Get help text for a builtin command.
      """
      def get_builtin_help(name) when is_atom(name) do
        __builtin_help__(name)
      end

      def get_builtin_help(name) when is_binary(name) do
        __builtin_help__(String.to_atom(name))
      end
    end

    [option_clauses, helper_functions]
  end
end
