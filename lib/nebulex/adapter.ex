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
  @callback children(cache, opts) :: [Supervisor.Spec.spec]

  @doc """
  Retrieves a single object from Cache.

  See callback `get/2` in module `Nebulex.Cache`.
  """
  @callback get(cache, key, opts) :: nil | return | no_return

  @doc """
  Stores a single object in the Cache.

  See callback `set/3` in module `Nebulex.Cache`.
  """
  @callback set(cache, key, value, opts) :: return | no_return

  @doc """
  Deletes a single object from Cache.

  See callback `delete/2` in module `Nebulex.Cache`.
  """
  @callback delete(cache, key, opts) :: return | no_return

  @doc """
  Returns whether the given `key` exists in Cache.

  See callback `has_key/2` in module `Nebulex.Cache`.
  """
  @callback has_key?(cache, key) :: boolean

  @doc """
  Returns the cache size (total number of cached entries).

  See callback `size/0` in module `Nebulex.Cache`.
  """
  @callback size(cache) :: integer

  @doc """
  Returns all cached keys.

  See callback `keys/0` in module `Nebulex.Cache`.
  """
  @callback keys(cache) :: [key]

  @doc """
  Invokes `reducer` for each entry in the cache, passing the key, the return
  and the accumulator `acc` as arguments. `reducer`’s return value is stored
  in `acc`.

  Returns the accumulator.

  See callback `reduce/2` in module `Nebulex.Cache`.
  """
  @callback reduce(cache, acc :: any, reducer, opts) :: any

  @doc """
  Returns a map with all cache entries.

  See callback `to_map/1` in module `Nebulex.Cache`.
  """
  @callback to_map(cache, opts) :: map

  @doc """
  Returns and removes a single object from Cache if `key` exists,
  otherwise returns `nil`.

  See callback `pop/2` in module `Nebulex.Cache`.
  """
  @callback pop(cache, key, opts) :: return | no_return

  @doc """
  Gets the value from `key` and updates it, all in one pass.

  See callback `get_and_update/3` in module `Nebulex.Cache`.
  """
  @callback get_and_update(cache, key, (value -> {get, update} | :pop), opts) ::
            no_return | {get, update} when get: value, update: value

  @doc """
  Updates the cached `key` with the given function.

  See callback `update/4` in module `Nebulex.Cache`.
  """
  @callback update(cache, key, initial :: value, (value -> value), opts) :: value | no_return

  @doc """
  Sets a lock on the caller Cache and `key`. If this succeeds, `fun` is
  evaluated and the result is returned.

  See callback `transaction/2` in module `Nebulex.Cache`.
  """
  @callback transaction(cache, key, (... -> any)) :: any
end
