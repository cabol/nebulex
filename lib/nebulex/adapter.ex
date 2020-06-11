defmodule Nebulex.Adapter do
  @moduledoc """
  This module specifies the adapter API that a Cache adapter is required to
  implement.
  """

  @type t :: module

  @typedoc """
  The metadata returned by the adapter `c:init/1`.

  It must be a map and Nebulex itself will always inject two keys into the meta:

    * `:cache` - The cache module.
    * `:name` - The nase of the cache.
    * :pid` - The PID returned by the child spec returned in `c:init/1`
  """
  @type adapter_meta :: map

  @type cache :: Nebulex.Cache.t()
  @type key :: Nebulex.Cache.key()
  @type value :: Nebulex.Cache.value()
  @type entry :: Nebulex.Entry.t()
  @type opts :: Nebulex.Cache.opts()
  @type entries :: Nebulex.Cache.entries()
  @type ttl :: timeout
  @type on_write :: :put | :put_new | :replace
  @type child_spec :: :supervisor.child_spec() | {module(), term()} | module() | nil

  @doc """
  The callback invoked in case the adapter needs to inject code.
  """
  @macrocallback __before_compile__(env :: Macro.Env.t()) :: Macro.t()

  @doc """
  Initializes the adapter supervision tree by returning the children.
  """
  @callback init(opts) :: {:ok, child_spec, adapter_meta}

  @doc """
  Gets the value for a specific `key` in `cache`.

  See `c:Nebulex.Cache.get/2`.
  """
  @callback get(adapter_meta, key, opts) :: value

  @doc """
  Gets a collection of entries from the Cache, returning them as `Map.t()` of
  the values associated with the set of keys requested.

  For every key that does not hold a value or does not exist, that key is
  simply ignored. Because of this, the operation never fails.

  See `c:Nebulex.Cache.get_all/2`.
  """
  @callback get_all(adapter_meta, [key], opts) :: map

  @doc """
  Puts the given `value` under `key` into the `cache`.

  Returns `true` if the `value` with key `key` is successfully inserted;
  otherwise `false` is returned.

  The `ttl` argument sets the time-to-live for the stored entry. If it is not
  set, it means the entry hasn't a time-to-live, then it shouldn't expire.

  ## OnWrite

  The `on_write` argument supports the following values:

    * `:put` - If the `key` already exists, it is overwritten. Any previous
      time-to-live associated with the key is discarded on successful `write`
      operation.

    * `:put_new` - It only stores the entry if the `key` does not already exist,
      otherwise, `false` is returned.

    * `:replace` - Alters the value stored under the given `key`, but only
      if the key already exists into the cache, otherwise, `false` is
      returned.

  See `c:Nebulex.Cache.put/3`, `c:Nebulex.Cache.put_new/3`, `c:Nebulex.Cache.replace/3`.
  """
  @callback put(adapter_meta, key, value, ttl, on_write, opts) :: boolean

  @doc """
  Puts the given `entries` (key/value pairs) into the `cache`.

  Returns `true` if all the keys were inserted. If no key was inserted
  (at least one key already existed), `false` is returned.

  The `ttl` argument sets the time-to-live for the stored entry. If it is not
  set, it means the entry hasn't a time-to-live, then it shouldn't expire.
  The given `ttl` is applied to all keys.

  ## OnWrite

  The `on_write` argument supports the following values:

    * `:put` - If the `key` already exists, it is overwritten. Any previous
      time-to-live associated with the key is discarded on successful `write`
      operation.

    * `:put_new` - It only stores the entry if the `key` does not already exist,
      otherwise, `false` is returned.

  Ideally, this operation should be atomic, so all given keys are set at once.
  But it depends purely on the adapter's implementation and the backend used
  internally by the adapter. Hence, it is recommended to checkout the
  adapter's documentation.

  See `c:Nebulex.Cache.put_all/2`.
  """
  @callback put_all(adapter_meta, entries, ttl, on_write, opts) :: boolean

  @doc """
  Deletes a single entry from cache.

  See `c:Nebulex.Cache.delete/2`.
  """
  @callback delete(adapter_meta, key, opts) :: :ok

  @doc """
  Returns and removes the entry with key `key` in the cache.

  See `c:Nebulex.Cache.take/2`.
  """
  @callback take(adapter_meta, key, opts) :: value

  @doc """
  Increments or decrements the counter mapped to the given `key`.

  See `c:Nebulex.Cache.incr/3`.
  """
  @callback incr(adapter_meta, key, incr :: integer, ttl, opts) :: integer

  @doc """
  Returns whether the given `key` exists in cache.

  See `c:Nebulex.Cache.has_key?/1`.
  """
  @callback has_key?(adapter_meta, key) :: boolean

  @doc """
  Returns the TTL (time-to-live) for the given `key`. If the `key` doen not
  exist, then `nil` is returned.

  See `c:Nebulex.Cache.ttl/1`.
  """
  @callback ttl(adapter_meta, key) :: ttl | nil

  @doc """
  Returns `true` if the given `key` exists and the new `ttl` was successfully
  updated, otherwise, `false` is returned.

  See `c:Nebulex.Cache.expire/2`.
  """
  @callback expire(adapter_meta, key, ttl) :: boolean

  @doc """
  Returns `true` if the given `key` exists and the last access time was
  successfully updated, otherwise, `false` is returned.

  See `c:Nebulex.Cache.touch/1`.
  """
  @callback touch(adapter_meta, key) :: boolean

  @doc """
  Returns the total number of cached entries.

  See `c:Nebulex.Cache.size/0`.
  """
  @callback size(adapter_meta) :: integer

  @doc """
  Flushes the cache and returns the number of evicted keys.

  See `c:Nebulex.Cache.flush/0`.
  """
  @callback flush(adapter_meta) :: integer
end
