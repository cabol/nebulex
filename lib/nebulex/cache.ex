defmodule Nebulex.Cache do
  @moduledoc """
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

    * `:telemetry_prefix` - It is recommend for adapters to publish events
      using the `Telemetry` library. By default, the telemetry prefix is based
      on the module name, so if your module is called `MyApp.Cache`, the prefix
      will be `[:my_app, :cache]`. See the "Telemetry events" section to see
      what events recommended for the  adapters to publish.. Note that if you
      have multiple caches, you should keep the `:telemetry_prefix` consistent
      for each of them and use the `:cache` and/or `:name` (in case of a named
      or dynamic cache) properties in the event metadata for distinguishing
      between caches.

    * `:telemetry` - An optional flag to tell the adapters whether Telemetry
      events should be emitted or not. Defaults to `true`.

    * `:stats` - Boolean to define whether or not the cache will provide stats.
      Defaults to `false`. Each adapter is responsible for providing stats by
      implementing `Nebulex.Adapter.Stats` behaviour. See the "Stats" section
      below.

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
        def handle_event(
              [:my_app, :cache, :command, event],
              measurements,
              metadata,
              config
            ) do
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

    * `:adapter_meta` - The adapter metadata.
    * `:function_name` - The name of the invoked adapter function.
    * `:args` - The arguments of the invoked adapter function, omitting the
      first argument, since it is the adapter metadata already included into
      the event's metadata.

  #### `[:my_app, :cache, :command, :stop]`

  This event should be invoked on every cache call sent to the adapter after
  the command logic is executed.

  The `:measurements` map will include the following:

    * `:duration` - The time spent executing the cache command. The measurement
      is given in the `:native` time unit. You can read more about it in the
      docs for `System.convert_time_unit/3`.

  A Telemetry `:metadata` map including the following fields. Each cache adapter
  may emit different information here. For built-in adapters, it will contain:

    * `:adapter_meta` - The adapter metadata.
    * `:function_name` - The name of the invoked adapter function.
    * `:args` - The arguments of the invoked adapter function, omitting the
      first argument, since it is the adapter metadata already included into
      the event's metadata.
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

    * `:adapter_meta` - The adapter metadata.
    * `:function_name` - The name of the invoked adapter function.
    * `:args` - The arguments of the invoked adapter function, omitting the
      first argument, since it is the adapter metadata already included into
      the event's metadata.
    * `:kind` - The type of the error: `:error`, `:exit`, or `:throw`.
    * `:reason` - The reason of the error.
    * `:stacktrace` - The stacktrace.

  **NOTE:** The events outlined above are the recommended for the adapters
  to dispatch. However, it is highly recommended to review the used adapter
  documentation to ensure it is fullly compatible with these events, perhaps
  differences, or perhaps also additional events.

  ## Stats

  Stats are provided by the adapters by implementing the optional behaviour
  `Nebulex.Adapter.Stats`. This behaviour exposes a callback to return the
  current cache stats.  Nevertheless, the behaviour brings with a default
  implementation using [Erlang counters][counters], which is used by the
  local built-in adapter (`Nebulex.Adapters.Local`).

  [counters]: https://erlang.org/doc/man/counters.html

  One can enable the stats by setting the option `:stats` to `true`.
  For example, in the configuration file:

      config :my_app, MyApp.Cache,
        stats: true,
        ...

  > Remember to check if the underlying adapter implements the
    `Nebulex.Adapter.Stats` behaviour.

  See `c:Nebulex.Cache.stats/0` for more information.

  ## Dispatching stats via Telemetry

  It is possible to emit Telemetry events for the current stats via
  `c:Nebulex.Cache.dispatch_stats/1`, but it has to be invoked explicitly;
  Nebulex does not emit this Telemetry event automatically. But it is very
  easy to emit this event using [`:telemetry_poller`][telemetry_poller].

  [telemetry_poller]: https://github.com/beam-telemetry/telemetry_poller

  For example, one can define a custom pollable measurement:

      :telemetry_poller.start_link(
        measurements: [
          {MyApp.Cache, :dispatch_stats, []},
        ],
        # configure sampling period - default is :timer.seconds(5)
        period: :timer.seconds(30),
        name: :my_cache_stats_poller
      )

  Or you can also start the `:telemetry_poller` process along with your
  application supervision tree:

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

  @typedoc "Proxy type for base Nebulex error"
  @type nbx_error :: Nebulex.Error.t()

  @typedoc "Fetch error reasons"
  @type fetch_error_reason :: Nebulex.KeyError.t() | nbx_error

  @typedoc "Query error reasons"
  @type query_error_reason :: Nebulex.QueryError.t() | nbx_error

  @typedoc "Error tuple with common reasons"
  @type error :: error(nbx_error)

  @typedoc "Error tuple type"
  @type error(reason) :: {:error, reason}

  @typedoc "Ok/Error tuple with default error reasons"
  @type ok_error_tuple(ok) :: ok_error_tuple(ok, nbx_error)

  @typedoc "Ok/Error tuple type"
  @type ok_error_tuple(ok, error) :: {:ok, ok} | {:error, error}

  @doc false
  defmacro __using__(opts) do
    quote do
      unquote(prelude(opts))
      unquote(base_defs())
      unquote(entry_defs())

      if Nebulex.Adapter.Queryable in behaviours do
        unquote(queryable_defs())
      end

      if Nebulex.Adapter.Persistence in behaviours do
        unquote(persistence_defs())
      end

      if Nebulex.Adapter.Transaction in behaviours do
        unquote(transaction_defs())
      end

      if Nebulex.Adapter.Stats in behaviours do
        unquote(stats_defs())
      end
    end
  end

  defp prelude(opts) do
    quote do
      @behaviour Nebulex.Cache

      {otp_app, adapter, behaviours} = Nebulex.Cache.Supervisor.compile_config(unquote(opts))

      @otp_app otp_app
      @adapter adapter
      @opts unquote(opts)
      @default_dynamic_cache @opts[:default_dynamic_cache] || __MODULE__
      @default_key_generator @opts[:default_key_generator] || Nebulex.Caching.SimpleKeyGenerator
      @before_compile adapter
    end
  end

  defp base_defs do
    quote do
      ## Config and metadata

      @impl true
      def config do
        {:ok, config} = Nebulex.Cache.Supervisor.runtime_config(__MODULE__, @otp_app, [])
        config
      end

      @impl true
      def __adapter__, do: @adapter

      @impl true
      def __default_key_generator__, do: @default_key_generator

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
    end
  end

  defp entry_defs do
    quote do
      alias Nebulex.Cache.Entry

      @impl true
      def fetch(key, opts \\ []) do
        Entry.fetch(get_dynamic_cache(), key, opts)
      end

      @impl true
      def fetch!(key, opts \\ []) do
        Entry.fetch!(get_dynamic_cache(), key, opts)
      end

      @impl true
      def get(key, default \\ nil, opts \\ []) do
        Entry.get(get_dynamic_cache(), key, default, opts)
      end

      @impl true
      def get!(key, default \\ nil, opts \\ []) do
        Entry.get!(get_dynamic_cache(), key, default, opts)
      end

      @impl true
      def get_all(keys, opts \\ []) do
        Entry.get_all(get_dynamic_cache(), keys, opts)
      end

      @impl true
      def get_all!(keys, opts \\ []) do
        Entry.get_all!(get_dynamic_cache(), keys, opts)
      end

      @impl true
      def put(key, value, opts \\ []) do
        Entry.put(get_dynamic_cache(), key, value, opts)
      end

      @impl true
      def put!(key, value, opts \\ []) do
        Entry.put!(get_dynamic_cache(), key, value, opts)
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
      def put_all!(entries, opts \\ []) do
        Entry.put_all!(get_dynamic_cache(), entries, opts)
      end

      @impl true
      def put_new_all(entries, opts \\ []) do
        Entry.put_new_all(get_dynamic_cache(), entries, opts)
      end

      @impl true
      def put_new_all!(entries, opts \\ []) do
        Entry.put_new_all!(get_dynamic_cache(), entries, opts)
      end

      @impl true
      def delete(key, opts \\ []) do
        Entry.delete(get_dynamic_cache(), key, opts)
      end

      @impl true
      def delete!(key, opts \\ []) do
        Entry.delete!(get_dynamic_cache(), key, opts)
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
      def exists?(key) do
        Entry.exists?(get_dynamic_cache(), key)
      end

      @impl true
      def get_and_update(key, fun, opts \\ []) do
        Entry.get_and_update(get_dynamic_cache(), key, fun, opts)
      end

      @impl true
      def get_and_update!(key, fun, opts \\ []) do
        Entry.get_and_update!(get_dynamic_cache(), key, fun, opts)
      end

      @impl true
      def update(key, initial, fun, opts \\ []) do
        Entry.update(get_dynamic_cache(), key, initial, fun, opts)
      end

      @impl true
      def update!(key, initial, fun, opts \\ []) do
        Entry.update!(get_dynamic_cache(), key, initial, fun, opts)
      end

      @impl true
      def incr(key, amount \\ 1, opts \\ []) do
        Entry.incr(get_dynamic_cache(), key, amount, opts)
      end

      @impl true
      def incr!(key, amount \\ 1, opts \\ []) do
        Entry.incr!(get_dynamic_cache(), key, amount, opts)
      end

      @impl true
      def decr(key, amount \\ 1, opts \\ []) do
        Entry.decr(get_dynamic_cache(), key, amount, opts)
      end

      @impl true
      def decr!(key, amount \\ 1, opts \\ []) do
        Entry.decr!(get_dynamic_cache(), key, amount, opts)
      end

      @impl true
      def ttl(key) do
        Entry.ttl(get_dynamic_cache(), key)
      end

      @impl true
      def ttl!(key) do
        Entry.ttl!(get_dynamic_cache(), key)
      end

      @impl true
      def expire(key, ttl) do
        Entry.expire(get_dynamic_cache(), key, ttl)
      end

      @impl true
      def expire!(key, ttl) do
        Entry.expire!(get_dynamic_cache(), key, ttl)
      end

      @impl true
      def touch(key) do
        Entry.touch(get_dynamic_cache(), key)
      end

      @impl true
      def touch!(key) do
        Entry.touch!(get_dynamic_cache(), key)
      end
    end
  end

  defp queryable_defs do
    quote do
      alias Nebulex.Cache.Queryable

      @impl true
      def all(query \\ nil, opts \\ []) do
        Queryable.all(get_dynamic_cache(), query, opts)
      end

      @impl true
      def all!(query \\ nil, opts \\ []) do
        Queryable.all!(get_dynamic_cache(), query, opts)
      end

      @impl true
      def count_all(query \\ nil, opts \\ []) do
        Queryable.count_all(get_dynamic_cache(), query, opts)
      end

      @impl true
      def count_all!(query \\ nil, opts \\ []) do
        Queryable.count_all!(get_dynamic_cache(), query, opts)
      end

      @impl true
      def delete_all(query \\ nil, opts \\ []) do
        Queryable.delete_all(get_dynamic_cache(), query, opts)
      end

      @impl true
      def delete_all!(query \\ nil, opts \\ []) do
        Queryable.delete_all!(get_dynamic_cache(), query, opts)
      end

      @impl true
      def stream(query \\ nil, opts \\ []) do
        Queryable.stream(get_dynamic_cache(), query, opts)
      end

      @impl true
      def stream!(query \\ nil, opts \\ []) do
        Queryable.stream!(get_dynamic_cache(), query, opts)
      end
    end
  end

  defp persistence_defs do
    quote do
      alias Nebulex.Cache.Persistence

      @impl true
      def dump(path, opts \\ []) do
        Persistence.dump(get_dynamic_cache(), path, opts)
      end

      @impl true
      def dump!(path, opts \\ []) do
        Persistence.dump!(get_dynamic_cache(), path, opts)
      end

      @impl true
      def load(path, opts \\ []) do
        Persistence.load(get_dynamic_cache(), path, opts)
      end

      @impl true
      def load!(path, opts \\ []) do
        Persistence.load!(get_dynamic_cache(), path, opts)
      end
    end
  end

  defp transaction_defs do
    quote do
      alias Nebulex.Cache.Transaction

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

  defp stats_defs do
    quote do
      alias Nebulex.Cache.Stats

      @impl true
      def stats do
        Stats.stats(get_dynamic_cache())
      end

      @impl true
      def stats! do
        Stats.stats!(get_dynamic_cache())
      end

      @impl true
      def dispatch_stats(opts \\ []) do
        Stats.dispatch_stats(get_dynamic_cache(), opts)
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
  Returns the default key generator applied only when using
  **"declarative annotation-based caching"** via `Nebulex.Caching`.

  Sometimes you may want to set a different key generator when using
  declarative caching. By default, the key generator is set to
  `Nebulex.Caching.SimpleKeyGenerator`. You can change the default
  key generator at compile time with:

      use Nebulex.Cache, default_key_generator: MyKeyGenerator

  See `Nebulex.Caching` and `Nebulex.Caching.KeyGenerator` for more information.
  """
  @callback __default_key_generator__ :: Nebulex.Caching.KeyGenerator.t()

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
  Fetches the value for a specific `key` in the cache.

  If the cache contains the given `key`, then its value is returned
  in the shape of `{:ok, value}`.

  If the cache does not contain `key`, `{:error, Nebulex.KeyError.t()}`
  is returned.

  Returns `{:error, Nebulex.Error.t()}` if any other error occurs while
  executing the command.

  ## Options

  See the "Shared options" section at the module documentation for more options.

  ## Example

      iex> MyCache.put("foo", "bar")
      :ok

      iex>  MyCache.fetch("foo")
      {:ok, "bar"}

      iex> {:error, %Nebulex.KeyError{key: "bar"}} = MyCache.fetch("bar")
      _error

  """
  @callback fetch(key, opts) :: ok_error_tuple(value, fetch_error_reason)

  @doc """
  Same as `c:fetch/2` but raises `Nebulex.KeyError` if the cache doesn't
  contain `key`, or `Nebulex.Error` if any other error occurs while executing
  the command.
  """
  @callback fetch!(key, opts) :: value

  @doc """
  Gets a value from cache where the key matches the given `key`.

  If the cache contains the given `key`, then its value is returned
  in the shape of `{:ok, value}`.

  If the cache does not contain `key`, `{:ok, default}` is returned.

  Returns `{:error, Nebulex.Error.t()}` if an error occurs while
  executing the command.

  ## Options

  See the "Shared options" section at the module documentation for more options.

  ## Example

      iex> MyCache.put("foo", "bar")
      :ok

      iex>  MyCache.get("foo")
      {:ok, "bar"}

      iex> MyCache.get(:inexistent)
      {:ok, nil}

      iex> MyCache.get(:inexistent, :default)
      {:ok, :default}

  """
  @callback get(key, default :: value, opts) :: ok_error_tuple(value)

  @doc """
  Same as `c:get/3` but raises an exception if an error occurs.
  """
  @callback get!(key, default :: value, opts) :: value

  @doc """
  Returns a map in the shape of `{:ok, map}` with the key-value pairs of all
  specified `keys`. For every key that does not hold a value or does not exist,
  it is ignored and not added into the returned map.

  Returns `{:error, reason}` if an error occurs while executing the command.

  ## Options

  See the "Shared options" section at the module documentation for more options.

  ## Example

      iex> MyCache.put_all([a: 1, c: 3])
      :ok

      iex> MyCache.get_all([:a, :b, :c])
      {:ok, %{a: 1, c: 3}}

  """
  @callback get_all(keys :: [key], opts) :: ok_error_tuple(map)

  @doc """
  Same as `c:get_all/2` but raises an exception if an error occurs.
  """
  @callback get_all!(keys :: [key], opts) :: map

  @doc """
  Puts the given `value` under `key` into the Cache.

  If `key` already holds an entry, it is overwritten. Any previous
  time to live associated with the key is discarded on successful
  `put` operation.

  Returns `:ok` if successful, or `{:error, reason}` if an error occurs.

  ## Options

    * `:ttl` - (positive integer or `:infinity`) Defines the time-to-live
      (or expiry time) for the given key  in **milliseconds**. Defaults
      to `:infinity`.

  See the "Shared options" section at the module documentation for more options.

  ## Example

      iex> MyCache.put("foo", "bar")
      :ok

  Putting entries with specific time-to-live:

      iex> MyCache.put("foo", "bar", ttl: 10_000)
      :ok

      iex> MyCache.put("foo", "bar", ttl: :timer.hours(1))
      :ok

      iex> MyCache.put("foo", "bar", ttl: :timer.minutes(1))
      :ok

      iex> MyCache.put("foo", "bar", ttl: :timer.seconds(1))
      :ok

  """
  @callback put(key, value, opts) :: :ok | error

  @doc """
  Same as `c:put/3` but raises an exception if an error occurs.
  """
  @callback put!(key, value, opts) :: :ok

  @doc """
  Puts the given `entries` (key/value pairs) into the cache. It replaces
  existing values with new values (just as regular `put`).

  Returns `:ok` if successful, or `{:error, reason}` if an error occurs.

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

  **NOTE:** Ideally, this operation should be atomic, so all given keys are
  put at once. But it depends purely on the adapter's implementation and the
  backend used internally by the adapter. Hence, it is recommended to review
  the adapter's documentation.
  """
  @callback put_all(entries, opts) :: :ok | error

  @doc """
  Same as `c:put_all/2` but raises an exception if an error occurs.
  """
  @callback put_all!(entries, opts) :: :ok

  @doc """
  Puts the given `value` under `key` into the cache, only if it does not
  already exist.

  Returns `{:ok, true}` if a value was set, otherwise, `{:ok, false}`
  is returned.

  Returns `{:error, reason}` if an error occurs.

  ## Options

    * `:ttl` - (positive integer or `:infinity`) Defines the time-to-live
      (or expiry time) for the given key  in **milliseconds**. Defaults
      to `:infinity`.

  See the "Shared options" section at the module documentation for more options.

  ## Example

      iex> MyCache.put_new("foo", "bar")
      {:ok, true}

      iex> MyCache.put_new("foo", "bar")
      {:ok, false}

  """
  @callback put_new(key, value, opts) :: ok_error_tuple(boolean)

  @doc """
  Same as `c:put_new/3` but raises an exception if an error occurs.
  """
  @callback put_new!(key, value, opts) :: boolean

  @doc """
  Puts the given `entries` (key/value pairs) into the `cache`. It will not
  perform any operation at all even if just a single key already exists.

  Returns `{:ok, true}` if all entries were successfully set, or `{:ok, false}`
  if no key was set (at least one key already existed).

  Returns `{:error, reason}` if an error occurs.

  ## Options

    * `:ttl` - (positive integer or `:infinity`) Defines the time-to-live
      (or expiry time) for the given key  in **milliseconds**. Defaults
      to `:infinity`.

  See the "Shared options" section at the module documentation for more options.

  ## Example

      iex> MyCache.put_new_all(apples: 3, bananas: 1)
      {:ok, true}

      iex> MyCache.put_new_all(%{apples: 3, oranges: 1}, ttl: 10_000)
      {:ok, false}

  **NOTE:** Ideally, this operation should be atomic, so all given keys are
  put at once. But it depends purely on the adapter's implementation and the
  backend used internally by the adapter. Hence, it is recommended to review
  the adapter's documentation.
  """
  @callback put_new_all(entries, opts) :: ok_error_tuple(boolean)

  @doc """
  Same as `c:put_new_all/2` but raises an exception if an error occurs.
  """
  @callback put_new_all!(entries, opts) :: boolean

  @doc """
  Alters the entry stored under `key`, but only if the entry already exists
  into the Cache.

  Returns `{:ok, true}` if a value was set, otherwise, `{:ok, false}`
  is returned.

  Returns `{:error, reason}` if an error occurs.

  ## Options

    * `:ttl` - (positive integer or `:infinity`) Defines the time-to-live
      (or expiry time) for the given key  in **milliseconds**. Defaults
      to `:infinity`.

  See the "Shared options" section at the module documentation for more options.

  ## Example

      iex> MyCache.replace("foo", "bar")
      {:ok, false}

      iex> MyCache.put_new("foo", "bar")
      {:ok, true}

      iex> MyCache.replace("foo", "bar2")
      {:ok, true}

  Update current value and TTL:

      iex> MyCache.replace("foo", "bar3", ttl: 10_000)
      {:ok, true}

  """
  @callback replace(key, value, opts) :: ok_error_tuple(boolean)

  @doc """
  Same as `c:replace/3` but raises an exception if an error occurs.
  """
  @callback replace!(key, value, opts) :: boolean

  @doc """
  Deletes the entry in cache for a specific `key`.

  Returns `{:error, reason}` if an error occurs.

  ## Options

  See the "Shared options" section at the module documentation for more options.

  ## Example

      iex> MyCache.put(:a, 1)
      :ok

      iex> MyCache.delete(:a)
      :ok

      iex> MyCache.get(:a)
      :ok

      iex> MyCache.delete(:inexistent)
      :ok

  """
  @callback delete(key, opts) :: :ok | error

  @doc """
  Same as `c:delete/2` but raises an exception if an error occurs.
  """
  @callback delete!(key, opts) :: :ok

  @doc """
  Removes and returns the value associated with `key` in the cache.

  If `key` is present in the cache, its value is removed and then returned
  in the shape of `{:ok, value}`.

  If `key` is not present in the cache, `{:error, Nebulex.KeyError.t()}`
  is returned.

  Returns `{:error, Nebulex.Error.t()}` if any other error occurs while
  executing the command.

  ## Options

  See the "Shared options" section at the module documentation for more options.

  ## Examples

      iex> MyCache.put(:a, 1)
      :ok

      iex> MyCache.take(:a)
      {:ok, 1}

      iex> {:error, %Nebulex.KeyError{key: :a}} = MyCache.take(:a)
      _error

  """
  @callback take(key, opts) :: ok_error_tuple(value, fetch_error_reason)

  @doc """
  Same as `c:take/2` but raises an exception if an error occurs.
  """
  @callback take!(key, opts) :: value

  @doc """
  Determines if the cache contains an entry for the specified `key`.

  More formally, returns `{:ok, true}` if the cache contains the given `key`.
  If the cache doesn't contain `key`, `{:ok, :false}` is returned.

  Returns `{:error, reason}` if an error occurs.

  ## Examples

      iex> MyCache.put(:a, 1)
      :ok

      iex> MyCache.exists?(:a)
      {:ok, true}

      iex> MyCache.exists?(:b)
      {:ok, false}

  """
  @callback exists?(key) :: ok_error_tuple(boolean)

  @doc """
  Increments the counter stored at `key` by the given `amount`, and returns
  the current count in the shape of `{:ok, count}`.

  If `amount < 0` (negative), the value is decremented by that `amount`
  instead.

  Returns `{:error, reason}` if an error occurs.

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
      {:ok, 1}

      iex> MyCache.incr(:a, 2)
      {:ok, 3}

      iex> MyCache.incr(:a, -1)
      {:ok, 2}

      iex> MyCache.incr(:missing_key, 2, default: 10)
      {:ok, 12}

  """
  @callback incr(key, amount :: integer, opts) :: ok_error_tuple(integer)

  @doc """
  Same as `c:incr/3` but raises an exception if an error occurs.
  """
  @callback incr!(key, amount :: integer, opts) :: integer

  @doc """
  Decrements the counter stored at `key` by the given `amount`, and returns
  the current count in the shape of `{:ok, count}`.

  If `amount < 0` (negative), the value is incremented by that `amount`
  instead (opposite to `incr/3`).

  Returns `{:error, reason}` if an error occurs.

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
      {:ok, -1}

      iex> MyCache.decr(:a, 2)
      {:ok, -3}

      iex> MyCache.decr(:a, -1)
      {:ok, -2}

      iex> MyCache.decr(:missing_key, 2, default: 10)
      {:ok, 8}

  """
  @callback decr(key, amount :: integer, opts) :: ok_error_tuple(integer)

  @doc """
  Same as `c:decr/3` but raises an exception if an error occurs.
  """
  @callback decr!(key, amount :: integer, opts) :: integer

  @doc """
  Returns the remaining time-to-live for the given `key`.

  If `key` is present in the cache, then its remaining TTL is returned
  in the shape of `{:ok, ttl}`.

  If `key` is not present in the cache, `{:error, Nebulex.KeyError.t()}`
  is returned.

  Returns `{:error, Nebulex.Error.t()}` if any other error occurs while
  executing the command.

  ## Examples

      iex> MyCache.put(:a, 1, ttl: 5000)
      :ok

      iex> MyCache.put(:b, 2)
      :ok

      iex> MyCache.ttl(:a)
      {:ok, _remaining_ttl}

      iex> MyCache.ttl(:b)
      {:ok, :infinity}

      iex> {:error, %Nebulex.KeyError{key: :c}} = MyCache.ttl(:c)
      _error

  """
  @callback ttl(key) :: ok_error_tuple(timeout, fetch_error_reason)

  @doc """
  Same as `c:ttl/1` but raises an exception if an error occurs.
  """
  @callback ttl!(key) :: timeout

  @doc """
  Returns `{:ok, true}` if the given `key` exists and the new `ttl` was
  successfully updated, otherwise, `{:ok, false}` is returned.

  Returns `{:error, reason}` if an error occurs.

  ## Examples

      iex> MyCache.put(:a, 1)
      :ok

      iex> MyCache.expire(:a, 5)
      {:ok, true}

      iex> MyCache.expire(:a, :infinity)
      {:ok, true}

      iex> MyCache.expire(:b, 5)
      {:ok, false}

  """
  @callback expire(key, ttl :: timeout) :: ok_error_tuple(boolean)

  @doc """
  Same as `c:expire/2` but raises an exception if an error occurs.
  """
  @callback expire!(key, ttl :: timeout) :: boolean

  @doc """
  Returns `{:ok, true}` if the given `key` exists and the last access time was
  successfully updated, otherwise, `{:ok, false}` is returned.

  Returns `{:error, reason}` if an error occurs.

  ## Examples

      iex> MyCache.put(:a, 1)
      :ok

      iex> MyCache.touch(:a)
      {:ok, true}

      iex> MyCache.ttl(:b)
      {:ok, false}

  """
  @callback touch(key) :: ok_error_tuple(boolean)

  @doc """
  Same as `c:touch/1` but raises an exception if an error occurs.
  """
  @callback touch!(key) :: boolean

  @doc """
  Gets the value from `key` and updates it, all in one pass.

  `fun` is called with the current cached value under `key` (or `nil` if `key`
  hasn't been cached) and must return a two-element tuple: the current value
  (the retrieved value, which can be operated on before being returned) and
  the new value to be stored under `key`. `fun` may also return `:pop`, which
  means the current value shall be removed from Cache and returned.

  This function returns:

    * `{:ok, {current_value, new_value}}` - The `current_value` is the current
      cached value and `new_value` the updated one returned by `fun`.

    * `{:error, reason}` - an error occurred while executing the command.

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
      {:ok, {nil, "value!"}}

  Update existing key:

      iex> MyCache.get_and_update(:a, fn current_value ->
      ...>   {current_value, "new value!"}
      ...> end)
      {:ok, {"value!", "new value!"}}

  Pop/remove value if exist:

      iex> MyCache.get_and_update(:a, fn _ -> :pop end)
      {:ok, {"new value!", nil}}

  Pop/remove nonexistent key:

      iex> MyCache.get_and_update(:b, fn _ -> :pop end)
      {:ok, {nil, nil}}

  """
  @callback get_and_update(key, (value -> {current_value, new_value} | :pop), opts) ::
              ok_error_tuple({current_value, new_value})
            when current_value: value, new_value: value

  @doc """
  Same as `c:get_and_update/3` but raises an exception if an error occurs.
  """
  @callback get_and_update!(key, (value -> {current_value, new_value} | :pop), opts) ::
              {current_value, new_value}
            when current_value: value, new_value: value

  @doc """
  Updates the cached `key` with the given function.

  If` key` is present in the cache, then the existing value is passed to `fun`
  and its result is used as the updated value of `key`. If `key` is not present
  in the cache, `default` is inserted as the value of `key`. The default value
  will not be passed through the update function.

  This function returns:

    * `{:ok, value}` - The value associated to the given `key` has been updated.

    * `{:error, reason}` - an error occurred while executing the command.

  ## Options

    * `:ttl` - (positive integer or `:infinity`) Defines the time-to-live
      (or expiry time) for the given key  in **milliseconds**. Defaults
      to `:infinity`.

  See the "Shared options" section at the module documentation for more options.

  ## Examples

      iex> MyCache.update(:a, 1, &(&1 * 2))
      {:ok, 1}

      iex> MyCache.update(:a, 1, &(&1 * 2))
      {:ok, 2}

  """
  @callback update(key, initial :: value, (value -> value), opts) :: ok_error_tuple(value)

  @doc """
  Same as `c:update/4` but raises an exception if an error occurs.
  """
  @callback update!(key, initial :: value, (value -> value), opts) :: value

  ## Nebulex.Adapter.Queryable

  @optional_callbacks all: 2,
                      all!: 2,
                      count_all: 2,
                      count_all!: 2,
                      delete_all: 2,
                      delete_all!: 2,
                      stream: 2,
                      stream!: 2

  @doc """
  Fetches all entries from cache matching the given `query`.

  This function returns:

    * `{:ok, matched_entries}` - the query is valid, then it is executed
      and the matched entries are returned.

    * `{:error, Nebulex.QueryError.t()}` - the query validation failed.

    * `{:error, reason}` - an error occurred while executing the command.

  ## Query values

  There are two types of query values. The ones shared and implemented
  by all adapters and the ones that are adapter specific.

  ### Common queries

  The following query values are shared and/or supported for all adapters:

    * `nil` - Matches all entries cached entries. In case of `c:all/2`
      for example, it returns a list with all cached entries based on
      the `:return` option.

  ### Adapter-specific queries

  The `query` value depends entirely on the adapter implementation; it could
  any term. Therefore, it is highly recommended to see adapters' documentation
  for more information about supported queries. For example, the built-in
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
      {:ok, [1, 2, 3, 4, 5]}

  Fetch all entries and return values:

      iex> MyCache.all(nil, return: :value)
      {:ok, [2, 4, 6, 8, 10]}

  Fetch all entries and return them as key/value pairs:

      iex> MyCache.all(nil, return: {:key, :value})
      {:ok, [{1, 2}, {2, 4}, {3, 6}, {4, 8}, {5, 10}]}

  Fetch all entries that match with the given query assuming we are using
  `Nebulex.Adapters.Local` adapter:

      iex> query = [{{:_, :"$1", :"$2", :_, :_}, [{:>, :"$2", 5}], [:"$1"]}]
      iex> MyCache.all(query)
      {:ok, [3, 4, 5]}

  ## Query

  Query spec is defined by the adapter, hence, it is recommended to review
  adapters documentation. For instance, the built-in `Nebulex.Adapters.Local`
  adapter supports `nil | :unexpired | :expired | :ets.match_spec()` as query
  value.

  ## Examples

  Additional built-in queries for `Nebulex.Adapters.Local` adapter:

      iex> {:ok, unexpired} = MyCache.all(:unexpired)
      iex> {:ok, expired} = MyCache.all(:expired)

  If we are using Nebulex.Adapters.Local adapter, the stored entry tuple
  `{:entry, key, value, touched, ttl}`, then the match spec could be
  something like:

      iex> spec = [
      ...>   {{:entry, :"$1", :"$2", :_, :_},
      ...>   [{:>, :"$2", 5}], [{{:"$1", :"$2"}}]}
      ...> ]
      iex> MyCache.all(spec)
      {:ok, [{3, 6}, {4, 8}, {5, 10}]}

  The same previous query but using `Ex2ms`:

      iex> import Ex2ms
      Ex2ms

      iex> spec =
      ...>   fun do
      ...>     {_. key, value, _, _} when value > 5 -> {key, value}
      ...>   end

      iex> MyCache.all(spec)
      {:ok, [{3, 6}, {4, 8}, {5, 10}]}

  """
  @callback all(query :: term, opts) :: ok_error_tuple([term], query_error_reason)

  @doc """
  Same as `c:all/2` but raises an exception if an error occurs.
  """
  @callback all!(query :: term, opts) :: [any]

  @doc """
  Similar to `c:all/2` but returns a lazy enumerable that emits all entries
  from the cache matching the given `query`.

  This function returns:

    * `{:ok, Enum.t()}` - the query is valid, then the stream is returned.

    * `{:error, Nebulex.QueryError.t()}` - the query validation failed.

    * `{:error, reason}` - an error occurred while executing the command.

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

      iex> {:ok, stream} = MyCache.stream()
      iex> Enum.to_list(stream)
      [1, 2, 3, 4, 5]

  Stream all entries and return values:

      iex> {:ok, stream} = MyCache.stream(nil, return: :value, page_size: 3)
      iex> Enum.to_list(stream)
      [2, 4, 6, 8, 10]

  Stream all entries and return them as key/value pairs:

      iex> {:ok, stream} = MyCache.stream(nil, return: {:key, :value})
      iex> Enum.to_list(stream)
      [{1, 2}, {2, 4}, {3, 6}, {4, 8}, {5, 10}]

  Additional built-in queries for `Nebulex.Adapters.Local` adapter:

      iex> {:ok, unexpired_stream} = MyCache.stream(:unexpired)
      iex> {:ok, expired_stream} = MyCache.stream(:expired)

  If we are using Nebulex.Adapters.Local adapter, the stored entry tuple
  `{:entry, key, value, touched, ttl}`, then the match spec could be
  something like:

      iex> spec = [
      ...>   {{:entry, :"$1", :"$2", :_, :_},
      ...>   [{:>, :"$2", 5}], [{{:"$1", :"$2"}}]}
      ...> ]
      iex> {:ok, stream} = MyCache.stream(spec, page_size: 100)
      iex> Enum.to_list(stream)
      [{3, 6}, {4, 8}, {5, 10}]

  The same previous query but using `Ex2ms`:

      iex> import Ex2ms
      Ex2ms

      iex> spec =
      ...>   fun do
      ...>     {_, key, value, _, _} when value > 5 -> {key, value}
      ...>   end

      iex> {:ok, stream} = MyCache.stream(spec, page_size: 100)
      iex> Enum.to_list(stream)
      [{3, 6}, {4, 8}, {5, 10}]

  """
  @callback stream(query :: term, opts) :: ok_error_tuple(Enum.t(), query_error_reason)

  @doc """
  Same as `c:stream/2` but raises an exception if an error occurs.
  """
  @callback stream!(query :: term, opts) :: Enum.t()

  @doc """
  Deletes all entries matching the given `query`. If `query` is `nil`,
  then all entries in the cache are deleted.

  This function returns:

    * `{:ok, deleted_count}` - the query is valid, then the matched entries
      are deleted and the `deleted_count` is returned.

    * `{:error, Nebulex.QueryError.t()}` - the query validation failed.

    * `{:error, reason}` - an error occurred while executing the command.

  ## Query values

  See `c:all/2` callback for more information about the query values.

  ## Options

  See the "Shared options" section at the module documentation for more options.

  ## Example

  Populate the cache with some entries:

      iex> :ok = Enum.each(1..5, &MyCache.put(&1, &1 * 2))

  Delete all (with default params):

      iex> MyCache.delete_all()
      {:ok, 5}

  Delete all entries that match with the given query assuming we are using
  `Nebulex.Adapters.Local` adapter:

      iex> query = [{{:_, :"$1", :"$2", :_, :_}, [{:>, :"$2", 5}], [true]}]
      iex> {:ok, deleted_count} = MyCache.delete_all(query)

  See `c:all/2` for more examples, the same applies to `c:delete_all/2`.
  """
  @callback delete_all(query :: term, opts) :: ok_error_tuple(non_neg_integer, query_error_reason)

  @doc """
  Same as `c:delete_all/2` but raises an exception if an error occurs.
  """
  @callback delete_all!(query :: term, opts) :: integer

  @doc """
  Counts all entries in cache matching the given `query`.

  If `query` is `nil` (the default), then the total number of
  cached entries is returned.

  This function returns:

    * `{:ok, count}` - the query is valid, then the `count` of the
      matched entries returned.

    * `{:error, Nebulex.QueryError.t()}` - the query validation failed.

    * `{:error, reason}` - an error occurred while executing the command.

  ## Query values

  See `c:all/2` callback for more information about the query values.

  ## Example

  Populate the cache with some entries:

      iex> :ok = Enum.each(1..5, &MyCache.put(&1, &1 * 2))

  Count all entries in cache:

      iex> MyCache.count_all()
      {:ok, 5}

  Count all entries that match with the given query assuming we are using
  `Nebulex.Adapters.Local` adapter:

      iex> query = [{{:_, :"$1", :"$2", :_, :_}, [{:>, :"$2", 5}], [true]}]
      iex> {:ok, count} = MyCache.count_all(query)

  See `c:all/2` for more examples, the same applies to `c:count_all/2`.
  """
  @callback count_all(query :: term, opts) :: ok_error_tuple(non_neg_integer, query_error_reason)

  @doc """
  Same as `c:count_all/2` but raises an exception if an error occurs.
  """
  @callback count_all!(query :: term, opts) :: integer

  ## Nebulex.Adapter.Persistence

  @optional_callbacks dump: 2, dump!: 2, load: 2, load!: 2

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
      iex> MyCache.put_all(entries)
      :ok

  Dump cache to a file:

      iex> MyCache.dump("my_cache")
      :ok

  """
  @callback dump(path :: Path.t(), opts) :: :ok | error

  @doc """
  Same as `c:dump/2` but raises an exception if an error occurs.
  """
  @callback dump!(path :: Path.t(), opts) :: :ok

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
      iex> MyCache.put_all(entries)
      :ok

  Dump cache to a file:

      iex> MyCache.dump("my_cache")
      :ok

  Load the cache from a file:

      iex> MyCache.load("my_cache")
      :ok

  """
  @callback load(path :: Path.t(), opts) :: :ok | error

  @doc """
  Same as `c:load/2` but raises an exception if an error occurs.
  """
  @callback load!(path :: Path.t(), opts) :: :ok

  ## Nebulex.Adapter.Transaction

  @optional_callbacks transaction: 2, in_transaction?: 0

  @doc """
  Runs the given function inside a transaction.

  A successful transaction returns the value returned by the function wrapped
  in a tuple as `{:ok, value}`.

  In case the transaction cannot be executed, then `{:error, reason}` is
  returned.

  If an unhandled error/exception occurs, the error will bubble up from the
  transaction function.

  If `transaction/2` is called inside another transaction, the function is
  simply executed without wrapping the new transaction call in any way.

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
  @callback transaction(opts, function :: fun) :: ok_error_tuple(term, term)

  @doc """
  Returns `{:ok, true}` if the current process is inside a transaction,
  otherwise, `{:ok, false}` is returned.

  Returns `{:error, reason}` if an error occurs.

  ## Examples

      MyCache.in_transaction?
      #=> {:ok, false}

      MyCache.transaction(fn ->
        MyCache.in_transaction? #=> {:ok, true}
      end)

  """
  @callback in_transaction?() :: ok_error_tuple(boolean)

  ## Nebulex.Adapter.Stats

  @optional_callbacks stats: 0, stats!: 0, dispatch_stats: 1

  @doc """
  Returns current stats values.

  This function returns:

    * `{:ok, Nebulex.Stats.t()}` - stats are enabled and available
      for the cache.

    * `{:error, reason}` - an error occurred while executing the command.

  ## Example

      iex> MyCache.stats()
      {:ok,
       %Nebulex.Stats{
         measurements: %{
           evictions: 0,
           expirations: 0,
           hits: 0,
           misses: 0,
           updates: 0,
           writes: 0
         },
         metadata: %{}
       }}

  """
  @callback stats() :: ok_error_tuple(Nebulex.Stats.t())

  @doc """
  Same as `c:stats/0` but raises an exception if an error occurs.
  """
  @callback stats!() :: Nebulex.Stats.t()

  @doc """
  Emits a telemetry event when called with the current stats count.

  Returns `{:error, reason}` if an error occurs.

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
  @callback dispatch_stats(opts) :: :ok | error
end
