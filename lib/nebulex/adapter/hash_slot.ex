defmodule Nebulex.Adapter.HashSlot do
  @moduledoc ~S"""
  This behaviour provides a callback to compute the hash slot for a specific
  key based on the number of slots/nodes.

  The purpose of this module is to allow users to implement a custom
  hash function to distribute keys. It can be used to select the
  node/slot where a specific key is supposed to be.

  > It is highly recommended to use a **Consistent Hashing** algorithm.

  ## Example

      defmodule MyApp.HashSlot do
        @behaviour Nebulex.Adapter.HashSlot

        def keyslot(key, range) do
          key
          |> :erlang.phash2()
          |> :jchash.compute(range)
        end
      end

  This example uses [Jumping Consistent Hash](https://github.com/cabol/jchash).
  """

  @doc false
  defmacro __using__(_opts) do
    quote do
      @behaviour Nebulex.Adapter.HashSlot

      @impl true
      defdelegate keyslot(key, range), to: :erlang, as: :phash2

      defoverridable keyslot: 2
    end
  end

  @doc """
  Computes the hash for a specific `key` based on the number of slots
  given by `range`. Returns a slot within the range `0..range-1`.

  ## Example

      iex> MyHash.keyslot("mykey", 10)
      2
  """
  @callback keyslot(key :: any, range :: pos_integer) :: non_neg_integer
end
