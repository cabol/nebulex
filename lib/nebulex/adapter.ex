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

  See `Nebulex.Cache.get/2`.
  """
  @callback get(cache, key, opts) :: object | nil

  @doc """
  Returns a map with the objects for all specified keys. For every key that
  does not hold a value or does not exist, that key is simply ignored.
  Because of this, the operation never fails.

  See `Nebulex.Cache.get_many/2`.
  """
  @callback get_many(cache, [key], opts) :: map

  @doc """
  Sets the given `object` under `key` into the cache.

  ## Options

  Besides the "Shared options" section in `Nebulex.Cache` documentation,
  it accepts:

    * `:action` - It may be one of `:add`, `:replace`, `:set` (the default).
      See the "Actions" section for more information.

  ## Actions

  The `:action` option supports the following values:

    * `:add` - Only set the `key` if it does not already exist. If it does,
      `nil` is returned.

    * `:replace` - Alters the entry stored under `key` into the cache, but
      only if the entry already exists into the cache. All attributes of the
      cached object can be updated, either the value if `value` is different
      than `nil`, or the expiry time if option `:ttl` is set in `opts`. The
      version is always regenerated.

    * `:set` - Set `key` to hold the given `object`. If key already holds an
      object, it is overwritten. Any previous `:ttl` (time to live) associated
      with the key is discarded on successful `set` operation. This action is
      the default.

  See `Nebulex.Cache.set/3`, `Nebulex.Cache.add/3`, `Nebulex.Cache.replace/3`.
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

  See `Nebulex.Cache.set_many/2`.
  """
  @callback set_many(cache, [object], opts) :: :ok | {:error, failed_keys :: [key]}

  @doc """
  Deletes a single object from cache.

  See `Nebulex.Cache.delete/2`.
  """
  @callback delete(cache, key, opts) :: :ok

  @doc """
  Returns and removes the object with key `key` in the cache.

  See `Nebulex.Cache.take/2`.
  """
  @callback take(cache, key, opts) :: object | nil

  @doc """
  Returns whether the given `key` exists in cache.

  See `Nebulex.Cache.has_key/2`.
  """
  @callback has_key?(cache, key) :: boolean

  @doc """
  Updates (increment or decrement) the counter mapped to the given `key`.

  See `Nebulex.Cache.update_counter/3`.
  """
  @callback update_counter(cache, key, incr :: integer, opts) :: integer

  @doc """
  Returns the total number of cached entries.

  See `Nebulex.Cache.size/0`.
  """
  @callback size(cache) :: integer

  @doc """
  Flushes the cache.

  See `Nebulex.Cache.flush/0`.
  """
  @callback flush(cache) :: :ok
end
