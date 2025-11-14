defmodule BashParser.AST.Walker do
  @moduledoc """
  Generic AST walker implementation using the visitor pattern.

  Provides flexible traversal strategies (pre-order, post-order, breadth-first)
  and callback hooks for visiting different node types.

  ## Usage

      # Simple traversal with callback
      Walker.walk(ast, fn node ->
        IO.inspect(node.__struct__)
        :continue
      end)

      # With accumulator
      count = Walker.reduce(ast, 0, fn node, acc ->
        {acc + 1, :continue}
      end)

      # Type-specific visitors
      visitors = %{
        command: fn cmd, ctx ->
          IO.puts("Found command")
          {:ok, ctx}
        end
      }
      Walker.walk_with_visitors(ast, visitors, initial_context)
  """

  # alias BashParser.AST.Types  # Unused alias

  @type ast_node :: struct()
  @type visitor_result :: :continue | :skip_children | {:halt, any()}
  @type visitor_fn :: (ast_node() -> visitor_result())
  @type visitor_map :: %{atom() => (ast_node(), any() -> {any(), visitor_result()})}
  @type traversal_order :: :pre | :post | :breadth

  @doc """
  Walk the AST with a simple callback function.

  The callback receives each node and should return:
  - `:continue` - continue walking
  - `:skip_children` - skip children of this node
  - `{:halt, value}` - stop walking and return value
  """
  @spec walk(ast_node(), visitor_fn(), traversal_order()) :: :ok | {:halted, any()}
  def walk(node, callback, order \\ :pre)

  def walk(node, callback, :pre) when is_struct(node) do
    case callback.(node) do
      :continue ->
        walk_children(node, callback, :pre)
        :ok

      :skip_children ->
        :ok

      {:halt, value} ->
        {:halted, value}
    end
  end

  def walk(node, callback, :post) when is_struct(node) do
    case walk_children(node, callback, :post) do
      {:halted, _} = halted ->
        halted

      :ok ->
        case callback.(node) do
          {:halt, value} -> {:halted, value}
          _ -> :ok
        end
    end
  end

  def walk(node, callback, :breadth) when is_struct(node) do
    walk_breadth_first(node, callback)
  end

  def walk(_node, _callback, _order), do: :ok

  @doc """
  Walk the AST with an accumulator (like Enum.reduce).

  The callback receives each node and accumulator, returns {new_acc, action}.
  """
  @spec reduce(ast_node(), acc, (ast_node(), acc -> {acc, visitor_result()})) :: acc
        when acc: any()
  def reduce(node, acc, callback, order \\ :pre)

  def reduce(node, acc, callback, :pre) when is_struct(node) do
    case callback.(node, acc) do
      {new_acc, :continue} ->
        reduce_children(node, new_acc, callback, :pre)

      {new_acc, :skip_children} ->
        new_acc

      {new_acc, {:halt, _}} ->
        new_acc
    end
  end

  def reduce(node, acc, callback, :post) when is_struct(node) do
    new_acc = reduce_children(node, acc, callback, :post)

    case callback.(node, new_acc) do
      {final_acc, _} -> final_acc
    end
  end

  def reduce(_node, acc, _callback, _order), do: acc

  @doc """
  Walk the AST with type-specific visitor functions.

  ## Example

      visitors = %{
        command: fn cmd, ctx ->
          new_ctx = Map.update(ctx, :command_count, 1, &(&1 + 1))
          {new_ctx, :continue}
        end,
        variable_assignment: fn assign, ctx ->
          new_ctx = put_in(ctx, [:vars, assign.name], assign.value)
          {new_ctx, :continue}
        end
      }

      context = Walker.walk_with_visitors(ast, visitors, %{command_count: 0, vars: %{}})
  """
  @spec walk_with_visitors(ast_node(), visitor_map(), any(), traversal_order()) :: any()
  def walk_with_visitors(node, visitors, context, order \\ :pre) do
    reduce(
      node,
      context,
      fn node, ctx ->
        node_type = get_node_type(node)

        case Map.get(visitors, node_type) do
          nil -> {ctx, :continue}
          visitor_fn -> visitor_fn.(node, ctx)
        end
      end,
      order
    )
  end

  @doc """
  Collect all nodes matching a predicate.
  """
  @spec collect(ast_node(), (ast_node() -> boolean())) :: [ast_node()]
  def collect(node, predicate) do
    reduce(node, [], fn n, acc ->
      if predicate.(n) do
        {[n | acc], :continue}
      else
        {acc, :continue}
      end
    end)
    |> Enum.reverse()
  end

  @doc """
  Find the first node matching a predicate.
  """
  @spec find(ast_node(), (ast_node() -> boolean())) :: ast_node() | nil
  def find(node, predicate) do
    case walk(node, fn n ->
           if predicate.(n), do: {:halt, n}, else: :continue
         end) do
      {:halted, found} -> found
      :ok -> nil
    end
  end

  @doc """
  Get all nodes of a specific type.
  """
  @spec collect_by_type(ast_node(), String.t() | [String.t()]) :: [ast_node()]
  def collect_by_type(node, types) when is_list(types) do
    type_set = MapSet.new(types)

    collect(node, fn n ->
      MapSet.member?(type_set, get_node_type(n))
    end)
  end

  def collect_by_type(node, type) when is_binary(type) do
    collect(node, fn n -> get_node_type(n) == type end)
  end

  @doc """
  Transform the AST by applying a function to each node.
  Returns a new AST with transformed nodes.
  """
  @spec transform(ast_node(), (ast_node() -> ast_node())) :: ast_node()
  def transform(node, transformer) when is_struct(node) do
    # Transform children first (post-order)
    node_with_transformed_children = transform_children(node, transformer)

    # Then transform this node
    transformer.(node_with_transformed_children)
  end

  def transform(value, _transformer), do: value

  @doc """
  Get statistics about the AST structure.
  """
  @spec statistics(ast_node()) :: %{
          total_nodes: non_neg_integer(),
          node_types: %{String.t() => non_neg_integer()},
          max_depth: non_neg_integer()
        }
  def statistics(node) do
    stats =
      reduce(node, %{total_nodes: 0, node_types: %{}, depth: 0, max_depth: 0}, fn n, acc ->
        node_type = get_node_type(n)

        {
          acc
          |> Map.update!(:total_nodes, &(&1 + 1))
          |> Map.update!(:node_types, fn types ->
            Map.update(types, node_type, 1, &(&1 + 1))
          end),
          :continue
        }
      end)

    Map.delete(stats, :depth)
  end

  # Private Helpers

  defp walk_children(node, callback, order) when is_struct(node) do
    node
    |> Map.from_struct()
    |> Enum.reduce_while(:ok, fn {_key, value}, _acc ->
      case walk_value(value, callback, order) do
        :ok -> {:cont, :ok}
        {:halted, _} = halted -> {:halt, halted}
      end
    end)
  end

  defp walk_value(value, callback, order) when is_struct(value) do
    walk(value, callback, order)
  end

  defp walk_value(values, callback, order) when is_list(values) do
    Enum.reduce_while(values, :ok, fn value, _acc ->
      case walk_value(value, callback, order) do
        :ok -> {:cont, :ok}
        {:halted, _} = halted -> {:halt, halted}
      end
    end)
  end

  defp walk_value(_value, _callback, _order), do: :ok

  defp reduce_children(node, acc, callback, order) when is_struct(node) do
    node
    |> Map.from_struct()
    |> Enum.reduce(acc, fn {_key, value}, current_acc ->
      reduce_value(value, current_acc, callback, order)
    end)
  end

  defp reduce_value(value, acc, callback, order) when is_struct(value) do
    reduce(value, acc, callback, order)
  end

  defp reduce_value(values, acc, callback, order) when is_list(values) do
    Enum.reduce(values, acc, fn value, current_acc ->
      reduce_value(value, current_acc, callback, order)
    end)
  end

  defp reduce_value(_value, acc, _callback, _order), do: acc

  defp walk_breadth_first(root, callback) do
    queue = :queue.from_list([root])
    walk_breadth_loop(queue, callback)
  end

  defp walk_breadth_loop(queue, callback) do
    case :queue.out(queue) do
      {{:value, node}, rest} ->
        case callback.(node) do
          :continue ->
            children = get_all_children(node)
            new_queue = Enum.reduce(children, rest, fn child, q -> :queue.in(child, q) end)
            walk_breadth_loop(new_queue, callback)

          :skip_children ->
            walk_breadth_loop(rest, callback)

          {:halt, value} ->
            {:halted, value}
        end

      {:empty, _} ->
        :ok
    end
  end

  defp get_all_children(node) when is_struct(node) do
    node
    |> Map.from_struct()
    |> Enum.flat_map(fn {_key, value} ->
      get_children_from_value(value)
    end)
  end

  defp get_children_from_value(value) when is_struct(value), do: [value]

  defp get_children_from_value(values) when is_list(values) do
    Enum.filter(values, &is_struct/1)
  end

  defp get_children_from_value(_), do: []

  defp transform_children(node, transformer) when is_struct(node) do
    node
    |> Map.from_struct()
    |> Enum.map(fn {key, value} ->
      {key, transform_value(value, transformer)}
    end)
    |> then(fn fields -> struct(node.__struct__, fields) end)
  end

  defp transform_value(value, transformer) when is_struct(value) do
    transform(value, transformer)
  end

  defp transform_value(values, transformer) when is_list(values) do
    Enum.map(values, fn value ->
      if is_struct(value) do
        transform(value, transformer)
      else
        value
      end
    end)
  end

  defp transform_value(value, _transformer), do: value

  defp get_node_type(node) when is_struct(node) do
    module = node.__struct__

    module
    |> Module.split()
    |> List.last()
    |> Macro.underscore()
  end

  defp get_node_type(_), do: nil
end
