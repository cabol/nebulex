defmodule Nebulex.Adapter do
  @moduledoc """
  This module specifies the adapter API that a Cache adapter is required to
  implement.
  """

  @type t :: module
  @type cache :: Nebulex.Cache.t()
  @type key :: Nebulex.Cache.key()
  @type value :: Nebulex.Cache.value()
  @type object :: Nebulex.Object.t()
  @type opts :: Nebulex.Cache.opts()

  @doc """
  The callback invoked in case the adapter needs to inject code.
  """
  @macrocallback __before_compile__(env :: Macro.Env.t()) :: Macro.t()

  @doc """
  Initializes the adapter supervision tree by returning the children
  """
  @callback init(cache, opts) :: {:ok, [:supervisor.child_spec()]}

  @doc """
  Retrieves a single object from cache.

  See `Nebulex.Cache.get/2`.
  """
  @callback get(cache, key, opts) :: nil | object | no_return

  @doc """
  Stores a single object in the cache.

  See `Nebulex.Cache.set/3`.
  """
  @callback set(cache, object, opts) :: object | no_return

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

  @doc """
  Deletes a single object from cache.

  See `Nebulex.Cache.delete/2`.
  """
  @callback delete(cache, key, opts) :: object | no_return

  @doc """
  Returns and removes the object with key `key` in the cache.

  See `Nebulex.Cache.take/2`.
  """
  @callback take(cache, key, opts) :: nil | object | no_return

  @doc """
  Returns whether the given `key` exists in cache.

  See `Nebulex.Cache.has_key/2`.
  """
  @callback has_key?(cache, key) :: boolean

  @doc """
  Gets the object/value from `key` and updates it, all in one pass.

  See `Nebulex.Cache.get_and_update/3`.
  """
  @callback get_and_update(cache, key, (value -> {get, update} | :pop), opts) ::
              {get, update} | no_return
            when get: value, update: object

  @doc """
  Updates the cached `key` with the given function.

  See `Nebulex.Cache.update/4`.
  """
  @callback update(cache, key, initial :: value, (value -> value), opts) :: object | no_return

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
end
