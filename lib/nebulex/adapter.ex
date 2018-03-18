defmodule Nebulex.Adapter do
  @moduledoc """
  This module specifies the adapter API that a Cache adapter is required to
  implement.
  """

  @type t       :: module
  @type cache   :: Nebulex.Cache.t
  @type key     :: Nebulex.Cache.key
  @type value   :: Nebulex.Cache.value
  @type object  :: Nebulex.Object.t
  @type opts    :: Nebulex.Cache.opts
  @type return  :: Nebulex.Cache.return
  @type reducer :: Nebulex.Cache.reducer

  @doc """
  The callback invoked in case the adapter needs to inject code.
  """
  @macrocallback __before_compile__(env :: Macro.Env.t) :: Macro.t

  @doc """
  Returns the children specs that starts the adapter process.
  """
  @callback children_specs(cache, opts) :: [Supervisor.Spec.spec]

  @doc """
  Retrieves a single object from Cache.

  See `Nebulex.Cache.get/2`.
  """
  @callback get(cache, key, opts) :: nil | return | no_return

  @doc """
  Stores a single object in the Cache.

  See `Nebulex.Cache.set/3`.
  """
  @callback set(cache, key, value, opts) :: return | no_return

  @doc """
  Deletes a single object from Cache.

  See `Nebulex.Cache.delete/2`.
  """
  @callback delete(cache, key, opts) :: return | no_return

  @doc """
  Returns whether the given `key` exists in Cache.

  See `Nebulex.Cache.has_key/2`.
  """
  @callback has_key?(cache, key) :: boolean

  @doc """
  Returns the cache size (total number of cached entries).

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
  Invokes `reducer` for each entry in the cache, passing the key, the return
  and the accumulator `acc` as arguments. `reducer`’s return value is stored
  in `acc`.

  Returns the accumulator.

  See `Nebulex.Cache.reduce/2`.
  """
  @callback reduce(cache, acc :: any, reducer, opts) :: any

  @doc """
  Returns a map with all cache entries.

  See `Nebulex.Cache.to_map/1`.
  """
  @callback to_map(cache, opts) :: map

  @doc """
  Returns and removes a single object from Cache if `key` exists,
  otherwise returns `nil`.

  See `Nebulex.Cache.pop/2`.
  """
  @callback pop(cache, key, opts) :: return | no_return

  @doc """
  Gets the value from `key` and updates it, all in one pass.

  See `Nebulex.Cache.get_and_update/3`.
  """
  @callback get_and_update(cache, key, (value -> {get, update} | :pop), opts) ::
            no_return | {get, update} when get: value, update: return

  @doc """
  Updates the cached `key` with the given function.

  See `Nebulex.Cache.update/4`.
  """
  @callback update(cache, key, initial :: value, (value -> value), opts) :: return | no_return

  @doc """
  Updates (increment or decrement) the counter mapped to the given `key`.

  See `Nebulex.Cache.update_counter/3`.
  """
  @callback update_counter(cache, key, incr :: integer, opts) :: integer | no_return
end
