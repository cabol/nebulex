defmodule Nebulex.Adapter do
  @moduledoc """
  This module specifies the adapter API that a Cache adapter is required to
  implement.
  """

  @type t :: module
  @type cache :: Nebulex.Cache.t()
  @type key :: Nebulex.Cache.key()
  @type object :: Nebulex.Object.t()
  @type opts :: Nebulex.Cache.opts()
  @type reducer :: Nebulex.Cache.reducer()

  @doc """
  The callback invoked in case the adapter needs to inject code.
  """
  @macrocallback __before_compile__(env :: Macro.Env.t()) :: Macro.t()

  @doc """
  Initializes the adapter supervision tree by returning the children
  """
  @callback init(cache, opts) :: {:ok, [:supervisor.child_spec()]}

  @doc """
  Retrieves a single object from Cache.

  See `Nebulex.Cache.get/2`.
  """
  @callback get(cache, key, opts) :: nil | object | no_return

  @doc """
  Returns a map with the objects for all specified keys. For every key that
  does not hold a value or does not exist, the special value `nil` is
  returned.

  See `Nebulex.Cache.mget/2`.
  """
  @callback mget(cache, [key], opts) :: map

  @doc """
  Stores a single object in the Cache.

  See `Nebulex.Cache.set/3`.
  """
  @callback set(cache, object, opts) :: object | no_return

  @doc """
  Stores multiple objects in the Cache.

  See `Nebulex.Cache.mset/2`.
  """
  @callback mset(cache, [object], opts) :: :ok | {:error, failed_keys :: [key]}

  @doc """
  Deletes a single object from Cache.

  See `Nebulex.Cache.delete/2`.
  """
  @callback delete(cache, key, opts) :: object | no_return

  @doc """
  Returns whether the given `key` exists in Cache.

  See `Nebulex.Cache.has_key/2`.
  """
  @callback has_key?(cache, key) :: boolean

  @doc """
  Updates (increment or decrement) the counter mapped to the given `key`.

  See `Nebulex.Cache.update_counter/3`.
  """
  @callback update_counter(cache, key, incr :: integer, opts) :: integer | no_return

  @doc """
  Returns the total number of cached entries.

  See `Nebulex.Cache.size/0`.
  """
  @callback size(cache) :: integer

  @doc """
  Flushes the cache.

  See `Nebulex.Cache.flush/0`.
  """
  @callback flush(cache) :: :ok | no_return

  @doc """
  Returns all cached keys.

  See `Nebulex.Cache.keys/0`.
  """
  @callback keys(cache) :: [key]

  @doc """
  Invokes `reducer` for each entry in the cache, passing cached object and
  the accumulator `acc` as arguments. `reducer`’s return value is stored
  in `acc`.

  Returns the accumulator.

  See `Nebulex.Cache.reduce/3`.
  """
  @callback reduce(cache, acc :: any, reducer, opts) :: any

  @doc """
  Returns a map with all cache entries.

  See `Nebulex.Cache.t()o_map/1`.
  """
  @callback to_map(cache, opts) :: map
end
