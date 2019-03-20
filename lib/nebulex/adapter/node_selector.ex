defmodule Nebulex.Adapter.NodeSelector do
  @moduledoc """
  Node Selector Interface.

  The purpose of this module is to allow users implement a custom
  node selector to distribute keys. This interface is used to
  select the node where is supposed the given key remains and
  then be able to execute the requested operation.

  To implement `get_node/2` function, it is highly recommended to use a
  **Consistent Hashing** algorithm.

  ## Example

      defmodule MyApp.MyNodeSelector do
        @behaviour Nebulex.Adapter.NodeSelector

        def get_node(nodes, key) do
          index =
            key
            |> :erlang.phash2()
            |> :jchash.compute(length(nodes))

          Enum.at(nodes, index)
        end
      end

  This example uses [Jumping Consistent Hash](https://github.com/cabol/jchash).
  """

  @doc false
  defmacro __using__(_opts) do
    quote do
      @behaviour Nebulex.Adapter.NodeSelector

      @doc false
      def get_node(nodes, key) do
        Enum.at(nodes, :erlang.phash2(key, length(nodes)))
      end

      defoverridable get_node: 2
    end
  end

  @doc """
  Picks the best node from `nodes` based on the given `key`.

  This callback is invoked by `Nebulex.Adapters.Dist` adapter to
  resolve the node where the current operation will take place.

  ## Example

      MyNodeSelector.get_node([:node1, :node2, :node2], "mykey")
  """
  @callback get_node(nodes :: [node], key :: any) :: node
end
