defmodule Nebulex.Adapter.Entry do
  @moduledoc """
  Specifies the entry API required from adapters.

  This behaviour specifies all read/write key-based functions,
  the ones applied to a specific cache entry.
  """

  @typedoc "Proxy type to the adapter meta"
  @type adapter_meta :: Nebulex.Adapter.adapter_meta()

  @typedoc "Proxy type to the cache key"
  @type key :: Nebulex.Cache.key()

  @typedoc "Proxy type to the cache value"
  @type value :: Nebulex.Cache.value()

  @typedoc "Proxy type to the cache options"
  @type opts :: Nebulex.Cache.opts()

  @typedoc "Proxy type to the cache entries"
  @type entries :: Nebulex.Cache.entries()

  @typedoc "TTL for a cache entry"
  @type ttl :: timeout

  @typedoc "Write command type"
  @type on_write :: :put | :put_new | :replace

  @doc """
  Fetches the value for a specific `key` in the cache.

  This callback returns:

    * `{:ok, value}` - the cache contains the given `key`, then its `value`
      is returned.

    * `{:error, Nebulex.KeyError.t()}` - the cache doesn't contain `key`.

    * `{:error, reason}` - an error occurred while executing the command.
      The `reason` can be one of `t:Nebulex.Cache.error_reason/0`.

  See `c:Nebulex.Cache.fetch/2`.
  """
  @callback fetch(adapter_meta, key, opts) ::
              Nebulex.Cache.ok_error_tuple(value, Nebulex.Cache.fetch_error_reason())

  @doc """
  Returns a map in the shape of `{:ok, map}` with the key-value pairs of all
  specified `keys`. For every key that does not hold a value or does not exist,
  it is ignored and not added into the returned map.

  Returns `{:error, reason}` if there's any other error with the cache.
  The `reason` may be one of `t:Nebulex.Cache.error_reason/0`.

  See `c:Nebulex.Cache.get_all/2`.
  """
  @callback get_all(adapter_meta, [key], opts) :: Nebulex.Cache.ok_error_tuple(map)

  @doc """
  Puts the given `value` under `key` into the `cache`.

  The `ttl` argument sets the time-to-live for the stored entry. If it is not
  set, it means the entry hasn't a time-to-live, then it shouldn't expire.

  Returns `{:ok, true}` if the `value` with key `key` is successfully inserted,
  otherwise, `{:ok, false}` is returned.

  Returns `{:error, reason}` if an error occurs. The `reason` may be one of
  `t:Nebulex.Cache.error_reason/0`.

  ## OnWrite

  The `on_write` argument supports the following values:

    * `:put` - If the `key` already exists, it is overwritten. Any previous
      time-to-live associated with the key is discarded on successful `write`
      operation.

    * `:put_new` - It only stores the entry if the `key` does not already exist,
      otherwise, `{:ok, false}` is returned.

    * `:replace` - Alters the value stored under the given `key`, but only
      if the key already exists into the cache, otherwise, `{ok, false}` is
      returned.

  See `c:Nebulex.Cache.put/3`, `c:Nebulex.Cache.put_new/3`,
  `c:Nebulex.Cache.replace/3`.
  """
  @callback put(adapter_meta, key, value, ttl, on_write, opts) ::
              Nebulex.Cache.ok_error_tuple(boolean)

  @doc """
  Puts the given `entries` (key/value pairs) into the `cache`.

  The `ttl` argument sets the time-to-live for the stored entry. If it is not
  set, it means the entry hasn't a time-to-live, then it shouldn't expire.
  The given `ttl` is applied to all keys.

  Returns `{:ok, true}` if all the keys were inserted. If no key was inserted
  (at least one key already existed), `{:ok, false}` is returned.

  Returns `{:error, reason}` if an error occurs. The `reason` may be one of
  `t:Nebulex.Cache.error_reason/0`.

  ## OnWrite

  The `on_write` argument supports the following values:

    * `:put` - If the `key` already exists, it is overwritten. Any previous
      time-to-live associated with the key is discarded on successful `write`
      operation.

    * `:put_new` - It only stores the entry if the `key` does not already exist,
      otherwise, `{:ok, false}` is returned.

  Ideally, this operation should be atomic, so all given keys are set at once.
  But it depends purely on the adapter's implementation and the backend used
  internally by the adapter. Hence, it is recommended to checkout the
  adapter's documentation.

  See `c:Nebulex.Cache.put_all/2`.
  """
  @callback put_all(adapter_meta, entries, ttl, on_write, opts) ::
              Nebulex.Cache.ok_error_tuple(boolean)

  @doc """
  Deletes a single entry from cache.

  Returns `{:error, reason}` if an error occurs. The `reason` may be one of
  `t:Nebulex.Cache.error_reason/0`.

  See `c:Nebulex.Cache.delete/2`.
  """
  @callback delete(adapter_meta, key, opts) :: :ok | Nebulex.Cache.error()

  @doc """
  Removes and returns the value associated with `key` in the cache.

  This function returns:

    * `{:ok, value}` - the cache contains the given `key`, then its `value`
      is removed and returned.

    * `{:error, Nebulex.KeyError.t()}` - the cache doesn't contain `key`.

    * `{:error, reason}` - an error occurred while executing the command.
      The `reason` can be one of `t:Nebulex.Cache.error_reason/0`.

  See `c:Nebulex.Cache.take/2`.
  """
  @callback take(adapter_meta, key, opts) ::
              Nebulex.Cache.ok_error_tuple(value, Nebulex.Cache.fetch_error_reason())

  @doc """
  Updates the counter mapped to the given `key`.

  If `amount` > 0, the counter is incremented by the given `amount`.
  If `amount` < 0, the counter is decremented by the given `amount`.
  If `amount` == 0, the counter is not updated.

  Returns `{:error, reason}` if an error occurs. The `reason` may be one of
  `t:Nebulex.Cache.error_reason/0`.

  See `c:Nebulex.Cache.incr/3`.
  See `c:Nebulex.Cache.decr/3`.
  """
  @callback update_counter(adapter_meta, key, amount, ttl, default, opts) ::
              Nebulex.Cache.ok_error_tuple(integer)
            when amount: integer, default: integer

  @doc """
  Determines if the cache contains an entry for the specified `key`.

  More formally, returns `{:ok, true}` if the cache contains the given `key`.
  If the cache doesn't contain `key`, `{:ok, :false}` is returned.

  Returns `{:error, reason}` if an error occurs. The `reason` may be one of
  `t:Nebulex.Cache.error_reason/0`.

  See `c:Nebulex.Cache.exists?/1`.
  """
  @callback exists?(adapter_meta, key) :: Nebulex.Cache.ok_error_tuple(boolean)

  @doc """
  Returns the remaining time-to-live for the given `key`.

  This function returns:

    * `{:ok, ttl}` - the cache contains the given `key`,
      then its remaining `ttl` is returned.

    * `{:error, Nebulex.KeyError.t()}` - the cache doesn't contain `key`.

    * `{:error, reason}` - an error occurred while executing the command.
      The `reason` can be one of `t:Nebulex.Cache.error_reason/0`.

  See `c:Nebulex.Cache.ttl/1`.
  """
  @callback ttl(adapter_meta, key) ::
              Nebulex.Cache.ok_error_tuple(value, Nebulex.Cache.fetch_error_reason())

  @doc """
  Returns `{:ok, true}` if the given `key` exists and the new `ttl` was
  successfully updated, otherwise, `{:ok, false}` is returned.

  Returns `{:error, reason}` if an error occurs. The `reason` may be one of
  `t:Nebulex.Cache.error_reason/0`.

  See `c:Nebulex.Cache.expire/2`.
  """
  @callback expire(adapter_meta, key, ttl) :: Nebulex.Cache.ok_error_tuple(boolean)

  @doc """
  Returns `{:ok, true}` if the given `key` exists and the last access time was
  successfully updated, otherwise, `{:ok, false}` is returned.

  Returns `{:error, reason}` if an error occurs. The `reason` may be one of
  `t:Nebulex.Cache.error_reason/0`.

  See `c:Nebulex.Cache.touch/1`.
  """
  @callback touch(adapter_meta, key) :: Nebulex.Cache.ok_error_tuple(boolean)
end
