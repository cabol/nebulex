defmodule Nebulex.Adapter.KV do
  @moduledoc """
  Specifies the adapter Key/Value API.

  This behaviour specifies all read/write key-based functions,
  applied to a specific cache key.
  """

  @typedoc "Proxy type to the adapter meta"
  @type adapter_meta() :: Nebulex.Adapter.adapter_meta()

  @typedoc "Proxy type to the cache key"
  @type key() :: Nebulex.Cache.key()

  @typedoc "Proxy type to the cache value"
  @type value() :: Nebulex.Cache.value()

  @typedoc "Proxy type to the cache options"
  @type opts() :: Nebulex.Cache.opts()

  @typedoc "Proxy type to the cache entries"
  @type entries() :: Nebulex.Cache.entries()

  @typedoc "TTL for a cache entry"
  @type ttl() :: timeout()

  @typedoc "Write command type"
  @type on_write() :: :put | :put_new | :replace

  @typedoc "Keep TTL flag"
  @type keep_ttl() :: boolean()

  @doc """
  Fetches the value for a specific `key` in the cache.

  If the cache contains the given `key`, then its value is returned
  in the shape of `{:ok, value}`.

  If there's an error with executing the command, `{:error, reason}`
  is returned. `reason` is the cause of the error and can be
  `Nebulex.KeyError` if the cache does not contain `key`,
  `Nebulex.Error` otherwise.

  See `c:Nebulex.Cache.fetch/2`.
  """
  @callback fetch(adapter_meta(), key(), opts()) ::
              Nebulex.Cache.ok_error_tuple(value, Nebulex.Cache.fetch_error_reason())

  @doc """
  Puts the given `value` under `key` into the `cache`.

  Returns `{:ok, true}` if the `value` with key `key` is successfully inserted.
  Otherwise, `{:ok, false}` is returned.

  If there's an error with executing the command, `{:error, reason}`
  is returned, where `reason` is the cause of the error.

  The `ttl` argument defines the time-to-live for the stored entry. If it is not
  set, it means the entry doesn't have a time-to-live, so it shouldn't expire.

  The `keep_ttl` argument tells whether to retain the time to live associated
  with the key. Otherwise, the TTL is always overwritten.

  ## `on_write` argument

  The `on_write` argument supports the following values:

    * `:put` - If the `key` already exists, it is overwritten. Any previous
      time-to-live associated with the key is discarded on a successful `write`
      operation.

    * `:put_new` - It only stores the entry if the `key` does not exist.
      Otherwise, `{:ok, false}` is returned.

    * `:replace` - Alters the value stored under the given `key`, but only
      if the key already exists in the cache. Otherwise, `{ok, false}` is
      returned.

  See `c:Nebulex.Cache.put/3`, `c:Nebulex.Cache.put_new/3`,
  `c:Nebulex.Cache.replace/3`.
  """
  @callback put(adapter_meta(), key(), value(), on_write(), ttl(), keep_ttl(), opts()) ::
              Nebulex.Cache.ok_error_tuple(boolean())

  @doc """
  Puts the given `entries` (key/value pairs) into the `cache` atomically
  or fail otherwise.

  If there's an error with executing the command, `{:error, reason}`
  is returned, where `reason` is the cause of the error.

  The `ttl` argument works the same as `c:put/7` but applies to all keys.

  ## `on_write` argument

  The `on_write` argument supports the following values:

    * `:put` - If the `key` already exists, it is overwritten. Any previous
      time-to-live associated with the key is discarded on a successful `write`
      operation.

    * `:put_new` - Insert all entries only if none exist in the cache, and it
      returns `{:ok, true}` . Otherwise, `{:ok, false}` is returned.

  See `c:Nebulex.Cache.put_all/2` and `c:Nebulex.Cache.put_new_all/2`.
  """
  @callback put_all(adapter_meta(), entries(), on_write(), ttl(), opts()) ::
              Nebulex.Cache.ok_error_tuple(boolean())

  @doc """
  Deletes a single entry from cache.

  If there's an error with executing the command, `{:error, reason}`
  is returned, where `reason` is the cause of the error.

  See `c:Nebulex.Cache.delete/2`.
  """
  @callback delete(adapter_meta(), key(), opts()) :: :ok | Nebulex.Cache.error_tuple()

  @doc """
  Removes and returns the value associated with `key` in the cache.

  If `key` is present in the cache, its value is removed and returned as
  `{:ok, value}`.

  If there's an error with executing the command, `{:error, reason}`
  is returned. `reason` is the cause of the error and can be
  `Nebulex.KeyError` if the cache does not contain `key` or
  `Nebulex.Error` otherwise.

  See `c:Nebulex.Cache.take/2`.
  """
  @callback take(adapter_meta(), key(), opts()) ::
              Nebulex.Cache.ok_error_tuple(value(), Nebulex.Cache.fetch_error_reason())

  @doc """
  Updates the counter mapped to the given `key`.

  If `amount` > 0, the counter is incremented by the given `amount`.
  If `amount` < 0, the counter is decremented by the given `amount`.
  If `amount` == 0, the counter is not updated.

  If there's an error with executing the command, `{:error, reason}`
  is returned, where `reason` is the cause of the error.

  The `ttl` is set when the key doesn't exist. Otherwise, only the counter is
  updated keeping the TTL when the counter was updated for the first time.

  See `c:Nebulex.Cache.incr/3`.
  See `c:Nebulex.Cache.decr/3`.
  """
  @callback update_counter(adapter_meta(), key(), amount, default, ttl(), opts()) ::
              Nebulex.Cache.ok_error_tuple(integer())
            when amount: integer(), default: integer()

  @doc """
  Determines if the cache contains an entry for the specified `key`.

  More formally, it returns `{:ok, true}` if the cache contains the given `key`.
  If the cache doesn't contain `key`, `{:ok, false}` is returned.

  If there's an error with executing the command, `{:error, reason}`
  is returned, where `reason` is the cause of the error.

  See `c:Nebulex.Cache.has_key?/2`.
  """
  @callback has_key?(adapter_meta(), key(), opts()) :: Nebulex.Cache.ok_error_tuple(boolean())

  @doc """
  Returns the remaining time-to-live for the given `key`.

  If `key` is present in the cache, then its remaining TTL is returned
  in the shape of `{:ok, ttl}`.

  If there's an error with executing the command, `{:error, reason}`
  is returned. `reason` is the cause of the error and can be
  `Nebulex.KeyError` if the cache does not contain `key`,
  `Nebulex.Error` otherwise.

  See `c:Nebulex.Cache.ttl/2`.
  """
  @callback ttl(adapter_meta(), key(), opts()) ::
              Nebulex.Cache.ok_error_tuple(value(), Nebulex.Cache.fetch_error_reason())

  @doc """
  Returns `{:ok, true}` if the given `key` exists and the new `ttl` is
  successfully updated; otherwise, `{:ok, false}` is returned.

  If there's an error with executing the command, `{:error, reason}`
  is returned; where `reason` is the cause of the error.

  See `c:Nebulex.Cache.expire/3`.
  """
  @callback expire(adapter_meta(), key(), ttl(), opts()) :: Nebulex.Cache.ok_error_tuple(boolean())

  @doc """
  Returns `{:ok, true}` if the given `key` exists and the last access time is
  successfully updated; otherwise, `{:ok, false}` is returned.

  If there's an error with executing the command, `{:error, reason}`
  is returned, where `reason` is the cause of the error.

  See `c:Nebulex.Cache.touch/2`.
  """
  @callback touch(adapter_meta(), key(), opts()) :: Nebulex.Cache.ok_error_tuple(boolean())
end
