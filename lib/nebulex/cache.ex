defmodule Nebulex.Cache do
  @moduledoc ~S"""
  Cache's main interface; defines the cache abstraction layer which is
  highly inspired by [Ecto](https://github.com/elixir-ecto/ecto).

  A Cache maps to an underlying implementation, controlled by the
  adapter. For example, Nebulex ships with a default adapter that
  implements a local generational cache.

  When used, the Cache expects the `:otp_app` and `:adapter` as options.
  The `:otp_app` should point to an OTP application that has the cache
  configuration. For example, the Cache:

      defmodule MyApp.Cache do
        use Nebulex.Cache,
          otp_app: :my_app,
          adapter: Nebulex.Adapters.Local
      end

  Could be configured with:

      config :my_app, MyApp.Cache,
        backend: :shards,
        gc_interval: :timer.hours(12),
        max_size: 1_000_000,
        allocated_memory: 2_000_000_000,
        gc_cleanup_min_timeout: :timer.seconds(10),
        gc_cleanup_max_timeout: :timer.minutes(10)

  Most of the configuration that goes into the `config` is specific
  to the adapter. For this particular example, you can check
  [`Nebulex.Adapters.Local`](https://hexdocs.pm/nebulex/Nebulex.Adapters.Local.html)
  for more information. In spite of this, the following configuration values
  are shared across all adapters:

    * `:name` - The name of the Cache supervisor process.

    * `:stats` - Boolean to define whether or not the cache will provide stats.
      Defaults to `false`. Each adapter is responsible for providing stats by
      implementing `Nebulex.Adapter.Stats` behaviour. See the "Stats" section
      below.

    * `:telemetry_prefix` - It is recommend for adapters to publish events
      using the `Telemetry` library. By default, the telemetry prefix is based
      on the module name, so if your module is called `MyApp.Cache`, the prefix
      will be `[:my_app, :cache]`. See the "Telemetry events" section to see
      what events recommended for the  adapters to publish.. Note that if you
      have multiple caches, you should keep the `:telemetry_prefix` consistent
      for each of them and use the `:cache` and/or `:name` (in case of a named
      or dynamic cache) properties in the event metadata for distinguishing
      between caches. If it is set to `nil`, Telemetry events are disabled for
      that cache.

  ## Stats

  Stats support depends on the adapter entirely, it should implement the
  optional behaviour `Nebulex.Adapter.Stats` to support so. Nevertheless,
  the behaviour `Nebulex.Adapter.Stats` brings with a default implementation
  using [Erlang counters][https://erlang.org/doc/man/counters.html], which is
  used by the local built-in adapter (`Nebulex.Adapters.Local`).

  To use stats it is a matter to set the option `:stats` to `true` into the
  Cache options. For example, you can do it in the configuration file:

      config :my_app, MyApp.Cache,
        stats: true,
        ...

  > Remember to check if the underlying adapter implements the
    `Nebulex.Adapter.Stats` behaviour.

  See `c:Nebulex.Cache.stats/0` for more information.

  ## Dispatching stats via Telemetry

  It is possible to emit Telemetry events for the current stats via
  `c:Nebulex.Cache.dispatch_stats/1`, but it has to be called explicitly,
  Nebulex does not emit Telemetry events on its own. But it is pretty easy
  to emit this event using [`:telemetry_poller`][telemetry_poller].

  [telemetry_poller]: https://github.com/beam-telemetry/telemetry_poller

  For example, we can define a custom pollable measurement:

      :telemetry_poller.start_link(
        measurements: [
          {MyApp.Cache, :dispatch_stats, []},
        ],
        # configure sampling period - default is :timer.seconds(5)
        period: :timer.seconds(30),
        name: :my_cache_stats_poller
      )

  Or you can also start the `:telemetry_poller` process along with your
  application supervision tree, like so:

      def start(_type, _args) do
        my_cache_stats_poller_opts = [
          measurements: [
            {MyApp.Cache, :dispatch_stats, []},
          ],
          period: :timer.seconds(30),
          name: :my_cache_stats_poller
        ]

        children = [
          {MyApp.Cache, []},
          {:telemetry_poller, my_cache_stats_poller_opts}
        ]

        opts = [strategy: :one_for_one, name: MyApp.Supervisor]
        Supervisor.start_link(children, opts)
      end

  See [Nebulex Telemetry Guide](http://hexdocs.pm/nebulex/telemetry.html)
  for more information.

  ## Telemetry events

  Similar to Ecto or Phoenix, Nebulex also provides built-in Telemetry events
  applied to all caches, and cache adapter-specific events.

  ### Nebulex built-in events

  The following events are emitted by all Nebulex caches:

    * `[:nebulex, :cache, :init]` - it is dispatched whenever a cache starts.
      The measurement is a single `system_time` entry in native unit. The
      metadata is the `:cache` and all initialization options under `:opts`.

  ### Adapter-specific events

  It is recommend the adapters to publish certain `Telemetry` events listed
  below. Those events will use the `:telemetry_prefix` outlined above which
  defaults to `[:my_app, :cache]`.

  For instance, to receive all events published by a cache called `MyApp.Cache`,
  one could define a module:

      defmodule MyApp.Telemetry do
        def handle_event([:my_app, :cache, :command, event], measurements, metadata, config) do
          case event do
            :start ->
              # Handle start event ...

            :stop ->
              # Handle stop event ...

            :exception ->
              # Handle exception event ...
          end
        end
      end

  Then, in the `Application.start/2` callback, attach the handler to this event
  using a unique handler id:

      :telemetry.attach(
        "my-app-handler-id",
        [:my_app, :cache, :command],
        &MyApp.Telemetry.handle_event/4,
        %{}
      )

  See [the telemetry documentation](https://hexdocs.pm/telemetry/)
  for more information.

  The following are the events you should expect from Nebulex. All examples
  below consider a cache named `MyApp.Cache`:

  #### `[:my_app, :cache, :command, :start]`

  This event should be invoked on every cache call sent to the adapter before
  the command logic is executed.

  The `:measurements` map will include the following:

    * `:system_time` - The current system time in native units from calling:
      `System.system_time()`.

  A Telemetry `:metadata` map including the following fields. Each cache adapter
  may emit different information here. For built-in adapters, it will contain:

    * `:action` - An atom indicating the called cache command or action.
    * `:cache` - The Nebulex cache.

  #### `[:my_app, :cache, :command, :stop]`

  This event should be invoked on every cache call sent to the adapter after
  the command logic is executed.

  The `:measurements` map will include the following:

    * `:duration` - The time spent executing the cache command. The measurement
      is given in the `:native` time unit. You can read more about it in the
      docs for `System.convert_time_unit/3`.

  A Telemetry `:metadata` map including the following fields. Each cache adapter
  may emit different information here. For built-in adapters, it will contain:

    * `:action` - An atom indicating the called cache command or action.
    * `:cache` - The Nebulex cache.
    * `:result` - The command result.

  #### `[:my_app, :cache, :command, :exception]`

  This event should be invoked when an error or exception occurs while executing
  the cache command.

  The `:measurements` map will include the following:

    * `:duration` - The time spent executing the cache command. The measurement
      is given in the `:native` time unit. You can read more about it in the
      docs for `System.convert_time_unit/3`.

  A Telemetry `:metadata` map including the following fields. Each cache adapter
  may emit different information here. For built-in adapters, it will contain:

    * `:action` - An atom indicating the called cache command or action.
    * `:cache` - The Nebulex cache.
    * `:kind` - The type of the error: `:error`, `:exit`, or `:throw`.
    * `:reason` - The reason of the error.
    * `:stacktrace` - The stacktrace.

  **NOTE:** The events outlined above are the recommended for the adapters
  to dispatch. However, it is highly recommended to review the used adapter
  documentation to ensure it is fullly compatible with these events, perhaps
  differences, or perhaps also additional events.

  ## Distributed topologies

  Nebulex provides the following adapters for distributed topologies:

    * `Nebulex.Adapters.Partitioned` - Partitioned cache topology.
    * `Nebulex.Adapters.Replicated` - Replicated cache topology.
    * `Nebulex.Adapters.Multilevel` - Multi-level distributed cache topology.

  These adapters work more as wrappers for an existing local adapter and provide
  the distributed topology on top of it. Optionally, you can set the adapter for
  the primary cache storage with the option `:primary_storage_adapter`. Defaults
  to `Nebulex.Adapters.Local`.
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

      alias Nebulex.Cache.{
        Entry,
        Persistence,
        Queryable,
        Stats,
        Storage,
        Transaction
      }

      alias Nebulex.Hook

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

      @impl true
      def with_dynamic_cache(name, fun) do
        default_dynamic_cache = get_dynamic_cache()

        try do
          _ = put_dynamic_cache(name)
          fun.()
        after
          _ = put_dynamic_cache(default_dynamic_cache)
        end
      end

      @impl true
      def with_dynamic_cache(name, module, fun, args) do
        with_dynamic_cache(name, fn -> apply(module, fun, args) end)
      end

      ## Entry

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
      def put_new(key, value, opts \\ []) do
        Entry.put_new(get_dynamic_cache(), key, value, opts)
      end

      @impl true
      def put_new!(key, value, opts \\ []) do
        Entry.put_new!(get_dynamic_cache(), key, value, opts)
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
      def put_all(entries, opts \\ []) do
        Entry.put_all(get_dynamic_cache(), entries, opts)
      end

      @impl true
      def put_new_all(entries, opts \\ []) do
        Entry.put_new_all(get_dynamic_cache(), entries, opts)
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
      def incr(key, amount \\ 1, opts \\ []) do
        Entry.incr(get_dynamic_cache(), key, amount, opts)
      end

      @impl true
      def decr(key, amount \\ 1, opts \\ []) do
        Entry.decr(get_dynamic_cache(), key, amount, opts)
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

      ## Queryable

      if Nebulex.Adapter.Queryable in behaviours do
        @impl true
        def all(query \\ nil, opts \\ []) do
          Queryable.all(get_dynamic_cache(), query, opts)
        end

        @impl true
        def count_all(query \\ nil, opts \\ []) do
          Queryable.count_all(get_dynamic_cache(), query, opts)
        end

        @impl true
        def delete_all(query \\ nil, opts \\ []) do
          Queryable.delete_all(get_dynamic_cache(), query, opts)
        end

        @impl true
        def stream(query \\ nil, opts \\ []) do
          Queryable.stream(get_dynamic_cache(), query, opts)
        end

        ## Deprecated functions (for backwards compatibility)

        @impl true
        defdelegate size, to: __MODULE__, as: :count_all

        @impl true
        defdelegate flush, to: __MODULE__, as: :delete_all
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

      ## Stats

      if Nebulex.Adapter.Stats in behaviours do
        @impl true
        def stats do
          Stats.stats(get_dynamic_cache())
        end

        @impl true
        def dispatch_stats(opts \\ []) do
          Stats.dispatch_stats(get_dynamic_cache(), opts)
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

  If the `c:init/1` callback is implemented in the cache, it will be invoked.
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

  You can also start caches without names by explicitly setting the name
  to `nil`:

      MyApp.Cache.start_link(name: nil, backend: :shards)

  > **NOTE:** There may be adapters requiring the `:name` option anyway,
    therefore, it is highly recommended to see the adapter's documentation
    you want to use.

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
  Invokes the given function `fun` for the dynamic cache `name_or_pid`.

  ## Example

      MyCache.with_dynamic_cache(:my_cache, fn ->
        MyCache.put("foo", "var")
      end)

  See `c:get_dynamic_cache/0` and `c:put_dynamic_cache/1`.
  """
  @callback with_dynamic_cache(name_or_pid :: atom() | pid(), fun) :: term

  @doc """
  For the dynamic cache `name_or_pid`, invokes the given function name `fun`
  from `module` with the list of arguments `args`.

  ## Example

      MyCache.with_dynamic_cache(:my_cache, Module, :some_fun, ["foo", "bar"])

  See `c:get_dynamic_cache/0` and `c:put_dynamic_cache/1`.
  """
  @callback with_dynamic_cache(
              name_or_pid :: atom() | pid(),
              module,
              fun :: atom,
              args :: [term]
            ) :: term

  ## Nebulex.Adapter.Entry

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
  Similar to `c:get/2` but raises `KeyError` if `key` is not found.

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

    * `:ttl` - (positive integer or `:infinity`) Defines the time-to-live
      (or expiry time) for the given key  in **milliseconds**. Defaults
      to `:infinity`.

  See the "Shared options" section at the module documentation for more options.

  ## Example

      iex> MyCache.put("foo", "bar")
      :ok

  If the value is nil, then it is not stored (operation is skipped):

      iex> MyCache.put("foo", nil)
      :ok

  Put key with time-to-live:

      iex> MyCache.put("foo", "bar", ttl: 10_000)
      :ok

  Using Nebulex.Time for TTL:

      iex> MyCache.put("foo", "bar", ttl: :timer.hours(1))
      :ok

      iex> MyCache.put("foo", "bar", ttl: :timer.minutes(1))
      :ok

      iex> MyCache.put("foo", "bar", ttl: :timer.seconds(1))
      :ok

  """
  @callback put(key, value, opts) :: :ok

  @doc """
  Puts the given `entries` (key/value pairs) into the Cache. It replaces
  existing values with new values (just as regular `put`).

  ## Options

    * `:ttl` - (positive integer or `:infinity`) Defines the time-to-live
      (or expiry time) for the given key  in **milliseconds**. Defaults
      to `:infinity`.

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

    * `:ttl` - (positive integer or `:infinity`) Defines the time-to-live
      (or expiry time) for the given key  in **milliseconds**. Defaults
      to `:infinity`.

  See the "Shared options" section at the module documentation for more options.

  ## Example

      iex> MyCache.put_new("foo", "bar")
      true

      iex> MyCache.put_new("foo", "bar")
      false

  If the value is nil, it is not stored (operation is skipped):

      iex> MyCache.put_new("other", nil)
      true

  """
  @callback put_new(key, value, opts) :: boolean

  @doc """
  Similar to `c:put_new/3` but raises `Nebulex.KeyAlreadyExistsError` if the
  key already exists.

  ## Options

    * `:ttl` - (positive integer or `:infinity`) Defines the time-to-live
      (or expiry time) for the given key  in **milliseconds**. Defaults
      to `:infinity`.

  See the "Shared options" section at the module documentation for more options.

  ## Example

      iex> MyCache.put_new!("foo", "bar")
      true

  """
  @callback put_new!(key, value, opts) :: true

  @doc """
  Puts the given `entries` (key/value pairs) into the `cache`. It will not
  perform any operation at all even if just a single key already exists.

  Returns `true` if all entries were successfully set. It returns `false`
  if no key was set (at least one key already existed).

  ## Options

    * `:ttl` - (positive integer or `:infinity`) Defines the time-to-live
      (or expiry time) for the given key  in **milliseconds**. Defaults
      to `:infinity`.

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

    * `:ttl` - (positive integer or `:infinity`) Defines the time-to-live
      (or expiry time) for the given key  in **milliseconds**. Defaults
      to `:infinity`.

  See the "Shared options" section at the module documentation for more options.

  ## Example

      iex> MyCache.replace("foo", "bar")
      false

      iex> MyCache.put_new("foo", "bar")
      true

      iex> MyCache.replace("foo", "bar2")
      true

  Update current value and TTL:

      iex> MyCache.replace("foo", "bar3", ttl: 10_000)
      true

  """
  @callback replace(key, value, opts) :: boolean

  @doc """
  Similar to `c:replace/3` but raises `KeyError` if `key` is not found.

  ## Options

    * `:ttl` - (positive integer or `:infinity`) Defines the time-to-live
      (or expiry time) for the given key  in **milliseconds**. Defaults
      to `:infinity`.

  See the "Shared options" section at the module documentation for more options.

  ## Example

      iex> MyCache.replace!("foo", "bar")
      true

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
  Similar to `c:take/2` but raises `KeyError` if `key` is not found.

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

  `fun` is called with the current cached value under `key` (or `nil` if `key`
  hasn't been cached) and must return a two-element tuple: the current value
  (the retrieved value, which can be operated on before being returned) and
  the new value to be stored under `key`. `fun` may also return `:pop`, which
  means the current value shall be removed from Cache and returned.

  The returned value is a tuple with the current value returned by `fun` and
  the new updated value under `key`.

  ## Options

    * `:ttl` - (positive integer or `:infinity`) Defines the time-to-live
      (or expiry time) for the given key  in **milliseconds**. Defaults
      to `:infinity`.

  See the "Shared options" section at the module documentation for more options.

  ## Examples

  Update nonexistent key:

      iex> MyCache.get_and_update(:a, fn current_value ->
      ...>   {current_value, "value!"}
      ...> end)
      {nil, "value!"}

  Update existing key:

      iex> MyCache.get_and_update(:a, fn current_value ->
      ...>   {current_value, "new value!"}
      ...> end)
      {"value!", "new value!"}

  Pop/remove value if exist:

      iex> MyCache.get_and_update(:a, fn _ -> :pop end)
      {"new value!", nil}

  Pop/remove nonexistent key:

      iex> MyCache.get_and_update(:b, fn _ -> :pop end)
      {nil, nil}

  """
  @callback get_and_update(key, (value -> {current_value, new_value} | :pop), opts) ::
              {current_value, new_value}
            when current_value: value, new_value: value

  @doc """
  Updates the cached `key` with the given function.

  If `key` is present in Cache with value `value`, `fun` is invoked with
  argument `value` and its result is used as the new value of `key`.

  If `key` is not present in Cache, `initial` is inserted as the value of `key`.
  The initial value will not be passed through the update function.

  ## Options

    * `:ttl` - (positive integer or `:infinity`) Defines the time-to-live
      (or expiry time) for the given key  in **milliseconds**. Defaults
      to `:infinity`.

  See the "Shared options" section at the module documentation for more options.

  ## Examples

      iex> MyCache.update(:a, 1, &(&1 * 2))
      1

      iex> MyCache.update(:a, 1, &(&1 * 2))
      2

  """
  @callback update(key, initial :: value, (value -> value), opts) :: value

  @doc """
  Increments the counter stored at `key` by the given `amount`.

  If `amount < 0` (negative), the value is decremented by that `amount`
  instead.

  ## Options

    * `:ttl` - (positive integer or `:infinity`) Defines the time-to-live
      (or expiry time) for the given key  in **milliseconds**. Defaults
      to `:infinity`.

    * `:default` - If `key` is not present in Cache, the default value is
      inserted as initial value of key before the it is incremented.
      Defaults to `0`.

  See the "Shared options" section at the module documentation for more options.

  ## Examples

      iex> MyCache.incr(:a)
      1

      iex> MyCache.incr(:a, 2)
      3

      iex> MyCache.incr(:a, -1)
      2

      iex> MyCache.incr(:missing_key, 2, default: 10)
      12

  """
  @callback incr(key, amount :: integer, opts) :: integer

  @doc """
  Decrements the counter stored at `key` by the given `amount`.

  If `amount < 0` (negative), the value is incremented by that `amount`
  instead (opposite to `incr/3`).

  ## Options

    * `:ttl` - (positive integer or `:infinity`) Defines the time-to-live
      (or expiry time) for the given key  in **milliseconds**. Defaults
      to `:infinity`.

    * `:default` - If `key` is not present in Cache, the default value is
      inserted as initial value of key before the it is incremented.
      Defaults to `0`.

  See the "Shared options" section at the module documentation for more options.

  ## Examples

      iex> MyCache.decr(:a)
      -1

      iex> MyCache.decr(:a, 2)
      -3

      iex> MyCache.decr(:a, -1)
      -2

      iex> MyCache.decr(:missing_key, 2, default: 10)
      8

  """
  @callback decr(key, amount :: integer, opts) :: integer

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

  ## Deprecated Callbacks

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
  @doc deprecated: "Use count_all/2 instead"
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
  @doc deprecated: "Use delete_all/2 instead"
  @callback flush() :: integer

  ## Nebulex.Adapter.Queryable

  @optional_callbacks all: 2, count_all: 2, delete_all: 2, stream: 2

  @doc """
  Fetches all entries from cache matching the given `query`.

  May raise `Nebulex.QueryError` if query validation fails.

  ## Query values

  There are two types of query values. The ones shared and implemented
  by all adapters and the ones that are adapter specific.

  ### Common queries

  The following query values are shared and/or supported for all adapters:

    * `nil` - Returns a list with all cached entries based on the `:return`
      option.

  ### Adapter-specific queries

  The `query` value depends entirely on the adapter implementation; it could
  any term. Therefore, it is highly recommended to see adapters' documentation
  for more information about building queries. For example, the built-in
  `Nebulex.Adapters.Local` adapter uses `:ets.match_spec()` for queries,
  as well as other pre-defined ones like `:unexpired` and `:expired`.

  ## Options

    * `:return` - Tells the query what to return from the matched entries.
      See the possible values in the "Query return option" section below.
      The default depends on the adapter, for example, the default for the
      built-in adapters is `:key`. This option is supported by the build-in
      adapters, but it is recommended to see the adapter's documentation
      to confirm its compatibility with this option.

  See the "Shared options" section at the module documentation for more options.

  ## Query return option

  The following are the possible values for the `:return` option:

    * `:key` - Returns a list only with the keys.
    * `:value` - Returns a list only with the values.
    * `:entry` - Returns a list of `t:Nebulex.Entry.t/0`.
    * `{:key, :value}` - Returns a list of tuples in the form `{key, value}`.

  See adapters documentation to confirm what of these options are supported
  and what other added.

  ## Example

  Populate the cache with some entries:

      iex> :ok = Enum.each(1..5, &MyCache.put(&1, &1 * 2))

  Fetch all (with default params):

      iex> MyCache.all()
      [1, 2, 3, 4, 5]

  Fetch all entries and return values:

      iex> MyCache.all(nil, return: :value)
      [2, 4, 6, 8, 10]

  Fetch all entries and return them as key/value pairs:

      iex> MyCache.all(nil, return: {:key, :value})
      [{1, 2}, {2, 4}, {3, 6}, {4, 8}, {5, 10}]

  Fetch all entries that match with the given query assuming we are using
  `Nebulex.Adapters.Local` adapter:

      iex> query = [{{:_, :"$1", :"$2", :_, :_}, [{:>, :"$2", 5}], [:"$1"]}]
      iex> MyCache.all(query)
      [3, 4, 5]

  ## Query

  Query spec is defined by the adapter, hence, it is recommended to review
  adapters documentation. For instance, the built-in `Nebulex.Adapters.Local`
  adapter supports `nil | :unexpired | :expired | :ets.match_spec()` as query
  value.

  ## Examples

  Additional built-in queries for `Nebulex.Adapters.Local` adapter:

      iex> unexpired = MyCache.all(:unexpired)
      iex> expired = MyCache.all(:expired)

  If we are using Nebulex.Adapters.Local adapter, the stored entry tuple
  `{:entry, key, value, version, expire_at}`, then the match spec could be
  something like:

      iex> spec = [
      ...>   {{:entry, :"$1", :"$2", :_, :_},
      ...>   [{:>, :"$2", 5}], [{{:"$1", :"$2"}}]}
      ...> ]
      iex> MyCache.all(spec)
      [{3, 6}, {4, 8}, {5, 10}]

  The same previous query but using `Ex2ms`:

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
  Similar to `c:all/2` but returns a lazy enumerable that emits all entries
  from the cache matching the given `query`.

  If `query` is `nil`, then all entries in cache match and are returned
  when the stream is evaluated; based on the `:return` option.

  May raise `Nebulex.QueryError` if query validation fails.

  ## Query values

  See `c:all/2` callback for more information about the query values.

  ## Options

    * `:return` - Tells the query what to return from the matched entries.
      See the possible values in the "Query return option" section below.
      The default depends on the adapter, for example, the default for the
      built-in adapters is `:key`. This option is supported by the build-in
      adapters, but it is recommended to see the adapter's documentation
      to confirm its compatibility with this option.

    * `:page_size` - Positive integer (>= 1) that defines the page size
      internally used by the adapter for paginating the results coming
      back from the cache's backend. Defaults to `20`; it's unlikely
      this will ever need changing.

  See the "Shared options" section at the module documentation for more options.

  ## Query return option

  The following are the possible values for the `:return` option:

    * `:key` - Returns a list only with the keys.
    * `:value` - Returns a list only with the values.
    * `:entry` - Returns a list of `t:Nebulex.Entry.t/0`.
    * `{:key, :value}` - Returns a list of tuples in the form `{key, value}`.

  See adapters documentation to confirm what of these options are supported
  and what other added.

  ## Examples

  Populate the cache with some entries:

      iex> :ok = Enum.each(1..5, &MyCache.put(&1, &1 * 2))

  Stream all (with default params):

      iex> MyCache.stream() |> Enum.to_list()
      [1, 2, 3, 4, 5]

  Stream all entries and return values:

      iex> nil |> MyCache.stream(return: :value, page_size: 3) |> Enum.to_list()
      [2, 4, 6, 8, 10]

  Stream all entries and return them as key/value pairs:

      iex> nil |> MyCache.stream(return: {:key, :value}) |> Enum.to_list()
      [{1, 2}, {2, 4}, {3, 6}, {4, 8}, {5, 10}]

  Additional built-in queries for `Nebulex.Adapters.Local` adapter:

      iex> unexpired_stream = MyCache.stream(:unexpired)
      iex> expired_stream = MyCache.stream(:expired)

  If we are using Nebulex.Adapters.Local adapter, the stored entry tuple
  `{:entry, key, value, version, expire_at}`, then the match spec could be
  something like:

      iex> spec = [
      ...>   {{:entry, :"$1", :"$2", :_, :_},
      ...>   [{:>, :"$2", 5}], [{{:"$1", :"$2"}}]}
      ...> ]
      iex> MyCache.stream(spec, page_size: 100) |> Enum.to_list()
      [{3, 6}, {4, 8}, {5, 10}]

  The same previous query but using `Ex2ms`:

      iex> import Ex2ms
      Ex2ms

      iex> spec =
      ...>   fun do
      ...>     {_, key, value, _, _} when value > 5 -> {key, value}
      ...>   end

      iex> spec |> MyCache.stream(page_size: 100) |> Enum.to_list()
      [{3, 6}, {4, 8}, {5, 10}]

  """
  @callback stream(query :: term, opts) :: Enum.t()

  @doc """
  Deletes all entries matching the given `query`. If `query` is `nil`,
  then all entries in the cache are deleted.

  It returns the number of deleted entries.

  May raise `Nebulex.QueryError` if query validation fails.

  ## Query values

  See `c:all/2` callback for more information about the query values.

  ## Options

  See the "Shared options" section at the module documentation for more options.

  ## Example

  Populate the cache with some entries:

      iex> :ok = Enum.each(1..5, &MyCache.put(&1, &1 * 2))

  Delete all (with default params):

      iex> MyCache.delete_all()
      5

  Delete all entries that match with the given query assuming we are using
  `Nebulex.Adapters.Local` adapter:

      iex> query = [{{:_, :"$1", :"$2", :_, :_}, [{:>, :"$2", 5}], [true]}]
      iex> MyCache.delete_all(query)

  > For the local adapter you can use [Ex2ms](https://github.com/ericmj/ex2ms)
    to build the match specs much easier.

  Additional built-in queries for `Nebulex.Adapters.Local` adapter:

      iex> unexpired = MyCache.delete_all(:unexpired)
      iex> expired = MyCache.delete_all(:expired)

  """
  @callback delete_all(query :: term, opts) :: integer

  @doc """
  Counts all entries in cache matching the given `query`.

  It returns the count of the matched entries.

  If `query` is `nil` (the default), then the total number of
  cached entries is returned.

  May raise `Nebulex.QueryError` if query validation fails.

  ## Query values

  See `c:all/2` callback for more information about the query values.

  ## Example

  Populate the cache with some entries:

      iex> :ok = Enum.each(1..5, &MyCache.put(&1, &1 * 2))

  Count all entries in cache:

      iex> MyCache.count_all()
      5

  Count all entries that match with the given query assuming we are using
  `Nebulex.Adapters.Local` adapter:

      iex> query = [{{:_, :"$1", :"$2", :_, :_}, [{:>, :"$2", 5}], [true]}]
      iex> MyCache.count_all(query)

  > For the local adapter you can use [Ex2ms](https://github.com/ericmj/ex2ms)
    to build the match specs much easier.

  Additional built-in queries for `Nebulex.Adapters.Local` adapter:

      iex> unexpired = MyCache.count_all(:unexpired)
      iex> expired = MyCache.count_all(:expired)

  """
  @callback count_all(query :: term, opts) :: integer

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

  Populate the cache with some entries:

      iex> entries = for x <- 1..10, into: %{}, do: {x, x}
      iex> MyCache.set_many(entries)
      :ok

  Dump cache to a file:

      iex> MyCache.dump("my_cache")
      :ok

  """
  @callback dump(path :: Path.t(), opts) :: :ok | {:error, term}

  @doc """
  Loads a dumped cache from the given `path`.

  Returns `:ok` if successful, or `{:error, reason}` if an error occurs.

  ## Options

  Similar to `c:dump/2`, this operation relies entirely on the adapter
  implementation, therefore, it is recommended to review the documentation
  of the adapter to be used. Similarly, the built-in adapters inherit the
  default implementation from `Nebulex.Adapter.Persistence`, hence, review
  the available options there.

  ## Examples

  Populate the cache with some entries:

      iex> entries = for x <- 1..10, into: %{}, do: {x, x}
      iex> MyCache.set_many(entries)
      :ok

  Dump cache to a file:

      iex> MyCache.dump("my_cache")
      :ok

  Load the cache from a file:

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

  Locking only the involved key (recommended):

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

  ## Nebulex.Adapter.Stats

  @optional_callbacks stats: 0, dispatch_stats: 1

  @doc """
  Returns `Nebulex.Stats.t()` with the current stats values.

  If the stats are disabled for the cache, then `nil` is returned.

  ## Example

      iex> MyCache.stats()
      %Nebulex.Stats{
        measurements: {
          evictions: 0,
          expirations: 0,
          hits: 0,
          misses: 0,
          updates: 0,
          writes: 0
        },
        metadata: %{}
      }

  """
  @callback stats() :: Nebulex.Stats.t() | nil

  @doc """
  Emits a telemetry event when called with the current stats count.

  The telemetry `:measurements` map will include the same as
  `Nebulex.Stats.t()`'s measurements. For example:

    * `:evictions` - Current **evictions** count.
    * `:expirations` - Current **expirations** count.
    * `:hits` - Current **hits** count.
    * `:misses` - Current **misses** count.
    * `:updates` - Current **updates** count.
    * `:writes` - Current **writes** count.

  The telemetry `:metadata` map will include the same as `Nebulex.Stats.t()`'s
  metadata by default. For example:

    * `:cache` - The cache module, or the name (if an explicit name has been
      given to the cache).

  Additionally, you can add your own metadata fields by given the option
  `:metadata`.

  ## Options

    * `:event_prefix` – The prefix of the telemetry event.
      Defaults to `[:nebulex, :cache]`.

    * `:metadata` – A map with additional metadata fields. Defaults to `%{}`.

  ## Examples

      iex> MyCache.dispatch_stats()
      :ok

      iex> MyCache.Stats.dispatch_stats(
      ...>   event_prefix: [:my_cache],
      ...>   metadata: %{tag: "tag1"}
      ...> )
      :ok

  **NOTE:** Since `:telemetry` is an optional dependency, when it is not
  defined, a default implementation is provided without any logic, just
  returning `:ok`.
  """
  @callback dispatch_stats(opts) :: :ok
end
