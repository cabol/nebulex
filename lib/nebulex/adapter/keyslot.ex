defmodule Nebulex.Adapter.Keyslot do
  @moduledoc """
  This behaviour provides a callback to compute the hash slot for a specific
  key based on the number of slots (partitions, nodes, ...).

  The purpose of this module is to allow users to implement a custom
  hash-slot function to distribute the keys. It can be used to select
  the node/slot where a specific key is supposed to be.

  > It is highly recommended to use a **Consistent Hashing** algorithm.

  ## Example

      defmodule MyApp.Keyslot do
        use Nebulex.Adapter.Keyslot

        @impl true
        def hash_slot(key, range) do
          key
          |> :erlang.phash2()
          |> :jchash.compute(range)
        end
      end

  This example uses [Jumping Consistent Hash](https://github.com/cabol/jchash).
  """

  @doc """
  Returns an integer within the range `0..range-1` identifying the hash slot
  the specified `key` hashes to.

  ## Example

      iex> MyKeyslot.hash_slot("mykey", 10)
      2

  """
  @callback hash_slot(key :: any, range :: pos_integer) :: non_neg_integer

  @doc false
  defmacro __using__(_opts) do
    quote do
      @behaviour Nebulex.Adapter.Keyslot

      @impl true
      defdelegate hash_slot(key, range), to: :erlang, as: :phash2

      defoverridable hash_slot: 2
    end
  end
end
