defmodule Nebulex.Adapters.Dist.NodePicker do
  @moduledoc """
  Node Picker Interface.

  The purpose of this module is to allow users implement a custom
  node picker/selector to distribute keys. This interface is used
  to cherry-pick the node where is supposed the given key remains
  and then be able to execute the requested operation.

  To implement `pick_node/2` function, it is highly recommended to use a
  **Consistent Hashing** algorithm.

  ## Example

      defmodule MyApp.MyNodePicker do
        @behaviour Nebulex.Adapters.Dist.NodePicker

        def pick_node(nodes, key) do
          key
          |> :erlang.phash2()
          |> :jchash.compute(length(nodes))
          |> Kernel.+(1)
          |> :lists.nth(nodes)
        end
      end

  This example uses [Jumping Consistent Hash](https://github.com/cabol/jchash).
  """

  @doc false
  defmacro __using__(_opts) do
    quote do
      @behaviour Nebulex.Adapters.Dist.NodePicker

      def pick_node(nodes, key) do
        key
        |> :erlang.phash2(length(nodes))
        |> Kernel.+(1)
        |> :lists.nth(nodes)
      end

      defoverridable [pick_node: 2]
    end
  end

  @doc """
  Picks the best node from `nodes` based on the given `key`.

  This callback is invoked by `Nebulex.Adapters.Dist` adapter to
  resolve the node where the current operation will take place.

  ## Example

      pick_node([:node1, :node2, :node2], "mykey")
  """
  @callback pick_node(nodes :: [node], key :: any) :: node
end
