defmodule Nebulex.Cache do
  @moduledoc ~S"""
  Cache's main interface; defines the cache abstraction layer which is
  highly inspired by [Ecto](https://github.com/elixir-ecto/ecto).

  A Cache maps to an underlying implementation, controlled by the
  adapter. For example, Nebulex ships with a default adapter that
  implements a local generational cache.

  When used, the Cache expects the `:otp_app` and `:adapter` as options.
  The `:otp_app` should point to an OTP application that has the Cache
  configuration. For example, the Cache:

      defmodule MyCache do
        use Nebulex.Cache,
          otp_app: :my_app,
          adapter: Nebulex.Adapters.Local
      end

  Could be configured with:

      config :my_app, MyCache,
        stats: true,
        backend: :shards,
        gc_interval: 86_400_000, #=> 1 day
        max_size: 200_000,
        gc_cleanup_min_timeout: 10_000,
        gc_cleanup_max_timeout: 900_000,
        partitions: System.schedulers_online()

  Most of the configuration that goes into the `config` is specific
  to the adapter. For this particular example, you can check
  [`Nebulex.Adapters.Local`](https://hexdocs.pm/nebulex/Nebulex.Adapters.Local.html)
  for more information. In spite of this, the following configuration values
  are shared across all adapters:

    * `:name`- The name of the Cache supervisor process (Optional). If it is
      not passed within the options, the name of the cache module will be used
      as the name by default.

    * `:stats` - The stats are supposed to be handled by the adapters, hence,
      it is recommended to check the adapters' documentation for supported
      stats, config, and so on. Nevertheless, Nebulex built-in adapters
      provide support for stats by setting the `:stats` option to `true`
      (Defaults to `false`). You can get the stats info by calling
      `Nebulex.Cache.Stats.info(cache_or_name)` at any time. For more
      information, See `Nebulex.Cache.Stats`.

  **NOTE:** It is highly recommendable to check the adapters' documentation.
  """

  @type t :: module

  @typedoc "Cache entry key"
  @type key :: any

  @typedoc "Cache entry value"
  @type value :: any

  @typedoc "Cache entries"
  @type entries :: map | [{key, value}]

  @typedoc "Cache action options"
  @type opts :: Keyword.t()

  @doc false
  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      @behaviour Nebulex.Cache

      alias Nebulex.Hook
      alias Nebulex.Cache.{Entry, Persistence, Queryable, Stats, Transaction}

      {otp_app, adapter, behaviours} = Nebulex.Cache.Supervisor.compile_config(opts)

      @otp_app otp_app
      @adapter adapter
      @opts opts
      @default_dynamic_cache opts[:default_dynamic_cache] || __MODULE__
      @before_compile adapter

      ## Config and metadata

      @impl true
      def config do
        {:ok, config} = Nebulex.Cache.Supervisor.runtime_config(__MODULE__, @otp_app, [])
        config
      end

      @impl true
      def __adapter__, do: @adapter

      ## Process lifecycle

      @doc false
      def child_spec(opts) do
        %{
          id: __MODULE__,
          start: {__MODULE__, :start_link, [opts]},
          type: :supervisor
        }
      end

      @impl true
      def start_link(opts \\ []) do
        Nebulex.Cache.Supervisor.start_link(__MODULE__, @otp_app, @adapter, opts)
      end

      @impl true
      def stop(timeout \\ 5000) do
        Supervisor.stop(get_dynamic_cache(), :normal, timeout)
      end

      @compile {:inline, get_dynamic_cache: 0}

      @impl true
      def get_dynamic_cache do
        Process.get({__MODULE__, :dynamic_cache}, @default_dynamic_cache)
      end

      @impl true
      def put_dynamic_cache(dynamic) when is_atom(dynamic) or is_pid(dynamic) do
        Process.put({__MODULE__, :dynamic_cache}, dynamic) || @default_dynamic_cache
      end

      ## Entries

      @impl true
      def get(key, opts \\ []) do
        Entry.get(get_dynamic_cache(), key, opts)
      end

      @impl true
      def get!(key, opts \\ []) do
        Entry.get!(get_dynamic_cache(), key, opts)
      end

      @impl true
      def get_all(keys, opts \\ []) do
        Entry.get_all(get_dynamic_cache(), keys, opts)
      end

      @impl true
      def put(key, value, opts \\ []) do
        Entry.put(get_dynamic_cache(), key, value, opts)
      end

      @impl true
      def put_all(entries, opts \\ []) do
        Entry.put_all(get_dynamic_cache(), entries, opts)
      end

      @impl true
      def put_new(key, value, opts \\ []) do
        Entry.put_new(get_dynamic_cache(), key, value, opts)
      end

      @impl true
      def put_new!(key, value, opts \\ []) do
        Entry.put_new!(get_dynamic_cache(), key, value, opts)
      end

      @impl true
      def put_new_all(entries, opts \\ []) do
        Entry.put_new_all(get_dynamic_cache(), entries, opts)
      end

      @impl true
      def replace(key, value, opts \\ []) do
        Entry.replace(get_dynamic_cache(), key, value, opts)
      end

      @impl true
      def replace!(key, value, opts \\ []) do
        Entry.replace!(get_dynamic_cache(), key, value, opts)
      end

      @impl true
      def delete(key, opts \\ []) do
        Entry.delete(get_dynamic_cache(), key, opts)
      end

      @impl true
      def take(key, opts \\ []) do
        Entry.take(get_dynamic_cache(), key, opts)
      end

      @impl true
      def take!(key, opts \\ []) do
        Entry.take!(get_dynamic_cache(), key, opts)
      end

      @impl true
      def has_key?(key) do
        Entry.has_key?(get_dynamic_cache(), key)
      end

      @impl true
      def get_and_update(key, fun, opts \\ []) do
        Entry.get_and_update(get_dynamic_cache(), key, fun, opts)
      end

      @impl true
      def update(key, initial, fun, opts \\ []) do
        Entry.update(get_dynamic_cache(), key, initial, fun, opts)
      end

      @impl true
      def incr(key, incr \\ 1, opts \\ []) do
        Entry.incr(get_dynamic_cache(), key, incr, opts)
      end

      @impl true
      def ttl(key) do
        Entry.ttl(get_dynamic_cache(), key)
      end

      @impl true
      def expire(key, ttl) do
        Entry.expire(get_dynamic_cache(), key, ttl)
      end

      @impl true
      def touch(key) do
        Entry.touch(get_dynamic_cache(), key)
      end

      @impl true
      def size do
        Entry.size(get_dynamic_cache())
      end

      @impl true
      def flush do
        Entry.flush(get_dynamic_cache())
      end

      ## Queryable

      if Nebulex.Adapter.Queryable in behaviours do
        @impl true
        def all(query \\ nil, opts \\ []) do
          Queryable.all(get_dynamic_cache(), query, opts)
        end

        @impl true
        def stream(query \\ nil, opts \\ []) do
          Queryable.stream(get_dynamic_cache(), query, opts)
        end
      end

      ## Persistence

      if Nebulex.Adapter.Persistence in behaviours do
        @impl true
        def dump(path, opts \\ []) do
          Persistence.dump(get_dynamic_cache(), path, opts)
        end

        @impl true
        def load(path, opts \\ []) do
          Persistence.load(get_dynamic_cache(), path, opts)
        end
      end

      ## Transactions

      if Nebulex.Adapter.Transaction in behaviours do
        @impl true
        def transaction(opts \\ [], fun) do
          Transaction.transaction(get_dynamic_cache(), opts, fun)
        end

        @impl true
        def in_transaction? do
          Transaction.in_transaction?(get_dynamic_cache())
        end
      end
    end
  end

  ## User callbacks

  @optional_callbacks init: 1

  @doc """
  A callback executed when the cache starts or when configuration is read.
  """
  @callback init(config :: Keyword.t()) :: {:ok, Keyword.t()} | :ignore

  ## Nebulex.Adapter

  @doc """
  Returns the adapter tied to the cache.
  """
  @callback __adapter__ :: Nebulex.Adapter.t()

  @doc """
  Returns the adapter configuration stored in the `:otp_app` environment.

  If the `c:init/2` callback is implemented in the cache, it will be invoked.
  """
  @callback config() :: Keyword.t()

  @doc """
  Starts a supervision and return `{:ok, pid}` or just `:ok` if nothing
  needs to be done.

  Returns `{:error, {:already_started, pid}}` if the cache is already
  started or `{:error, term}` in case anything else goes wrong.

  ## Options

  See the configuration in the moduledoc for options shared between adapters,
  for adapter-specific configuration see the adapter's documentation.
  """
  @callback start_link(opts) ::
              {:ok, pid}
              | {:error, {:already_started, pid}}
              | {:error, term}

  @doc """
  Shuts down the cache.
  """
  @callback stop(timeout) :: :ok

  @doc """
  Returns the atom name or pid of the current cache
  (based on Ecto dynamic repo).

  See also `c:put_dynamic_cache/1`.
  """
  @callback get_dynamic_cache() :: atom() | pid()

  @doc """
  Sets the dynamic cache to be used in further commands
  (based on Ecto dynamic repo).

  There might be cases where we want to have different cache instances but
  accessing them through the same cache module. By default, when you call
  `MyApp.Cache.start_link/1`, it will start a cache with the name
  `MyApp.Cache`. But it is also possible to start multiple caches by using
  a different name for each of them:

      MyApp.Cache.start_link(name: :cache1)
      MyApp.Cache.start_link(name: :cache2, backend: :shards)

  However, once the cache is started, it is not possible to interact directly
  with it, since all operations through `MyApp.Cache` are sent by default to
  the cache named `MyApp.Cache`. But you can change the default cache at
  compile-time:

      use Nebulex.Cache, default_dynamic_cache: :cache_name

  Or anytime at runtime by calling `put_dynamic_cache/1`:

      MyApp.Cache.put_dynamic_cache(:another_cache_name)

  From this moment on, all future commands performed by the current process
  will run on `:another_cache_name`.
  """
  @callback put_dynamic_cache(atom() | pid()) :: atom() | pid()

  @doc """
  Gets a value from Cache where the key matches the given `key`.

  Returns `nil` if no result was found.

  ## Options

  See the "Shared options" section at the module documentation for more options.

  ## Example

      iex> MyCache.put("foo", "bar")
      :ok

      iex>  MyCache.get("foo")
      "bar"

      iex> MyCache.get(:non_existent_key)
      nil
  """
  @callback get(key, opts) :: value

  @doc """
  Similar to `get/2` but raises `KeyError` if `key` is not found.

  ## Options

  See the "Shared options" section at the module documentation for more options.

  ## Example

      MyCache.get!(:a)
  """
  @callback get!(key, opts) :: value

  @doc """
  Returns a `map` with all the key-value pairs in the Cache where the key
  is in `keys`.

  If `keys` contains keys that are not in the Cache, they're simply ignored.

  ## Options

  See the "Shared options" section at the module documentation for more options.

  ## Example
      iex> MyCache.put_all([a: 1, c: 3])
      :ok

      iex> MyCache.get_all([:a, :b, :c])
      %{a: 1, c: 3}
  """
  @callback get_all(keys :: [key], opts) :: map

  @doc """
  Puts the given `value` under `key` into the Cache.

  If `key` already holds an entry, it is overwritten. Any previous
  time to live associated with the key is discarded on successful
  `put` operation.

  ## Options

    * `:ttl` - Time To Live (TTL) or expiration time in milliseconds for a key
      (default: `:infinity`).

  See the "Shared options" section at the module documentation for more options.

  ## Example

      iex> import Nebulex.Time

      iex> MyCache.put("foo", "bar")
      :ok

      # if the value is nil, then it is not stored (operation is skipped)
      iex> MyCache.put("foo", nil)
      :ok

      # put key with time-to-live
      iex> MyCache.put("foo", "bar", ttl: 10_000)
      :ok

      # using Nebulex.Time
      iex> MyCache.put("foo", "bar", ttl: expiry_time(10))
      iex> MyCache.put("foo", "bar", ttl: expiry_time(10, :minute))
      iex> MyCache.put("foo", "bar", ttl: expiry_time(1, :hour))
  """
  @callback put(key, value, opts) :: :ok

  @doc """
  Puts the given `entries` (key/value pairs) into the Cache. It replaces
  existing values with new values (just as regular `put`).

  ## Options

    * `:ttl` - Time To Live (TTL) or expiration time in milliseconds for a key
      (default: `:infinity`). It applies to all given `entries`.

  See the "Shared options" section at the module documentation for more options.

  ## Example

      iex> MyCache.put_all(apples: 3, bananas: 1)
      :ok

      iex> MyCache.put_all(%{apples: 2, oranges: 1}, ttl: 10_000)
      :ok

  Ideally, this operation should be atomic, so all given keys are put at once.
  But it depends purely on the adapter's implementation and the backend used
  internally by the adapter. Hence, it is recommended to review the adapter's
  documentation.
  """
  @callback put_all(entries, opts) :: :ok

  @doc """
  Puts the given `value` under `key` into the cache, only if it does not
  already exist.

  Returns `true` if a value was set, otherwise, `false` is returned.

  ## Options

    * `:ttl` - Time To Live (TTL) or expiration time in milliseconds for a key
      (default: `:infinity`).

  See the "Shared options" section at the module documentation for more options.

  ## Example

      iex> MyCache.put_new("foo", "bar")
      true

      iex> MyCache.put_new("foo", "bar")
      false

      # if the value is nil, it is not stored (operation is skipped)
      iex> MyCache.put_new("other", nil)
      true
  """
  @callback put_new(key, value, opts) :: boolean

  @doc """
  Similar to `put_new/3` but raises `Nebulex.KeyAlreadyExistsError` if the
  key already exists.

  ## Options

    * `:ttl` - Time To Live (TTL) or expiration time in milliseconds for a key
      (default: `:infinity`).

  See the "Shared options" section at the module documentation for more options.

  ## Example

      MyCache.put_new!("foo", "bar")
  """
  @callback put_new!(key, value, opts) :: true

  @doc """
  Puts the given `entries` (key/value pairs) into the `cache`. It will not
  perform any operation at all even if just a single key already exists.

  Returns `true` if all entries were successfully set. It returns `false`
  if no key was set (at least one key already existed).

  ## Options

    * `:ttl` - Time To Live (TTL) or expiration time in milliseconds for a key
      (default: `:infinity`). It applies to all given `entries`.

  See the "Shared options" section at the module documentation for more options.

  ## Example

      iex> MyCache.put_new_all(apples: 3, bananas: 1)
      true

      iex> MyCache.put_new_all(%{apples: 3, oranges: 1}, ttl: 10_000)
      false

  Ideally, this operation should be atomic, so all given keys are put at once.
  But it depends purely on the adapter's implementation and the backend used
  internally by the adapter. Hence, it is recommended to review the adapter's
  documentation.
  """
  @callback put_new_all(entries, opts) :: boolean

  @doc """
  Alters the entry stored under `key`, but only if the entry already exists
  into the Cache.

  Returns `true` if a value was set, otherwise, `false` is returned.

  ## Options

    * `:ttl` - Time To Live (TTL) or expiration time in milliseconds for a key
      (default: `:infinity`).

  See the "Shared options" section at the module documentation for more options.

  ## Example

      iex> MyCache.replace("foo", "bar")
      false

      iex> MyCache.put_new("foo", "bar")
      true

      iex> MyCache.replace("foo", "bar2")
      true

      # update current value and TTL
      iex> MyCache.replace("foo", "bar3", ttl: 10_000)
      true
  """
  @callback replace(key, value, opts) :: boolean

  @doc """
  Similar to `replace/3` but raises `KeyError` if `key` is not found.

  ## Options

    * `:ttl` - Time To Live (TTL) or expiration time in milliseconds for a key
      (default: `:infinity`).

  See the "Shared options" section at the module documentation for more options.

  ## Example

      MyCache.replace!("foo", "bar")
  """
  @callback replace!(key, value, opts) :: true

  @doc """
  Deletes the entry in Cache for a specific `key`.

  ## Options

  See the "Shared options" section at the module documentation for more options.

  ## Example

      iex> MyCache.put(:a, 1)
      :ok

      iex> MyCache.delete(:a)
      :ok

      iex> MyCache.get(:a)
      :ok

      iex> MyCache.delete(:non_existent_key)
      :ok
  """
  @callback delete(key, opts) :: :ok

  @doc """
  Returns and removes the value associated with `key` in the Cache.
  If the `key` does not exist, then `nil` is returned.

  ## Options

  See the "Shared options" section at the module documentation for more options.

  ## Examples

      iex> MyCache.put(:a, 1)
      :ok

      iex> MyCache.take(:a)
      1

      iex> MyCache.take(:a)
      nil
  """
  @callback take(key, opts) :: value

  @doc """
  Similar to `take/2` but raises `KeyError` if `key` is not found.

  ## Options

  See the "Shared options" section at the module documentation for more options.

  ## Example

      MyCache.take!(:a)
  """
  @callback take!(key, opts) :: value

  @doc """
  Returns whether the given `key` exists in the Cache.

  ## Examples

      iex> MyCache.put(:a, 1)
      :ok

      iex> MyCache.has_key?(:a)
      true

      iex> MyCache.has_key?(:b)
      false
  """
  @callback has_key?(key) :: boolean

  @doc """
  Gets the value from `key` and updates it, all in one pass.

  `fun` is called with the current cached value under `key` (or `nil`
  if `key` hasn't been cached) and must return a two-element tuple:
  the "get" value (the retrieved value, which can be operated on before
  being returned) and the new value to be stored under `key`. `fun` may
  also return `:pop`, which means the current value shall be removed
  from Cache and returned.

  The returned value is a tuple with the "get" value returned by
  `fun` and the new updated value under `key`.

  ## Options

    * `:ttl` - Time To Live (TTL) or expiration time in milliseconds for a key
      (default: `:infinity`).

  See the "Shared options" section at the module documentation for more options.

  ## Examples

      # update nonexistent key
      iex> MyCache.get_and_update(:a, fn current_value ->
      ...>   {current_value, "value!"}
      ...> end)
      {nil, "value!"}

      # update existing key
      iex> MyCache.get_and_update(:a, fn current_value ->
      ...>   {current_value, "new value!"}
      ...> end)
      {"value!", "new value!"}

      # pop/remove value if exist
      iex> MyCache.get_and_update(:a, fn _ -> :pop end)
      {"new value!", nil}

      # pop/remove nonexistent key
      iex> MyCache.get_and_update(:b, fn _ -> :pop end)
      {nil, nil}
  """
  @callback get_and_update(key, (value -> {get, update} | :pop), opts) :: {get, update}
            when get: value, update: value

  @doc """
  Updates the cached `key` with the given function.

  If `key` is present in Cache with value `value`, `fun` is invoked with
  argument `value` and its result is used as the new value of `key`.

  If `key` is not present in Cache, `initial` is inserted as the value of `key`.
  The initial value will not be passed through the update function.

  ## Options

    * `:ttl` - Time To Live (TTL) or expiration time in milliseconds for a key
      (default: `:infinity`).

  See the "Shared options" section at the module documentation for more options.

  ## Examples

      iex> MyCache.update(:a, 1, &(&1 * 2))
      1

      iex> MyCache.update(:a, 1, &(&1 * 2))
      2
  """
  @callback update(key, initial :: value, (value -> value), opts) :: value

  @doc """
  Increments or decrements the counter mapped to the given `key`.

  If `incr >= 0` (positive value) then the current value is incremented by
  that amount, otherwise, it means the X is a negative value so the current
  value is decremented by the same amount.

  ## Options

    * `:ttl` - Time To Live (TTL) or expiration time in milliseconds for a key
      (default: `:infinity`).

  See the "Shared options" section at the module documentation for more options.

  ## Examples

      iex> MyCache.incr(:a)
      1

      iex> MyCache.incr(:a, 2)
      3

      iex> MyCache.incr(:a, -1)
      2
  """
  @callback incr(key, incr :: integer, opts) :: integer

  @doc """
  Returns the remaining time-to-live for the given `key`. If the `key` does not
  exist, then `nil` is returned.

  ## Examples

      iex> MyCache.put(:a, 1, ttl: 5000)
      :ok

      iex> MyCache.put(:b, 2)
      :ok

      iex> MyCache.ttl(:a)
      _remaining_ttl

      iex> MyCache.ttl(:b)
      :infinity

      iex> MyCache.ttl(:c)
      nil
  """
  @callback ttl(key) :: timeout | nil

  @doc """
  Returns `true` if the given `key` exists and the new `ttl` was successfully
  updated, otherwise, `false` is returned.

  ## Examples

      iex> MyCache.put(:a, 1)
      :ok

      iex> MyCache.expire(:a, 5)
      true

      iex> MyCache.expire(:a, :infinity)
      true

      iex> MyCache.ttl(:b, 5)
      false
  """
  @callback expire(key, ttl :: timeout) :: boolean

  @doc """
  Returns `true` if the given `key` exists and the last access time was
  successfully updated, otherwise, `false` is returned.

  ## Examples

      iex> MyCache.put(:a, 1)
      :ok

      iex> MyCache.touch(:a)
      true

      iex> MyCache.ttl(:b)
      false
  """
  @callback touch(key) :: boolean

  @doc """
  Returns the total number of cached entries.

  ## Examples

      iex> :ok = Enum.each(1..10, &MyCache.put(&1, &1))
      iex> MyCache.size()
      10

      iex> :ok = Enum.each(1..5, &MyCache.delete(&1))
      iex> MyCache.size()
      5
  """
  @callback size() :: integer

  @doc """
  Flushes the cache and returns the number of evicted keys.

  ## Examples

      iex> :ok = Enum.each(1..5, &MyCache.put(&1, &1))
      iex> MyCache.flush()
      5

      iex> MyCache.size()
      0
  """
  @callback flush() :: integer

  ## Nebulex.Adapter.Queryable

  @optional_callbacks all: 2, stream: 2

  @doc """
  Fetches all entries from cache matching the given `query`.

  If the `query` is `nil`, it fetches all entries from cache; this is common
  for all adapters. However, the `query` could be any other value, which
  depends entirely on the adapter's implementation; see the "Query"
  section below.

  May raise `Nebulex.QueryError` if query validation fails.

  ## Options

    * `:return` - Tells the query what to return from the matched entries.
      The possible values are: `:key`, `:value`, and `:entry` (`{key, value}`
      pairs). Defaults to `:key`. This option is supported by the build-in
      adapters, but it is recommended to check the adapter's documentation
      to confirm its compatibility with this option.

  See the "Shared options" section at the module documentation for more options.

  ## Example

      # set some entries
      iex> :ok = Enum.each(1..5, &MyCache.put(&1, &1 * 2))

      # fetch all (with default params)
      iex> MyCache.all()
      [1, 2, 3, 4, 5]

      # fetch all entries and return values
      iex> MyCache.all(nil, return: :value)
      [2, 4, 6, 8, 10]

      # fetch all entries that match with the given query
      # assuming we are using Nebulex.Adapters.Local adapter
      iex> query = [{{:_, :"$1", :"$2", :_, :_}, [{:>, :"$2", 5}], [:"$1"]}]
      iex> MyCache.all(query)
      [3, 4, 5]

  ## Query

  Query spec is defined by the adapter, hence, it is recommended to review
  adapters documentation. For instance, the built-in `Nebulex.Adapters.Local`
  adapter supports `nil | :unexpired | :expired | :ets.match_spec()` as query
  value.

  ## Examples

      # additional built-in queries for Nebulex.Adapters.Local adapter
      iex> unexpired = MyCache.all(:unexpired)
      iex> expired = MyCache.all(:expired)

      # if we are using Nebulex.Adapters.Local adapter, the stored entry tuple
      # {:entry, key, value, version, expire_at}, then the match spec could be
      # something like:
      iex> spec = [{{:entry, :"$1", :"$2", :_, :_}, [{:>, :"$2", 5}], [{{:"$1", :"$2"}}]}]
      iex> MyCache.all(spec)
      [{3, 6}, {4, 8}, {5, 10}]

      # the same previous query but using Ex2ms
      iex> import Ex2ms
      Ex2ms

      iex> spec =
      ...>   fun do
      ...>     {_. key, value, _, _} when value > 5 -> {key, value}
      ...>   end

      iex> MyCache.all(spec)
      [{3, 6}, {4, 8}, {5, 10}]
  """
  @callback all(query :: term, opts) :: [any]

  @doc """
  Similar to `all/2` but returns a lazy enumerable that emits all entries
  from the cache matching the given `query`.

  May raise `Nebulex.QueryError` if query validation fails.

  ## Options

    * `:return` - Tells the query what to return from the matched entries.
      The possible values are: `:key`, `:value`, and `:entry` (`{key, value}`
      pairs). Defaults to `:key`. This option is supported by the build-in
      adapters, but it is recommended to check the adapter's documentation
      to confirm its compatibility with this option.

    * `:page_size` - Positive integer (>= 1) that defines the page size for
      the stream (defaults to `10`).

  See the "Shared options" section at the module documentation for more options.

  ## Examples

      # set some entries
      iex> :ok = Enum.each(1..5, &MyCache.put(&1, &1 * 2))

      # stream all (with default params)
      iex> MyCache.stream() |> Enum.to_list()
      [1, 2, 3, 4, 5]

      # stream all entries and return values
      iex> MyCache.stream(nil, return: :value, page_size: 3) |> Enum.to_list()
      [2, 4, 6, 8, 10]

      # additional built-in queries for Nebulex.Adapters.Local adapter
      unexpired_stream = MyCache.stream(:unexpired)
      expired_stream = MyCache.stream(:expired)

      # if we are using Nebulex.Adapters.Local adapter, the stored entry tuple
      # {:entry, key, value, version, expire_at}, then the match spec could be
      # something like:
      iex> spec = [{{:entry, :"$1", :"$2", :_, :_}, [{:>, :"$2", 5}], [{{:"$1", :"$2"}}]}]
      iex> MyCache.stream(spec, page_size: 3) |> Enum.to_list()
      [{3, 6}, {4, 8}, {5, 10}]

      # the same previous query but using Ex2ms
      iex> import Ex2ms
      Ex2ms

      iex> spec =
      ...>   fun do
      ...>     {_, key, value, _, _} when value > 5 -> {key, value}
      ...>   end

      iex> spec |> MyCache.stream(page_size: 3) |> Enum.to_list()
      [{3, 6}, {4, 8}, {5, 10}]
  """
  @callback stream(query :: term, opts) :: Enum.t()

  ## Nebulex.Adapter.Persistence

  @optional_callbacks dump: 2, load: 2

  @doc """
  Dumps a cache to the given file `path`.

  Returns `:ok` if successful, or `{:error, reason}` if an error occurs.

  ## Options

  This operation relies entirely on the adapter implementation, which means the
  options depend on each of them. For that reason, it is recommended to review
  the documentation of the adapter to be used. The built-in adapters inherit
  the default implementation from `Nebulex.Adapter.Persistence`, hence, review
  the available options there.

  ## Examples

      # set some entries
      iex> entries = for x <- 1..10, into: %{}, do: {x, x}
      iex> MyCache.set_many(entries)
      :ok

      # dump cache to a file
      iex> MyCache.dump("my_cache")
      :ok
  """
  @callback dump(path :: Path.t(), opts) :: :ok | {:error, term}

  @doc """
  Loads a dumped cache from the given `path`.

  Returns `:ok` if successful, or `{:error, reason}` if an error occurs.

  ## Options

  Similar to `dump/2`, this operation relies entirely on the adapter
  implementation, therefore, it is recommended to review the documentation
  of the adapter to be used. Similarly, the built-in adapters inherit the
  default implementation from `Nebulex.Adapter.Persistence`, hence, review
  the available options there.

  ## Examples

      # set some entries
      iex> entries = for x <- 1..10, into: %{}, do: {x, x}
      iex> MyCache.set_many(entries)
      :ok

      # dump cache to a file
      iex> MyCache.dump("my_cache")
      :ok

      # load the cache from a file
      iex> MyCache.load("my_cache")
      :ok
  """
  @callback load(path :: Path.t(), opts) :: :ok | {:error, term}

  ## Nebulex.Adapter.Transaction

  @optional_callbacks transaction: 2, in_transaction?: 0

  @doc """
  Runs the given function inside a transaction.

  A successful transaction returns the value returned by the function.

  ## Options

  See the "Shared options" section at the module documentation for more options.

  ## Examples

      MyCache.transaction fn ->
        alice = MyCache.get(:alice)
        bob = MyCache.get(:bob)
        MyCache.put(:alice, %{alice | balance: alice.balance + 100})
        MyCache.put(:bob, %{bob | balance: bob.balance + 100})
      end

      # locking only the involved key (recommended):
      MyCache.transaction [keys: [:alice, :bob]], fn ->
        alice = MyCache.get(:alice)
        bob = MyCache.get(:bob)
        MyCache.put(:alice, %{alice | balance: alice.balance + 100})
        MyCache.put(:bob, %{bob | balance: bob.balance + 100})
      end
  """
  @callback transaction(opts, function :: fun) :: term

  @doc """
  Returns `true` if the current process is inside a transaction.

  ## Examples

      MyCache.in_transaction?
      #=> false

      MyCache.transaction(fn ->
        MyCache.in_transaction? #=> true
      end)
  """
  @callback in_transaction?() :: boolean
end
