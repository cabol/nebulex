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

  @doc """
  The callback invoked in case the adapter needs to inject code.
  """
  @macrocallback __before_compile__(env :: Macro.Env.t()) :: Macro.t()

  @doc """
  Initializes the adapter supervision tree by returning the children
  """
  @callback init(opts) :: {:ok, [:supervisor.child_spec() | {module(), term()} | module()]}

  @doc """
  Retrieves a single object from cache.

  See `c:Nebulex.Cache.get/2`.
  """
  @callback get(cache, key, opts) :: object | nil

  @doc """
  Returns a map with the objects for all specified keys. For every key that
  does not hold a value or does not exist, that key is simply ignored.
  Because of this, the operation never fails.

  See `c:Nebulex.Cache.get_many/2`.
  """
  @callback get_many(cache, [key], opts) :: map

  @doc """
  Sets the given `object` under `key` into the cache.

  If the object already exists, it is overwritten. Any previous time to live
  associated with the key is discarded on successful `set` operation.

  Returns `true` if an object with key `key` is found and successfully inserted,
  otherwise `false`.

  ## Options

  Besides the "Shared options" section in `Nebulex.Cache` documentation,
  it accepts:

    * `:action` - It may be one of `:add`, `:replace`, `:set` (the default).
      See the "Actions" section for more information.

  ## Actions

  The `:action` option supports the following values:

    * `:add` - Only set the `key` if it does not already exist. If it does,
      `false` is returned.

    * `:replace` - Alters the object stored under `key`, but only if the object
      already exists into the cache.

    * `:set` - Set `key` to hold the given `object` (default).

  See `c:Nebulex.Cache.set/3`, `c:Nebulex.Cache.add/3`, `c:Nebulex.Cache.replace/3`.
  """
  @callback set(cache, object, opts) :: boolean

  @doc """
  Sets the given `objects`, replacing existing ones, just as regular `set`.

  Returns `:ok` if the all objects were successfully set, otherwise
  `{:error, failed_keys}`, where `failed_keys` contains the keys that
  could not be set.

  Ideally, this operation should be atomic, so all given keys are set at once.
  But it depends purely on the adapter's implementation and the backend used
  internally by the adapter. Hence, it is recommended to checkout the
  adapter's documentation.

  See `c:Nebulex.Cache.set_many/2`.
  """
  @callback set_many(cache, [object], opts) :: :ok | {:error, failed_keys :: [key]}

  @doc """
  Deletes a single object from cache.

  See `c:Nebulex.Cache.delete/2`.
  """
  @callback delete(cache, key, opts) :: :ok

  @doc """
  Returns and removes the object with key `key` in the cache.

  See `c:Nebulex.Cache.take/2`.
  """
  @callback take(cache, key, opts) :: object | nil

  @doc """
  Returns whether the given `key` exists in cache.

  See `c:Nebulex.Cache.has_key?/1`.
  """
  @callback has_key?(cache, key) :: boolean

  @doc """
  Returns the information associated with `attr` for the given `key`,
  or returns `nil` if `key` doesn't exist.

  See `c:Nebulex.Cache.object_info/2`.
  """
  @callback object_info(cache, key, attr :: :ttl | :version) :: term | nil

  @doc """
  Returns the expiry timestamp for the given `key`, if the timeout `ttl`
  (in seconds) is successfully updated.

  If `key` doesn't exist, `nil` is returned.

  See `c:Nebulex.Cache.expire/2`.
  """
  @callback expire(cache, key, ttl :: timeout) :: timeout | nil

  @doc """
  Updates (increment or decrement) the counter mapped to the given `key`.

  See `c:Nebulex.Cache.update_counter/3`.
  """
  @callback update_counter(cache, key, incr :: integer, opts) :: integer

  @doc """
  Returns the total number of cached entries.

  See `c:Nebulex.Cache.size/0`.
  """
  @callback size(cache) :: integer

  @doc """
  Flushes the cache.

  See `c:Nebulex.Cache.flush/0`.
  """
  @callback flush(cache) :: :ok
end
