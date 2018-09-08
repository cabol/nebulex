defmodule Nebulex.Adapter.Multi do
  @moduledoc """
  Multi API.
  """

  @type cache :: Nebulex.Cache.t()
  @type key :: Nebulex.Cache.key()
  @type opts :: Nebulex.Cache.opts()
  @type object :: Nebulex.Object.t()

  @doc """
  Returns a map with the objects for all specified keys. For every key that
  does not hold a value or does not exist, the special value `nil` is
  returned.

  See `Nebulex.Cache.mget/2`.
  """
  @callback mget(cache, [key], opts) :: map

  @doc """
  Stores multiple objects in the cache.

  See `Nebulex.Cache.mset/2`.
  """
  @callback mset(cache, [object], opts) :: :ok | {:error, failed_keys :: [key]}
end
