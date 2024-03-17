defmodule Nebulex.Cache do
  @moduledoc """
  Cache abstraction layer inspired by
  [Ecto](https://github.com/elixir-ecto/ecto).

  A cache maps to an underlying in-memory storage controlled by the adapter.
  For example, Nebulex ships with an adapter that implements a local
  generational cache.

  The cache expects the `:otp_app` and `:adapter` as options when used.
  The `:otp_app` should point to an OTP application with the cache
  configuration. See the compile time options for more information:

  #{Nebulex.Cache.Options.compile_options_docs()}

  For example, the cache:

      defmodule MyApp.Cache do
        use Nebulex.Cache,
          otp_app: :my_app,
          adapter: Nebulex.Adapters.Local
      end

  Could be configured with:

      config :my_app, MyApp.Cache,
        gc_interval: :timer.hours(12),
        max_size: 1_000_000,
        allocated_memory: 2_000_000_000,
        gc_cleanup_min_timeout: :timer.seconds(10),
        gc_cleanup_max_timeout: :timer.minutes(10)

  Most of the configuration that goes into the `config` is specific
  to the adapter. For this particular example, you can check
  [`Nebulex.Adapters.Local`][local_adapter] for more information.
  Despite this, the following configuration values are shared
  across all adapters:

  #{Nebulex.Cache.Options.start_link_options_docs()}

  [local_adapter]: https://hexdocs.pm/nebulex/Nebulex.Adapters.Local.html

  ## Shared options

  All of the cache functions outlined in this module accept the following
  options:

  #{Nebulex.Cache.Options.runtime_shared_options_docs()}

  > #### Adapter-specific options {: .info}
  >
  > In addition to the shared options, each adapter can define its
  > specific options. Therefore, Nebulex recommends reviewing the
  > adapter's documentation.

  ## Telemetry events

  There are two types of telemetry events. The emitted by Nebulex and the ones
  that are adapter specific. The ones emitted by Nebulex are divided into two
  categories: cache lifecycle events and cache command events. Let us take a
  closer look at each of them.

  ### Cache lifecycle events

  All Nebulex caches emit the following events:

    * `[:nebulex, :cache, :init]` - It is dispatched whenever a cache starts.
      The only measurement is the current system time in native units from
      calling: `System.system_time()`. The `:opts` key in the metadata
      contains all initialization options.

      * Measurement: `%{system_time: integer()}`
      * Metadata: `%{cache: module(), name: atom(), opts: keyword()}`

  ### Cache command events

  When the option `:telemetry` is set to `true` (the default), Nebulex will
  emit Telemetry span events for each cache command, and those will use the
  `:telemetry_prefix` outlined above, which defaults to `[:nebulex, :cache]`.

  For instance, to receive all events published for the cache `MyApp.Cache`,
  one could define a module:

      defmodule MyApp.Telemetry do
        def handle_event(
              [:nebulex, :cache, :command, event],
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

  Then, in the `Application.start/2` callback, attach the handler to the events
  using a unique handler id:

      :telemetry.attach_many(
        "my-app-handler-id",
        [
          [:nebulex, :cache, :command, :start],
          [:nebulex, :cache, :command, :stop],
          [:nebulex, :cache, :command, :exception]
        ],
        &MyApp.Telemetry.handle_event/4,
        :no_config
      )

  See the [telemetry documentation](https://hexdocs.pm/telemetry/)
  for more information.

  The following are the events you should expect from Nebulex. All examples
  below consider a cache named `MyApp.Cache`:

  #### `[:nebulex, :cache, :command, :start]`

  This event is emitted before a cache command is executed.

  The `:measurements` map will include the following:

    * `:system_time` - The current system time in native units from calling:
      `System.system_time()`.

  A Telemetry `:metadata` map including the following fields:

    * `:adapter_meta` - The adapter metadata.
    * `:command` - The name of the invoked adapter's command.
    * `:args` - The arguments passed to the invoked adapter, except for the
      first one, since the adapter's metadata is available in the event's
      metadata.
    * `:extra_metadata` - Additional metadata through the runtime option
      `:telemetry_metadata.`

  #### `[:nebulex, :cache, :command, :stop]`

  This event is emitted after a cache command is executed.

  The `:measurements` map will include the following:

    * `:duration` - The time spent executing the cache command. The measurement
      is given in the `:native` time unit. You can read more about it in the
      docs for `System.convert_time_unit/3`.

  A Telemetry `:metadata` map including the following fields:

    * `:adapter_meta` - The adapter metadata.
    * `:command` - The name of the invoked adapter's command.
    * `:args` - The arguments passed to the invoked adapter, except for the
      first one, since the adapter's metadata is available in the event's
      metadata.
    * `:extra_metadata` - Additional metadata through the runtime option
      `:telemetry_metadata.`
    * `:result` - The command's result.

  #### `[:nebulex, :cache, :command, :exception]`

  This event is emitted when an error or exception occurs during the
  cache command execution.

  The `:measurements` map will include the following:

    * `:duration` - The time spent executing the cache command. The measurement
      is given in the `:native` time unit. You can read more about it in the
      docs for `System.convert_time_unit/3`.

  A Telemetry `:metadata` map including the following fields:

    * `:adapter_meta` - The adapter metadata.
    * `:command` - The name of the invoked adapter's command.
    * `:args` - The arguments passed to the invoked adapter, except for the
      first one, since the adapter's metadata is available in the event's
      metadata.
    * `:extra_metadata` - Additional metadata through the runtime option
      `:telemetry_metadata.`
    * `:kind` - The type of the error: `:error`, `:exit`, or `:throw`.
    * `:reason` - The reason of the error.
    * `:stacktrace` - Exception's stack trace.

  ### Adapter-specific events

  Regardless of whether Nebulex emits the telemetry events outlined above or
  not, the adapters can and are free to expose their own, but they will be
  out of Nebulex's scope. Therefore, if you are interested in using specific
  adapter events, you should review the adapters' documentation.

  ## Dynamic caches

  Nebulex allows you to start multiple processes from the same cache module.
  This feature is typically useful when you want to have different cache
  instances but access them through the same cache module.

  When you list a cache in your supervision tree, such as `MyApp.Cache`, it will
  start a supervision tree with a process named `MyApp.Cache` under the hood.
  By default, the process has the same name as the cache module. Hence, whenever
  you invoke a function in `MyApp.Cache`, such as `MyApp.Cache.put/3`, Nebulex
  will execute the command in the cache process named `MyApp.Cache`.

  However, with Nebulex, you can start multiple processes from the same cache.
  The only requirement is that they must have different process names, like
  this:

      children = [
        MyApp.Cache,
        {MyApp.Cache, name: MyApp.UsersCache}
      ]

  Now you have two cache instances running: one is named `MyApp.Cache`, and the
  other one is named `MyApp.UsersCache`. You can tell Nebulex which process you
  want to use in your cache operations by calling:

      MyApp.Cache.put_dynamic_cache(MyApp.Cache)
      MyApp.Cache.put_dynamic_cache(MyApp.UsersCache)

  Once you call `MyApp.Cache.put_dynamic_cache(name)`, all invocations made on
  `MyApp.Cache` will use the cache instance denoted by `name`.

  Nebulex also provides a handy function for invoking commands using dynamic
  caches: `c:with_dynamic_cache/2`.

      MyApp.Cache.with_dynamic_cache(MyApp.UsersCache, fn ->
        # all commands here will use MyApp.UsersCache
        MyApp.Cache.put("u1", "joe")
        ...
      end)

  While these functions are handy, you may want to have the ability to pass
  the dynamic cache directly to the command, avoiding the boilerplate logic
  of using `c:put_dynamic_cache/1` or `c:with_dynamic_cache/2`. From **v3.0**,
  all Cache API commands expose an extended callback version that admits a
  dynamic cache at the first argument, so you can directly interact with a
  cache instance.

      MyApp.Cache.put(MyApp.UsersCache, "u1", "joe", ttl: :timer.hours(1))
      MyApp.Cache.get(MyApp.UsersCache, "u1", nil, [])
      MyApp.Cache.delete(MyApp.UsersCache, "u1", [])

  This is another handy way to work with multiple cache instances through
  the same cache module.

  ## Distributed topologies

  One of the goals of Nebulex is also to provide the ability to set up
  distributed cache topologies, but this feature will depend on the adapters.
  However, there are available adapters already for this:

    * `Nebulex.Adapters.Partitioned` - Partitioned cache topology.
    * `Nebulex.Adapters.Replicated` - Replicated cache topology.
    * `Nebulex.Adapters.Multilevel` - Multi-level distributed cache topology.

  These adapters work more as wrappers for an existing local adapter and provide
  the distributed topology on top of it. You can optionally set the adapter for
  the primary cache storage with the option `:primary_storage_adapter`. Defaults
  to `Nebulex.Adapters.Local`. See adapters documentation for information.
  """

  @typedoc "Cache type"
  @type t() :: module()

  @typedoc "Cache entry key"
  @type key() :: any()

  @typedoc "Cache entry value"
  @type value() :: any()

  @typedoc "Dynamic cache value"
  @type dynamic_cache() :: atom() | pid()

  @typedoc "Cache entries"
  @type entries() :: map() | [{key(), value()}]

  @typedoc "Cache action options"
  @type opts() :: keyword()

  @typedoc "The data type for a query spec"
  @type query_spec() :: keyword()

  @typedoc "Specification key for the item(s) to include in the returned info"
  @type info_spec() :: :all | atom() | [atom()]

  @typedoc "The type for the info item's value"
  @type info_item() :: any()

  @typedoc "Info map"
  @type info_map() :: %{optional(atom()) => any()}

  @typedoc "The data type for the cache information"
  @type info_data() :: info_map() | info_item()

  @typedoc "Proxy type for generic Nebulex error"
  @type nbx_error_reason() :: Nebulex.Error.t()

  @typedoc "Fetch error reason"
  @type fetch_error_reason() :: Nebulex.KeyError.t() | nbx_error_reason()

  @typedoc "Common error type"
  @type error_tuple() :: error_tuple(nbx_error_reason())

  @typedoc "Error type for the given reason"
  @type error_tuple(reason) :: {:error, reason}

  @typedoc "Ok/Error tuple with default error reasons"
  @type ok_error_tuple(ok) :: ok_error_tuple(ok, nbx_error_reason())

  @typedoc "Ok/Error type"
  @type ok_error_tuple(ok, error) :: {:ok, ok} | {:error, error}

  ## API

  import __MODULE__.Impl

  @doc false
  defmacro __using__(opts) do
    quote do
      unquote(prelude(opts))
      unquote(base_defs())
      unquote(kv_defs())

      if Nebulex.Adapter.Queryable in behaviours do
        unquote(queryable_defs())
      end

      if Nebulex.Adapter.Persistence in behaviours do
        unquote(persistence_defs())
      end

      if Nebulex.Adapter.Transaction in behaviours do
        unquote(transaction_defs())
      end

      if Nebulex.Adapter.Info in behaviours do
        unquote(info_defs())
      end
    end
  end

  defp prelude(opts) do
    quote do
      @behaviour Nebulex.Cache

      {otp_app, adapter, behaviours, opts} = Nebulex.Cache.Supervisor.compile_config(unquote(opts))

      @otp_app otp_app
      @adapter adapter
      @opts opts
      @default_dynamic_cache @opts[:default_dynamic_cache] || __MODULE__

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
      def stop(opts \\ []) do
        stop(get_dynamic_cache(), opts)
      end

      @impl true
      def stop(name, opts) do
        Supervisor.stop(name, :normal, Keyword.get(opts, :timeout, 5000))
      end

      # Iniline common instructions
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
    end
  end

  defp kv_defs do
    quote do
      alias Nebulex.Cache.KV

      defcacheapi fetch(key, opts \\ []), to: KV

      defcacheapi fetch!(key, opts \\ []), to: KV

      defcacheapi get(key, default \\ nil, opts \\ []), to: KV

      defcacheapi get!(key, default \\ nil, opts \\ []), to: KV

      defcacheapi put(key, value, opts \\ []), to: KV

      defcacheapi put!(key, value, opts \\ []), to: KV

      defcacheapi put_new(key, value, opts \\ []), to: KV

      defcacheapi put_new!(key, value, opts \\ []), to: KV

      defcacheapi replace(key, value, opts \\ []), to: KV

      defcacheapi replace!(key, value, opts \\ []), to: KV

      defcacheapi put_all(entries, opts \\ []), to: KV

      defcacheapi put_all!(entries, opts \\ []), to: KV

      defcacheapi put_new_all(entries, opts \\ []), to: KV

      defcacheapi put_new_all!(entries, opts \\ []), to: KV

      defcacheapi delete(key, opts \\ []), to: KV

      defcacheapi delete!(key, opts \\ []), to: KV

      defcacheapi take(key, opts \\ []), to: KV

      defcacheapi take!(key, opts \\ []), to: KV

      defcacheapi has_key?(key, opts \\ []), to: KV

      defcacheapi get_and_update(key, fun, opts \\ []), to: KV

      defcacheapi get_and_update!(key, fun, opts \\ []), to: KV

      defcacheapi update(key, initial, fun, opts \\ []), to: KV

      defcacheapi update!(key, initial, fun, opts \\ []), to: KV

      defcacheapi incr(key, amount \\ 1, opts \\ []), to: KV

      defcacheapi incr!(key, amount \\ 1, opts \\ []), to: KV

      defcacheapi decr(key, amount \\ 1, opts \\ []), to: KV

      defcacheapi decr!(key, amount \\ 1, opts \\ []), to: KV

      defcacheapi ttl(key, opts \\ []), to: KV

      defcacheapi ttl!(key, opts \\ []), to: KV

      defcacheapi expire(key, ttl, opts \\ []), to: KV

      defcacheapi expire!(key, ttl, opts \\ []), to: KV

      defcacheapi touch(key, opts \\ []), to: KV

      defcacheapi touch!(key, opts \\ []), to: KV
    end
  end

  defp queryable_defs do
    quote do
      alias Nebulex.Cache.Queryable

      defcacheapi get_all(query_spec \\ [], opts \\ []), to: Queryable

      defcacheapi get_all!(query_spec \\ [], opts \\ []), to: Queryable

      defcacheapi count_all(query_spec \\ [], opts \\ []), to: Queryable

      defcacheapi count_all!(query_spec \\ [], opts \\ []), to: Queryable

      defcacheapi delete_all(query_spec \\ [], opts \\ []), to: Queryable

      defcacheapi delete_all!(query_spec \\ [], opts \\ []), to: Queryable

      defcacheapi stream(query_spec \\ [], opts \\ []), to: Queryable

      defcacheapi stream!(query_spec \\ [], opts \\ []), to: Queryable
    end
  end

  defp persistence_defs do
    quote do
      alias Nebulex.Cache.Persistence

      defcacheapi dump(path, opts \\ []), to: Persistence

      defcacheapi dump!(path, opts \\ []), to: Persistence

      defcacheapi load(path, opts \\ []), to: Persistence

      defcacheapi load!(path, opts \\ []), to: Persistence
    end
  end

  defp transaction_defs do
    quote do
      alias Nebulex.Cache.Transaction

      defcacheapi transaction(fun, opts \\ []), to: Transaction

      defcacheapi in_transaction?(opts \\ []), to: Transaction
    end
  end

  defp info_defs do
    quote do
      alias Nebulex.Cache.Info

      defcacheapi info(spec \\ :all, opts \\ []), to: Info

      defcacheapi info!(spec \\ :all, opts \\ []), to: Info
    end
  end

  ## User callbacks

  @optional_callbacks init: 1

  @doc """
  A callback executed when the cache starts or when configuration is read.
  """
  @doc group: "User callbacks"
  @callback init(config :: keyword) :: {:ok, keyword} | :ignore

  ## Nebulex.Adapter

  @doc """
  Returns the adapter tied to the cache.
  """
  @doc group: "Runtime API"
  @callback __adapter__ :: Nebulex.Adapter.t()

  @doc """
  Returns the adapter configuration stored in the `:otp_app` environment.

  If the `c:init/1` callback is implemented in the cache, it will be invoked.
  """
  @doc group: "Runtime API"
  @callback config() :: keyword()

  @doc """
  Starts a supervision and return `{:ok, pid}` or just `:ok` if nothing
  needs to be done.

  Returns `{:error, {:already_started, pid}}` if the cache is already
  started or `{:error, term}` in case anything else goes wrong.

  ## Options

  See the configuration in the moduledoc for options shared between adapters,
  for adapter-specific configuration see the adapter's documentation.
  """
  @doc group: "Runtime API"
  @callback start_link(opts()) ::
              {:ok, pid()}
              | {:error, {:already_started, pid()}}
              | {:error, any()}

  @doc """
  Shuts down the cache.

  ## Options

    `:timeout` - It is an integer that specifies how many milliseconds to wait
    for the cache supervisor process to terminate, or the atom `:infinity` to
    wait indefinitely. Defaults to `5000`. See `Supervisor.stop/3`.

  See the ["Shared options"](#module-shared-options) section in the module
  documentation for more options.
  """
  @doc group: "Runtime API"
  @callback stop(opts()) :: :ok

  @doc """
  Same as `c:stop/1` but stops the cache instance given in the first argument
  `dynamic_cache`.

  See the ["Dynamic caches"](#module-dynamic-caches) section in the
  module documentation for more information.
  """
  @doc group: "Runtime API"
  @callback stop(dynamic_cache(), opts()) :: :ok

  @doc """
  Returns the atom name or pid of the current cache
  (based on Ecto dynamic repo).

  See also `c:put_dynamic_cache/1`.
  """
  @doc group: "Runtime API"
  @callback get_dynamic_cache() :: dynamic_cache()

  @doc """
  Sets the dynamic cache to be used in further commands
  (based on Ecto dynamic repo).

  There are cases where you may want to have different cache instances but
  access them through the same cache module. By default, when you call
  `MyApp.Cache.start_link/1`, it will start a cache with the name
  `MyApp.Cache`. But it is also possible to start multiple caches by using
  a different name for each of them:

      MyApp.Cache.start_link(name: :cache1)
      MyApp.Cache.start_link(name: :cache2)

  You can also start caches without names by explicitly setting the name
  to `nil`:

      MyApp.Cache.start_link(name: nil)

  > **NOTE:** There may be adapters requiring the `:name` option anyway,
    therefore, it is highly recommended to see the adapter's documentation
    you want to use.

  All operations through `MyApp.Cache` are sent by default to the cache named
  `MyApp.Cache`. But you can change the default cache at compile-time:

      use Nebulex.Cache, default_dynamic_cache: :cache_name

  Or anytime at runtime by calling `put_dynamic_cache/1`:

      MyApp.Cache.put_dynamic_cache(:another_cache_name)

  From this moment on, all future commands performed by the current process
  will run on `:another_cache_name`.

  Additionally, all cache commands optionally support passing the wanted
  dynamic cache (name or PID) as the first argument so you can o directly
  interact with a cache instance. See the
  ["Dynamic caches"](#module-dynamic-caches) section in the module
  documentation for more information.
  """
  @doc group: "Runtime API"
  @callback put_dynamic_cache(dynamic_cache()) :: dynamic_cache()

  @doc """
  Invokes the function `fun` using the given dynamic cache.

  ## Example

      MyCache.with_dynamic_cache(:my_cache, fn ->
        MyCache.put("foo", "var")
      end)

  See `c:get_dynamic_cache/0` and `c:put_dynamic_cache/1`.
  """
  @doc group: "Runtime API"
  @callback with_dynamic_cache(dynamic_cache(), fun()) :: any()

  ## Nebulex.Adapter.KV

  @doc """
  Fetches the value for a specific `key` in the cache.

  If the cache contains the given `key`, then its value is returned
  in the shape of `{:ok, value}`.

  If there's an error with executing the command, `{:error, reason}`
  is returned. `reason` is the cause of the error and can be
  `Nebulex.KeyError` if the cache does not contain `key`,
  `Nebulex.Error` otherwise.

  ## Options

  See the ["Shared options"](#module-shared-options) section in the module
  documentation for more options.

  ## Examples

      iex> MyCache.put("foo", "bar")
      :ok
      iex>  MyCache.fetch("foo")
      {:ok, "bar"}

      iex> {:error, %Nebulex.KeyError{key: "bar"} = e} = MyCache.fetch("bar")
      iex> e.reason
      :not_found

  """
  @doc group: "KV API"
  @callback fetch(key(), opts()) :: ok_error_tuple(value(), fetch_error_reason())

  @doc """
  Same as `c:fetch/2`, but the command is executed on the cache instance
  given at the first argument `dynamic_cache`.

  See the ["Dynamic caches"](#module-dynamic-caches) section in the
  module documentation for more information.

  ## Examples

      iex> MyCache.put("foo", "bar")
      :ok
      iex> MyCache.fetch(MyCache1, "foo", [])
      {:ok, "bar"}

  """
  @doc group: "KV API"
  @callback fetch(dynamic_cache(), key(), opts()) :: ok_error_tuple(value(), fetch_error_reason())

  @doc """
  Same as `c:fetch/2` but raises `Nebulex.KeyError` if the cache doesn't contain
  `key` or `Nebulex.Error` if another error occurs while executing the command.

  ## Examples

      iex> MyCache.put("foo", "bar")
      :ok
      iex>  MyCache.fetch!("foo")
      "bar"

  """
  @doc group: "KV API"
  @callback fetch!(key(), opts()) :: value()

  @doc """
  Same as `c:fetch/3` but raises `Nebulex.KeyError` if the cache doesn't contain
  `key` or `Nebulex.Error` if another error occurs while executing the command.
  """
  @doc group: "KV API"
  @callback fetch!(dynamic_cache(), key(), opts()) :: value()

  @doc """
  Gets a value from the cache where the key matches the given `key`.

  If the cache contains the given `key` its value is returned as
  `{:ok, value}`.

  If the cache does not contain `key`, `{:ok, default}` is returned.

  If there's an error with executing the command, `{:error, reason}`
  is returned, where `reason` is the cause of the error.

  ## Options

  See the ["Shared options"](#module-shared-options) section in the module
  documentation for more options.

  ## Examples

      iex> MyCache.put("foo", "bar")
      :ok
      iex>  MyCache.get("foo")
      {:ok, "bar"}
      iex> MyCache.get(:inexistent)
      {:ok, nil}
      iex> MyCache.get(:inexistent, :default)
      {:ok, :default}

  """
  @doc group: "KV API"
  @callback get(key(), default :: value(), opts()) :: ok_error_tuple(value())

  @doc """
  Same as `c:get/3`, but the command is executed on the cache instance
  given at the first argument `dynamic_cache`.

  See the ["Dynamic caches"](#module-dynamic-caches) section in the
  module documentation for more information.

  ## Examples

      iex> MyCache.get(MyCache1, "key", nil, [])
      {:ok, nil}

  """
  @doc group: "KV API"
  @callback get(dynamic_cache(), key(), default :: value(), opts()) :: ok_error_tuple(value())

  @doc """
  Same as `c:get/3` but raises an exception if an error occurs.
  """
  @doc group: "KV API"
  @callback get!(key(), default :: value(), opts()) :: value()

  @doc """
  Same as `c:get!/4` but raises an exception if an error occurs.
  """
  @doc group: "KV API"
  @callback get!(dynamic_cache(), key(), default :: value(), opts()) :: value()

  @doc """
  Puts the given `value` under `key` into the cache.

  If `key` already holds an entry, it is overwritten. Any previous TTL
  (time to live) associated with the key is discarded on a successful
  `put` operation.

  Returns `:ok` if successful; `{:error, reason}` otherwise.

  ## Options

  #{Nebulex.Cache.Options.runtime_common_write_options_docs()}

  See the ["Shared options"](#module-shared-options) section in the module
  documentation for more options.

  ## Examples

      iex> MyCache.put("foo", "bar")
      :ok

  Putting entries with specific time-to-live:

      iex> MyCache.put("foo", "bar", ttl: 10_000)
      :ok
      iex> MyCache.put("foo", "bar", ttl: :timer.hours(1))
      :ok
      iex> MyCache.put("foo", "bar", ttl: :timer.minutes(1))
      :ok
      iex> MyCache.put("foo", "bar", ttl: :timer.seconds(30))
      :ok

  """
  @doc group: "KV API"
  @callback put(key(), value(), opts()) :: :ok | error_tuple()

  @doc """
  Same as `c:put/3`, but the command is executed on the cache instance
  given at the first argument `dynamic_cache`.

  See the ["Dynamic caches"](#module-dynamic-caches) section in the
  module documentation for more information.

  ## Examples

      iex> MyCache.put(MyCache1, "foo", "bar", [])
      :ok
      iex> MyCache.put(MyCache2, "foo", "bar", ttl: :timer.hours(1))
      :ok

  """
  @doc group: "KV API"
  @callback put(dynamic_cache(), key(), value(), opts()) :: :ok | error_tuple()

  @doc """
  Same as `c:put/3` but raises an exception if an error occurs.
  """
  @doc group: "KV API"
  @callback put!(key(), value(), opts()) :: :ok

  @doc """
  Same as `c:put!/4` but raises an exception if an error occurs.
  """
  @doc group: "KV API"
  @callback put!(dynamic_cache(), key(), value(), opts()) :: :ok

  @doc """
  Puts the given `entries` (key/value pairs) into the cache. It replaces
  existing values with new values (just as regular `put`).

  Returns `:ok` if successful; `{:error, reason}` otherwise.

  ## Options

  #{Nebulex.Cache.Options.runtime_common_write_options_docs()}

  See the ["Shared options"](#module-shared-options) section in the module
  documentation for more options.

  ## Examples

      iex> MyCache.put_all(apples: 3, bananas: 1)
      :ok
      iex> MyCache.put_all(%{apples: 2, oranges: 1}, ttl: :timer.hours(1))
      :ok

  > #### Atomic operation {: .warning}
  >
  > Ideally, this operation should be atomic, so all given keys are put at once.
  > But it depends purely on the adapter's implementation and the backend used
  > internally by the adapter. Hence, reviewing the adapter's documentation is
  > highly recommended.
  """
  @doc group: "KV API"
  @callback put_all(entries(), opts()) :: :ok | error_tuple()

  @doc """
  Same as `c:put_all/2`, but the command is executed on the cache instance
  given at the first argument `dynamic_cache`.

  See the ["Dynamic caches"](#module-dynamic-caches) section in the
  module documentation for more information.

  ## Examples

      iex> MyCache.put_all(MyCache1, [apples: 3, bananas: 1], [])
      :ok
      iex> MyCache.put_all(MyCache1, %{oranges: 1}, ttl: :timer.hours(1))
      :ok

  """
  @doc group: "KV API"
  @callback put_all(dynamic_cache(), entries(), opts()) :: :ok | error_tuple()

  @doc """
  Same as `c:put_all/2` but raises an exception if an error occurs.
  """
  @doc group: "KV API"
  @callback put_all!(entries(), opts()) :: :ok

  @doc """
  Same as `c:put_all!/3` but raises an exception if an error occurs.
  """
  @doc group: "KV API"
  @callback put_all!(dynamic_cache(), entries(), opts()) :: :ok

  @doc """
  Puts the given `value` under `key` into the cache only if it does not
  already exist.

  Returns `{:ok, true}` if the value is stored; otherwise, `{:ok, false}`
  is returned.

  If there's an error with executing the command, `{:error, reason}`
  is returned, where `reason` is the cause of the error.

  ## Options

  #{Nebulex.Cache.Options.runtime_common_write_options_docs()}

  See the ["Shared options"](#module-shared-options) section in the module
  documentation for more options.

  ## Examples

      iex> MyCache.put_new("foo", "bar")
      {:ok, true}
      iex> MyCache.put_new("foo", "bar", ttt: :timer.hours(1))
      {:ok, false}

  """
  @doc group: "KV API"
  @callback put_new(key(), value(), opts()) :: ok_error_tuple(boolean())

  @doc """
  Same as `c:put_new/3`, but the command is executed on the cache instance
  given at the first argument `dynamic_cache`.

  See the ["Dynamic caches"](#module-dynamic-caches) section in the
  module documentation for more information.

  ## Examples

      iex> MyCache.put_new(MyCache1, "foo", "bar", [])
      {:ok, true}
      iex> MyCache.put_new(MyCache1, "foo", "bar", ttt: :timer.hours(1))
      {:ok, false}

  """
  @doc group: "KV API"
  @callback put_new(dynamic_cache(), key(), value(), opts()) :: ok_error_tuple(boolean())

  @doc """
  Same as `c:put_new/3` but raises an exception if an error occurs.

  ## Examples

      iex> MyCache.put_new!("foo", "bar")
      true
      iex> MyCache.put_new!("foo", "bar", ttt: :timer.hours(1))
      false

  """
  @doc group: "KV API"
  @callback put_new!(key(), value(), opts()) :: boolean()

  @doc """
  Same as `c:put_new!/4` but raises an exception if an error occurs.
  """
  @doc group: "KV API"
  @callback put_new!(dynamic_cache(), key(), value(), opts()) :: boolean()

  @doc """
  Puts the given `entries` (key/value pairs) into the `cache`. It will not
  perform any operation, even if a single key exists.

  Returns `{:ok, true}` if all entries are successfully stored, or
  `{:ok, false}` if no key was set (at least one key already existed).

  If there's an error with executing the command, `{:error, reason}`
  is returned, where `reason` is the cause of the error.

  ## Options

  #{Nebulex.Cache.Options.runtime_common_write_options_docs()}

  See the ["Shared options"](#module-shared-options) section in the module
  documentation for more options.

  ## Examples

      iex> MyCache.put_new_all(apples: 3, bananas: 1)
      {:ok, true}
      iex> MyCache.put_new_all(%{apples: 3, oranges: 1}, ttl: :timer.hours(1))
      {:ok, false}

  > #### Atomic operation {: .warning}
  >
  > Ideally, this operation should be atomic, so all given keys are put at once.
  > But it depends purely on the adapter's implementation and the backend used
  > internally by the adapter. Hence, reviewing the adapter's documentation is
  > highly recommended.
  """
  @doc group: "KV API"
  @callback put_new_all(entries(), opts()) :: ok_error_tuple(boolean())

  @doc """
  Same as `c:put_new_all/2`, but the command is executed on the cache instance
  given at the first argument `dynamic_cache`.

  See the ["Dynamic caches"](#module-dynamic-caches) section in the
  module documentation for more information.

  ## Examples

      iex> MyCache.put_new_all(MyCache1, [apples: 3, bananas: 1], [])
      {:ok, true}
      iex> MyCache.put_new_all(MyCache1, %{apples: 3, oranges: 1}, ttl: 10_000)
      {:ok, false}

  """
  @doc group: "KV API"
  @callback put_new_all(dynamic_cache(), entries(), opts()) :: ok_error_tuple(boolean())

  @doc """
  Same as `c:put_new_all/2` but raises an exception if an error occurs.

  ## Examples

      iex> MyCache.put_new_all!(apples: 3, bananas: 1)
      true
      iex> MyCache.put_new_all!(%{apples: 3, oranges: 1}, ttl: :timer.hours(1))
      false

  """
  @doc group: "KV API"
  @callback put_new_all!(entries(), opts()) :: boolean()

  @doc """
  Same as `c:put_new_all!/3` but raises an exception if an error occurs.
  """
  @doc group: "KV API"
  @callback put_new_all!(dynamic_cache(), entries(), opts()) :: boolean()

  @doc """
  Alters the entry stored under `key`, but only if the entry already exists
  in the cache.

  Returns `{:ok, true}` if the value is replaced. Otherwise, `{:ok, false}`
  is returned.

  If there's an error with executing the command, `{:error, reason}`
  is returned, where `reason` is the cause of the error.

  ## Options

  #{Nebulex.Cache.Options.runtime_common_write_options_docs()}

  See the ["Shared options"](#module-shared-options) section in the module
  documentation for more options.

  ## Examples

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
  @doc group: "KV API"
  @callback replace(key(), value(), opts()) :: ok_error_tuple(boolean())

  @doc """
  Same as `c:replace/3`, but the command is executed on the cache instance
  given at the first argument `dynamic_cache`.

  See the ["Dynamic caches"](#module-dynamic-caches) section in the
  module documentation for more information.

  ## Examples

      iex> MyCache.replace(MyCache1, "foo", "bar", [])
      {:ok, false}
      iex> MyCache.put_new("foo", "bar")
      {:ok, true}
      iex> MyCache.replace(MyCache1, "foo", "bar", ttl: :timer.hours(1))
      {:ok, true}

  """
  @doc group: "KV API"
  @callback replace(dynamic_cache(), key(), value(), opts()) :: ok_error_tuple(boolean())

  @doc """
  Same as `c:replace/3` but raises an exception if an error occurs.

  ## Examples

      iex> MyCache.replace!("foo", "bar")
      false
      iex> MyCache.put_new!("foo", "bar")
      true
      iex> MyCache.replace!("foo", "bar2")
      true

  """
  @doc group: "KV API"
  @callback replace!(key(), value(), opts()) :: boolean()

  @doc """
  Same as `c:replace!/4` but raises an exception if an error occurs.
  """
  @doc group: "KV API"
  @callback replace!(dynamic_cache(), key(), value(), opts()) :: boolean()

  @doc """
  Deletes the entry in the cache for a specific `key`.

  If there's an error with executing the command, `{:error, reason}`
  is returned, where `reason` is the cause of the error.

  ## Options

  See the ["Shared options"](#module-shared-options) section in the module
  documentation for more options.

  ## Examples

      iex> MyCache.put(:a, 1)
      :ok
      iex> MyCache.delete(:a)
      :ok
      iex> MyCache.get!(:a)
      nil
      iex> MyCache.delete(:inexistent)
      :ok

  """
  @doc group: "KV API"
  @callback delete(key(), opts()) :: :ok | error_tuple()

  @doc """
  Same as `c:delete/2`, but the command is executed on the cache instance
  given at the first argument `dynamic_cache`.

  See the ["Dynamic caches"](#module-dynamic-caches) section in the
  module documentation for more information.

  ## Examples

      iex> MyCache.delete(MyCache1, :a, [])
      :ok

  """
  @doc group: "KV API"
  @callback delete(dynamic_cache(), key(), opts()) :: :ok | error_tuple()

  @doc """
  Same as `c:delete/2` but raises an exception if an error occurs.
  """
  @doc group: "KV API"
  @callback delete!(key(), opts()) :: :ok

  @doc """
  Same as `c:delete!/3` but raises an exception if an error occurs.
  """
  @doc group: "KV API"
  @callback delete!(dynamic_cache(), key(), opts()) :: :ok

  @doc """
  Removes and returns the value associated with `key` in the cache.

  If `key` is present in the cache, its value is removed and returned as
  `{:ok, value}`.

  If there's an error with executing the command, `{:error, reason}`
  is returned. `reason` is the cause of the error and can be
  `Nebulex.KeyError` if the cache does not contain `key` or
  `Nebulex.Error` otherwise.

  ## Options

  See the ["Shared options"](#module-shared-options) section in the module
  documentation for more options.

  ## Examples

      iex> MyCache.put(:a, 1)
      :ok
      iex> MyCache.take(:a)
      {:ok, 1}

      iex> {:error, %Nebulex.KeyError{key: :a} = e} = MyCache.take(:a)
      iex> e.reason
      :not_found

  """
  @doc group: "KV API"
  @callback take(key(), opts()) :: ok_error_tuple(value(), fetch_error_reason())

  @doc """
  Same as `c:take/2`, but the command is executed on the cache instance
  given at the first argument `dynamic_cache`.

  See the ["Dynamic caches"](#module-dynamic-caches) section in the
  module documentation for more information.

  ## Examples

      iex> MyCache.put(:a, 1)
      :ok
      iex> MyCache.take(MyCache1, :a, [])
      {:ok, 1}

  """
  @doc group: "KV API"
  @callback take(dynamic_cache(), key(), opts()) :: ok_error_tuple(value(), fetch_error_reason())

  @doc """
  Same as `c:take/2` but raises an exception if an error occurs.

  ## Examples

      iex> MyCache.put(:a, 1)
      :ok
      iex> MyCache.take!(:a)
      1

  """
  @doc group: "KV API"
  @callback take!(key(), opts()) :: value()

  @doc """
  Same as `c:take!/3` but raises an exception if an error occurs.
  """
  @doc group: "KV API"
  @callback take!(dynamic_cache(), key(), opts()) :: value()

  @doc """
  Determines if the cache contains an entry for the specified `key`.

  More formally, it returns `{:ok, true}` if the cache contains the given `key`.
  If the cache doesn't contain `key`, `{:ok, false}` is returned.

  If there's an error with executing the command, `{:error, reason}`
  is returned, where `reason` is the cause of the error.

  ## Options

  See the ["Shared options"](#module-shared-options) section in the module
  documentation for more options.

  ## Examples

      iex> MyCache.put(:a, 1)
      :ok
      iex> MyCache.has_key?(:a)
      {:ok, true}
      iex> MyCache.has_key?(:b)
      {:ok, false}

  """
  @doc group: "KV API"
  @callback has_key?(key(), opts()) :: ok_error_tuple(boolean())

  @doc """
  Same as `c:has_key?/2`, but the command is executed on the cache instance
  given at the first argument `dynamic_cache`.

  See the ["Dynamic caches"](#module-dynamic-caches) section in the
  module documentation for more information.

  ## Examples

      iex> MyCache.has_key?(MyCache1, :a, [])
      {:ok, false}

  """
  @doc group: "KV API"
  @callback has_key?(dynamic_cache(), key(), opts()) :: ok_error_tuple(boolean())

  @doc """
  Increments the counter stored at `key` by the given `amount` and returns
  the current count as `{:ok, count}`.

  If `amount < 0`, the value is decremented by that `amount` instead.

  If there's an error with executing the command, `{:error, reason}`
  is returned, where `reason` is the cause of the error.

  ## Options

  #{Nebulex.Cache.Options.update_counter_options_docs()}

  See the ["Shared options"](#module-shared-options) section in the module
  documentation for more options.

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
  @doc group: "KV API"
  @callback incr(key(), amount :: integer(), opts()) :: ok_error_tuple(integer())

  @doc """
  Same as `c:incr/3`, but the command is executed on the cache instance
  given at the first argument `dynamic_cache`.

  See the ["Dynamic caches"](#module-dynamic-caches) section in the
  module documentation for more information.

  ## Examples

      iex> MyCache.incr(MyCache1, :a, 1, [])
      {:ok, 1}

  """
  @doc group: "KV API"
  @callback incr(dynamic_cache(), key(), amount :: integer(), opts()) :: ok_error_tuple(integer())

  @doc """
  Same as `c:incr/3` but raises an exception if an error occurs.

  ## Examples

      iex> MyCache.incr!(:a)
      1
      iex> MyCache.incr!(:a, 2)
      3

  """
  @doc group: "KV API"
  @callback incr!(key(), amount :: integer(), opts()) :: integer()

  @doc """
  Same as `c:incr!/4` but raises an exception if an error occurs.
  """
  @doc group: "KV API"
  @callback incr!(dynamic_cache(), key(), amount :: integer(), opts()) :: integer()

  @doc """
  Decrements the counter stored at `key` by the given `amount` and returns
  the current count as `{:ok, count}`.

  If `amount < 0`, the value is incremented by that `amount` instead
  (opposite to `incr/3`).

  If there's an error with executing the command, `{:error, reason}`
  is returned, where `reason` is the cause of the error.

  ## Options

  #{Nebulex.Cache.Options.update_counter_options_docs()}

  See the ["Shared options"](#module-shared-options) section in the module
  documentation for more options.

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
  @doc group: "KV API"
  @callback decr(key(), amount :: integer(), opts()) :: ok_error_tuple(integer())

  @doc """
  Same as `c:decr/3`, but the command is executed on the cache instance
  given at the first argument `dynamic_cache`.

  See the ["Dynamic caches"](#module-dynamic-caches) section in the
  module documentation for more information.

  ## Examples

      iex> MyCache.decr(MyCache1, :a, 1, [])
      {:ok, -1}

  """
  @doc group: "KV API"
  @callback decr(dynamic_cache(), key(), amount :: integer(), opts()) :: ok_error_tuple(integer())

  @doc """
  Same as `c:decr/3` but raises an exception if an error occurs.

  ## Examples

      iex> MyCache.decr!(:a)
      -1

  """
  @doc group: "KV API"
  @callback decr!(key(), amount :: integer(), opts()) :: integer()

  @doc """
  Same as `c:decr!/4` but raises an exception if an error occurs.
  """
  @doc group: "KV API"
  @callback decr!(dynamic_cache(), key(), amount :: integer(), opts()) :: integer()

  @doc """
  Returns the remaining time-to-live for the given `key`.

  If `key` is present in the cache, its remaining TTL is returned as
  `{:ok, ttl}`.

  If there's an error with executing the command, `{:error, reason}`
  is returned. `reason` is the cause of the error and can be
  `Nebulex.KeyError` if the cache does not contain `key`,
  `Nebulex.Error` otherwise.

  ## Options

  See the ["Shared options"](#module-shared-options) section in the module
  documentation for more options.

  ## Examples

      iex> MyCache.put(:a, 1, ttl: 5000)
      :ok
      iex> MyCache.put(:b, 2)
      :ok
      iex> MyCache.ttl(:a)
      {:ok, _remaining_ttl}
      iex> MyCache.ttl(:b)
      {:ok, :infinity}

      iex> {:error, %Nebulex.KeyError{key: :c} = e} = MyCache.ttl(:c)
      iex> e.reason
      :not_found

  """
  @doc group: "KV API"
  @callback ttl(key(), opts()) :: ok_error_tuple(timeout(), fetch_error_reason())

  @doc """
  Same as `c:ttl/2`, but the command is executed on the cache instance
  given at the first argument `dynamic_cache`.

  See the ["Dynamic caches"](#module-dynamic-caches) section in the
  module documentation for more information.

  ## Examples

      iex> MyCache.put(:a, 1, ttl: 5000)
      :ok
      iex> MyCache.ttl(MyCache1, :a, [])
      {:ok, _remaining_ttl}

  """
  @doc group: "KV API"
  @callback ttl(dynamic_cache(), key(), opts()) :: ok_error_tuple(timeout(), fetch_error_reason())

  @doc """
  Same as `c:ttl/2` but raises an exception if an error occurs.

  ## Examples

      iex> MyCache.put(:a, 1, ttl: 5000)
      :ok
      iex> MyCache.ttl!(:a)
      _remaining_ttl

  """
  @doc group: "KV API"
  @callback ttl!(key(), opts()) :: timeout()

  @doc """
  Same as `c:ttl!/3` but raises an exception if an error occurs.
  """
  @doc group: "KV API"
  @callback ttl!(dynamic_cache(), key(), opts()) :: timeout()

  @doc """
  Returns `{:ok, true}` if the given `key` exists and the new `ttl` is
  successfully updated; otherwise, `{:ok, false}` is returned.

  If there's an error with executing the command, `{:error, reason}`
  is returned; where `reason` is the cause of the error.

  ## Options

  See the ["Shared options"](#module-shared-options) section in the module
  documentation for more options.

  ## Examples

      iex> MyCache.put(:a, 1)
      :ok
      iex> MyCache.expire(:a, :timer.hours(1))
      {:ok, true}
      iex> MyCache.expire(:a, :infinity)
      {:ok, true}
      iex> MyCache.expire(:b, 5)
      {:ok, false}

  """
  @doc group: "KV API"
  @callback expire(key(), ttl :: timeout(), opts()) :: ok_error_tuple(boolean())

  @doc """
  Same as `c:expire/3`, but the command is executed on the cache instance
  given at the first argument `dynamic_cache`.

  See the ["Dynamic caches"](#module-dynamic-caches) section in the
  module documentation for more information.

  ## Examples

      iex> MyCache.expire(MyCache1, :a, :timer.hours(1), [])
      {:ok, false}

  """
  @doc group: "KV API"
  @callback expire(dynamic_cache(), key(), ttl :: timeout(), opts()) :: ok_error_tuple(boolean())

  @doc """
  Same as `c:expire/3` but raises an exception if an error occurs.

  ## Examples

      iex> MyCache.put(:a, 1)
      :ok
      iex> MyCache.expire!(:a, :timer.hours(1))
      true

  """
  @doc group: "KV API"
  @callback expire!(key(), ttl :: timeout(), opts()) :: boolean()

  @doc """
  Same as `c:expire!/4` but raises an exception if an error occurs.
  """
  @doc group: "KV API"
  @callback expire!(dynamic_cache(), key(), ttl :: timeout(), opts()) :: boolean()

  @doc """
  Returns `{:ok, true}` if the given `key` exists and the last access time is
  successfully updated; otherwise, `{:ok, false}` is returned.

  If there's an error with executing the command, `{:error, reason}`
  is returned, where `reason` is the cause of the error.

  ## Options

  See the ["Shared options"](#module-shared-options) section in the module
  documentation for more options.

  ## Examples

      iex> MyCache.put(:a, 1)
      :ok
      iex> MyCache.touch(:a)
      {:ok, true}
      iex> MyCache.ttl(:b)
      {:ok, false}

  """
  @doc group: "KV API"
  @callback touch(key(), opts()) :: ok_error_tuple(boolean())

  @doc """
  Same as `c:touch/2`, but the command is executed on the cache instance
  given at the first argument `dynamic_cache`.

  See the ["Dynamic caches"](#module-dynamic-caches) section in the
  module documentation for more information.

  ## Examples

      iex> MyCache.touch(MyCache1, :a, [])
      {:ok, false}

  """
  @doc group: "KV API"
  @callback touch(dynamic_cache(), key(), opts()) :: ok_error_tuple(boolean())

  @doc """
  Same as `c:touch/2` but raises an exception if an error occurs.

  ## Examples

      iex> MyCache.put(:a, 1)
      :ok
      iex> MyCache.touch!(:a)
      true

  """
  @doc group: "KV API"
  @callback touch!(key(), opts()) :: boolean()

  @doc """
  Same as `c:touch!/3` but raises an exception if an error occurs.
  """
  @doc group: "KV API"
  @callback touch!(dynamic_cache(), key(), opts()) :: boolean()

  @doc """
  Gets the value from `key` and updates it, all in one pass.

  `fun` is called with the current cached value under `key` (or `nil` if `key`
  hasn't been cached) and must return a two-element tuple: the current value
  (the retrieved value, which can be operated on before being returned) and
  the new value to be stored under `key`. `fun` may also return `:pop`, which
  means the current value shall be removed from the cache and returned.

  This function returns:

    * `{:ok, {current_value, new_value}}` - The `current_value` is the current
      cached value and `new_value` the updated one returned by `fun`.

    * `{:error, reason}` - An error occurred executing the command.
      `reason` is the cause of the error.

  ## Options

  #{Nebulex.Cache.Options.runtime_common_write_options_docs()}

  See the ["Shared options"](#module-shared-options) section in the module
  documentation for more options.

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
  @doc group: "KV API"
  @callback get_and_update(key(), (value() -> {current_value, new_value} | :pop), opts()) ::
              ok_error_tuple({current_value, new_value})
            when current_value: value(), new_value: value()

  @doc """
  Same as `c:get_and_update/3`, but the command is executed on the cache
  instance given at the first argument `dynamic_cache`.

  See the ["Dynamic caches"](#module-dynamic-caches) section in the
  module documentation for more information.

  ## Examples

      iex> MyCache.get_and_update(MyCache1, :a, &{&1, "value!"}, [])
      {:ok, {nil, "value!"}}

  """
  @doc group: "KV API"
  @callback get_and_update(
              dynamic_cache(),
              key(),
              (value() -> {current_value, new_value} | :pop),
              opts()
            ) :: ok_error_tuple({current_value, new_value})
            when current_value: value(), new_value: value()

  @doc """
  Same as `c:get_and_update/3` but raises an exception if an error occurs.

  ## Examples

      iex> MyCache.get_and_update!(:a, &{&1, "value!"})
      {nil, "value!"}

  """
  @doc group: "KV API"
  @callback get_and_update!(key(), (value() -> {current_value, new_value} | :pop), opts()) ::
              {current_value, new_value}
            when current_value: value(), new_value: value()

  @doc """
  Same as `c:get_and_update!/4` but raises an exception if an error occurs.
  """
  @doc group: "KV API"
  @callback get_and_update!(
              dynamic_cache(),
              key(),
              (value() -> {current_value, new_value} | :pop),
              opts()
            ) :: {current_value, new_value}
            when current_value: value(), new_value: value()

  @doc """
  Updates the `key` in the cache with the given function.

  If `key` is present in the cache, the existing value is passed to `fun` and
  its result is used as the updated value of `key`. If `key` is not present in
  the cache, `default` is inserted as the value of `key`. The default value
  will not be passed through the update function.

  This function returns:

    * `{:ok, value}` - The value associated with the `key` is updated.

    * `{:error, reason}` - An error occurred executing the command.
      `reason` is the cause.

  ## Options

  #{Nebulex.Cache.Options.runtime_common_write_options_docs()}

  See the ["Shared options"](#module-shared-options) section in the module
  documentation for more options.

  ## Examples

      iex> MyCache.update(:a, 1, &(&1 * 2))
      {:ok, 1}
      iex> MyCache.update(:a, 1, &(&1 * 2))
      {:ok, 2}

  """
  @doc group: "KV API"
  @callback update(key(), initial :: value(), (value() -> value()), opts()) ::
              ok_error_tuple(value())

  @doc """
  Same as `c:update/4`, but the command is executed on the cache instance
  given at the first argument `dynamic_cache`.

  See the ["Dynamic caches"](#module-dynamic-caches) section in the
  module documentation for more information.

  ## Examples

      iex> MyCache.update(MyCache1, :a, 1, &(&1 * 2), [])
      {:ok, 1}

  """
  @doc group: "KV API"
  @callback update(dynamic_cache(), key(), initial :: value(), (value() -> value()), opts()) ::
              ok_error_tuple(value())

  @doc """
  Same as `c:update/4` but raises an exception if an error occurs.

  ## Examples

      iex> MyCache.update!(:a, 1, &(&1 * 2))
      1

  """
  @doc group: "KV API"
  @callback update!(key(), initial :: value(), (value() -> value()), opts()) :: value()

  @doc """
  Same as `c:update!/5` but raises an exception if an error occurs.
  """
  @doc group: "KV API"
  @callback update!(dynamic_cache(), key(), initial :: value(), (value() -> value()), opts()) ::
              value()

  ## Nebulex.Adapter.Queryable

  @optional_callbacks get_all: 2,
                      get_all: 3,
                      get_all!: 2,
                      get_all!: 3,
                      count_all: 2,
                      count_all: 3,
                      count_all!: 2,
                      count_all!: 3,
                      delete_all: 2,
                      delete_all: 3,
                      delete_all!: 2,
                      delete_all!: 3,
                      stream: 2,
                      stream: 3,
                      stream!: 2,
                      stream!: 3

  @doc """
  Fetches all entries from the cache matching the given query specified through
  the ["query-spec"](#c:get_all/2-query-specification).

  This function returns:

    * `{:ok, result}` - The cache executes the query successfully. The `result`
      is a list with the matched entries.

    * `{:error, reason}` - An error occurred executing the command.
      `reason` is the cause.

  May raise `Nebulex.QueryError` if query validation fails.

  ## Query specification

  There are two ways to use the Query API:

    * Fetch multiple keys (all at once), like a bulk fetch.
    * Fetch all entries from the cache matching a given query, more like a
      search (this is the most generic option).

  Here is where the `query_spec` argument comes in to specify the type of query
  to run.

  The `query_spec` argument is a `t:keyword/0` with options defining the desired
  query. The `query_spec` fields or options are:

  #{Nebulex.Cache.QuerySpec.options_docs()}

  ### Fetching multiple keys

  While you can perform any query using the `:query` option (even fetching
  multiple keys), the option `:in` is preferable. For example:

      MyCache.get_all(in: ["a", "list", "of", "keys"])

  ### Fetching all entries matching a given query

  As mentioned above, the option `:query` is the most generic way to match
  entries in a cache. This option allows users to write custom queries
  to be executed by the underlying adapter.

  For matching all cached entries, you can skip the `:query` option or set it
  to `nil` instead (the default). For example:

      MyCache.get_all() #=> Equivalent to MyCache.get_all(query: nil)

  Using a custom query:

      MyCache.get_all(query: query_supported_by_the_adapter)

  > _Nebulex recommends to see the adapter documentation when using this option._

  ## Options

  See the ["Shared options"](#module-shared-options) section in the module
  documentation for more options.

  ## Examples

  Populate the cache with some entries:

      iex> MyCache.put_all(a: 1, b: 2, c: 3)
      :ok

  Fetch all entries in the cache:

      iex> MyCache.get_all()
      {:ok, [a: 1, b: 2, c: 3]}

  Fetch all entries returning only the keys:

      iex> MyCache.get_all(select: :key)
      {:ok, [:a, :b, :c]}

  Fetch all entries returning only the values:

      iex> MyCache.get_all(select: :value)
      {:ok, [1, 2, 3]}

  Fetch only the requested keys (bulk fetch):

      iex> MyCache.get_all(in: [:a, :b, :d])
      {:ok, [a: 1, b: 2]}

  Fetch the requested keys returning only the keys or values:

      iex> MyCache.get_all(in: [:a, :b, :d], select: :key)
      {:ok, [:a, :b]}
      iex> MyCache.get_all(in: [:a, :b, :d], select: :value)
      {:ok, [1, 2]}

  ### Query examples for `Nebulex.Adapters.Local` adapter

  The `Nebulex.Adapters.Local` adapter supports **"ETS Match Spec"** as query
  values (in addition to `nil` or the option `:in`).

  You must know the adapter's entry structure for match-spec queries, which is
  `{:entry, key, value, touched, ttl}`. For example, one may write the following
  query:

      iex> match_spec = [
      ...>   {
      ...>     {:entry, :"$1", :"$2", :_, :_},
      ...>     [{:>, :"$2", 1}],
      ...>     [{{:"$1", :"$2"}}]
      ...>   }
      ...> ]
      iex> MyCache.get_all(query: match_spec)
      {:ok, [b: 1, c: 3]}

  """
  @doc group: "Query API"
  @callback get_all(query_spec(), opts()) :: ok_error_tuple([any()])

  @doc """
  Same as `c:get_all/2`, but the command is executed on the cache instance
  given at the first argument `dynamic_cache`.

  See the ["Dynamic caches"](#module-dynamic-caches) section in the
  module documentation for more information.

  ## Examples

      iex> MyCache.get_all(MyCache1, [], [])
      {:ok, _matched_entries}

  """
  @doc group: "Query API"
  @callback get_all(dynamic_cache(), query_spec(), opts()) :: ok_error_tuple([any()])

  @doc """
  Same as `c:get_all/2` but raises an exception if an error occurs.

  ## Examples

      iex> MyCache.put_all(a: 1, b: 2, c: 3)
      :ok
      iex> MyCache.get_all!()
      [a: 1, b: 2, c: 3]
      iex> MyCache.get_all!(in: [:a, :b])
      [a: 1, b: 2]

  """
  @doc group: "Query API"
  @callback get_all!(query_spec(), opts()) :: [any()]

  @doc """
  Same as `c:get_all!/3` but raises an exception if an error occurs.
  """
  @doc group: "Query API"
  @callback get_all!(dynamic_cache(), query_spec(), opts()) :: [any()]

  @doc """
  Deletes all entries matching the query specified by the given `query_spec`.

  See `c:get_all/2` for more information about the `query_spec`.

  This function returns:

    * `{:ok, deleted_count}` - The cache executes the query successfully and
      returns the deleted entries count.

    * `{:error, reason}` - An error occurred executing the command.
      `reason` is the cause.

  May raise `Nebulex.QueryError` if query validation fails.

  ## Options

  See the ["Shared options"](#module-shared-options) section in the module
  documentation for more options.

  ## Examples

  Populate the cache with some entries:

      iex> Enum.each(1..5, &MyCache.put(&1, &1 * 2))
      :ok

  Delete all (default args):

      iex> MyCache.delete_all()
      {:ok, 5}

  Delete only the requested keys (bulk delete):

      iex> MyCache.delete_all(in: [1, 2, 10])
      {:ok, 2}

  Delete all entries that match with the given query, assuming we are using
  `Nebulex.Adapters.Local` adapter:

      iex> query = [{{:_, :"$1", :"$2", :_, :_}, [{:>, :"$2", 5}], [true]}]
      iex> {:ok, deleted_count} = MyCache.delete_all(query: query)

  See `c:get_all/2` for more query examples.
  """
  @doc group: "Query API"
  @callback delete_all(query_spec(), opts()) :: ok_error_tuple(non_neg_integer())

  @doc """
  Same as `c:delete_all/2`, but the command is executed on the cache instance
  given at the first argument `dynamic_cache`.

  See the ["Dynamic caches"](#module-dynamic-caches) section in the
  module documentation for more information.

  ## Examples

      iex> MyCache.delete_all(MyCache1, [], [])
      {:ok, 0}

  """
  @doc group: "Query API"
  @callback delete_all(dynamic_cache(), query_spec(), opts()) :: ok_error_tuple(non_neg_integer())

  @doc """
  Same as `c:delete_all/2` but raises an exception if an error occurs.

  ## Examples

      iex> MyCache.delete_all!()
      0

  """
  @doc group: "Query API"
  @callback delete_all!(query_spec(), opts()) :: integer()

  @doc """
  Same as `c:delete_all!/3` but raises an exception if an error occurs.
  """
  @doc group: "Query API"
  @callback delete_all!(dynamic_cache(), query_spec(), opts()) :: integer()

  @doc """
  Counts all entries matching the query specified by the given `query_spec`.

  See `c:get_all/2` for more information about the `query_spec`.

  This function returns:

    * `{:ok, count}` - The cache executes the query successfully and
      returns the `count` of the matched entries.

    * `{:error, reason}` - An error occurred executing the command.
      `reason` is the cause.

  May raise `Nebulex.QueryError` if query validation fails.

  ## Options

  See the ["Shared options"](#module-shared-options) section in the module
  documentation for more options.

  ## Examples

  Populate the cache with some entries:

      iex> Enum.each(1..5, &MyCache.put(&1, &1 * 2))
      :ok

  Count all entries in cache (cache size):

      iex> MyCache.count_all()
      {:ok, 5}

  Count all entries that match with the given query, assuming we are using
  `Nebulex.Adapters.Local` adapter:

      iex> query = [{{:_, :"$1", :"$2", :_, :_}, [{:>, :"$2", 5}], [true]}]
      iex> {:ok, count} = MyCache.count_all(query: query)

  See `c:get_all/2` for more query examples.
  """
  @doc group: "Query API"
  @callback count_all(query_spec(), opts()) :: ok_error_tuple(non_neg_integer())

  @doc """
  Same as `c:count_all/2`, but the command is executed on the cache instance
  given at the first argument `dynamic_cache`.

  See the ["Dynamic caches"](#module-dynamic-caches) section in the
  module documentation for more information.

  ## Examples

      iex> MyCache.count_all(MyCache1, [], [])
      {:ok, 0}

  """
  @doc group: "Query API"
  @callback count_all(dynamic_cache(), query_spec(), opts()) :: ok_error_tuple(non_neg_integer())

  @doc """
  Same as `c:count_all/2` but raises an exception if an error occurs.

  ## Examples

      iex> MyCache.count_all!()
      0

  """
  @doc group: "Query API"
  @callback count_all!(query_spec(), opts()) :: non_neg_integer()

  @doc """
  Same as `c:count_all!/3` but raises an exception if an error occurs.
  """
  @doc group: "Query API"
  @callback count_all!(dynamic_cache(), query_spec(), opts()) :: non_neg_integer()

  @doc """
  Similar to `c:get_all/2`, but returns a lazy enumerable that emits all entries
  matching the query specified by the given `query_spec`.

  See `c:get_all/2` for more information about the `query_spec`.

  This function returns:

    * `{:ok, stream}` - It returns a `stream` of values.

    * `{:error, reason}` - An error occurred executing the command.
      `reason` is the cause.

  May raise `Nebulex.QueryError` if query validation fails.

  ## Options

    * `:max_entries` - The number of entries to load from the cache
      as we stream. Defaults to `100`.

  See the ["Shared options"](#module-shared-options) section in the module
  documentation for more options.

  ## Examples

  Populate the cache with some entries:

      iex> MyCache.put_all(a: 1, b: 2, c: 3)
      :ok

  Stream all (default args):

      iex> {:ok, stream} = MyCache.stream()
      iex> Enum.to_list(stream)
      [a: 1, b: 2, c: 3]

  Stream all entries returning only the keys (with :max_entries option):

      iex> {:ok, stream} = MyCache.stream([select: :key], max_entries: 2)
      iex> Enum.to_list(stream)
      [:a, :b, :c]

  Stream all entries returning only the values:

      iex> {:ok, stream} = MyCache.stream(select: :value)
      iex> Enum.to_list(stream)
      [1, 2, 3]

  Stream only the resquested keys (lazy bulk-fetch):

      iex> {:ok, stream} = MyCache.stream(in: [:a, :b, :d])
      iex> Enum.to_list(stream)
      [a: 1, b: 2]
      iex> {:ok, stream} = MyCache.stream(in: [:a, :b, :d], select: :key)
      iex> Enum.to_list(stream)
      [:a, :b]

  """
  @doc group: "Query API"
  @callback stream(query_spec(), opts()) :: ok_error_tuple(Enum.t())

  @doc """
  Same as `c:stream/2`, but the command is executed on the cache instance
  given at the first argument `dynamic_cache`.

  See the ["Dynamic caches"](#module-dynamic-caches) section in the
  module documentation for more information.

  ## Examples

      iex> = MyCache.stream(MyCache1, nil, [])
      {:ok, _stream}

  """
  @doc group: "Query API"
  @callback stream(dynamic_cache(), query_spec(), opts()) :: ok_error_tuple(Enum.t())

  @doc """
  Same as `c:stream/2` but raises an exception if an error occurs.

  ## Examples

      iex> MyCache.put_all(a: 1, b: 2, c: 3)
      :ok
      iex> MyCache.stream!() |> Enum.to_list()
      [a: 1, b: 2, c: 3]

  """
  @doc group: "Query API"
  @callback stream!(query_spec(), opts()) :: Enum.t()

  @doc """
  Same as `c:stream!/3` but raises an exception if an error occurs.
  """
  @doc group: "Query API"
  @callback stream!(dynamic_cache(), query_spec(), opts()) :: Enum.t()

  ## Nebulex.Adapter.Persistence

  @optional_callbacks dump: 2, dump: 3, dump!: 2, dump!: 3, load: 2, load: 3, load!: 2, load!: 3

  @doc """
  Dumps a cache to the given file `path`.

  Returns `:ok` if successful, `{:error, reason}` otherwise.

  ## Options

  See the ["Shared options"](#module-shared-options) section in the module
  documentation for more options.

  ## Examples

  Populate the cache with some entries:

      iex> entries = for x <- 1..10, into: %{}, do: {x, x}
      iex> MyCache.put_all(entries)
      :ok

  Dump cache to a file:

      iex> MyCache.dump("my_cache")
      :ok

  """
  @doc group: "Persistence API"
  @callback dump(path :: Path.t(), opts()) :: :ok | error_tuple()

  @doc """
  Same as `c:dump/2`, but the command is executed on the cache instance
  given at the first argument `dynamic_cache`.

  See the ["Dynamic caches"](#module-dynamic-caches) section in the
  module documentation for more information.

  ## Examples

      MyCache.dump(MyCache1, "my_cache", [])

  """
  @doc group: "Persistence API"
  @callback dump(dynamic_cache(), path :: Path.t(), opts()) :: :ok | error_tuple()

  @doc """
  Same as `c:dump/2` but raises an exception if an error occurs.
  """
  @doc group: "Persistence API"
  @callback dump!(path :: Path.t(), opts()) :: :ok

  @doc """
  Same as `c:dump!/3` but raises an exception if an error occurs.
  """
  @doc group: "Persistence API"
  @callback dump!(dynamic_cache(), path :: Path.t(), opts()) :: :ok

  @doc """
  Loads a dumped cache from the given `path`.

  Returns `:ok` if successful, `{:error, reason}` otherwise.

  ## Options

  See the ["Shared options"](#module-shared-options) section in the module
  documentation for more options.

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
  @doc group: "Persistence API"
  @callback load(path :: Path.t(), opts()) :: :ok | error_tuple()

  @doc """
  Same as `c:load/2`, but the command is executed on the cache instance
  given at the first argument `dynamic_cache`.

  See the ["Dynamic caches"](#module-dynamic-caches) section in the
  module documentation for more information.

  ## Examples

      MyCache.load(MyCache1, "my_cache", [])

  """
  @doc group: "Persistence API"
  @callback load(dynamic_cache(), path :: Path.t(), opts()) :: :ok | error_tuple()

  @doc """
  Same as `c:load/2` but raises an exception if an error occurs.
  """
  @doc group: "Persistence API"
  @callback load!(path :: Path.t(), opts()) :: :ok

  @doc """
  Same as `c:load!/3` but raises an exception if an error occurs.
  """
  @doc group: "Persistence API"
  @callback load!(dynamic_cache(), path :: Path.t(), opts()) :: :ok

  ## Nebulex.Adapter.Transaction

  @optional_callbacks transaction: 2, transaction: 3, in_transaction?: 1, in_transaction?: 2

  @doc """
  Runs the given function inside a transaction.

  If an Elixir exception occurs, the exception will bubble up from the
  transaction function. If the cache aborts the transaction, it returns
  `{:error, reason}`.

  A successful transaction returns the value returned by the function wrapped
  in a tuple as `{:ok, value}`.

  ### Nested transactions

  If `transaction/2` is called inside another transaction, the cache executes
  the function without wrapping the new transaction call in any way.

  ## Options

  See the ["Shared options"](#module-shared-options) section in the module
  documentation for more options.

  ## Examples

      MyCache.transaction(fn ->
        alice = MyCache.get(:alice)
        bob = MyCache.get(:bob)
        MyCache.put(:alice, %{alice | balance: alice.balance + 100})
        MyCache.put(:bob, %{bob | balance: bob.balance + 100})
      end)

  We can provide the keys to lock when using the `Nebulex.Adapters.Local`
  adapter: (recommended):

      MyCache.transaction(
        fn ->
          alice = MyCache.get(:alice)
          bob = MyCache.get(:bob)
          MyCache.put(:alice, %{alice | balance: alice.balance + 100})
          MyCache.put(:bob, %{bob | balance: bob.balance + 100})
        end,
        [keys: [:alice, :bob]]
      )

  """
  @doc group: "Transaction API"
  @callback transaction(fun(), opts()) :: ok_error_tuple(any())

  @doc """
  Same as `c:transaction/2`, but the command is executed on the cache instance
  given at the first argument `dynamic_cache`.

  See the ["Dynamic caches"](#module-dynamic-caches) section in the
  module documentation for more information.

  ## Examples

      MyCache.transaction(
        MyCache1,
        fn ->
          alice = MyCache.get(:alice)
          bob = MyCache.get(:bob)
          MyCache.put(:alice, %{alice | balance: alice.balance + 100})
          MyCache.put(:bob, %{bob | balance: bob.balance + 100})
        end,
        [keys: [:alice, :bob]]
      )

  """
  @doc group: "Transaction API"
  @callback transaction(dynamic_cache(), fun(), opts()) :: ok_error_tuple(any())

  @doc """
  Returns `{:ok, true}` if the current process is inside a transaction;
  otherwise, `{:ok, false}` is returned.

  If there's an error with executing the command, `{:error, reason}`
  is returned, where `reason` is the cause of the error.

  ## Options

  See the ["Shared options"](#module-shared-options) section in the module
  documentation for more options.

  ## Examples

      MyCache.in_transaction?()
      #=> {:ok, false}

      MyCache.transaction(fn ->
        MyCache.in_transaction? #=> {:ok, true}
      end)

  """
  @doc group: "Transaction API"
  @callback in_transaction?(opts()) :: ok_error_tuple(boolean())

  @doc """
  Same as `c:in_transaction?/1`, but the command is executed on the cache instance
  given at the first argument `dynamic_cache`.

  See the ["Dynamic caches"](#module-dynamic-caches) section in the
  module documentation for more information.

  ## Examples

      MyCache.in_transaction?(MyCache1, [])

  """
  @doc group: "Transaction API"
  @callback in_transaction?(dynamic_cache(), opts()) :: ok_error_tuple(boolean())

  ## Nebulex.Adapter.Info

  @optional_callbacks info: 2, info: 3, info!: 2, info!: 3

  @doc """
  Returns `{:ok, info}` where `info` contains the requested cache information,
  as specified by the `spec`.

  If there's an error with executing the command, `{:error, reason}`
  is returned, where `reason` is the cause of the error.

  The `spec` (information specification key) can be:

    * **The atom `:all`** - returns a map with all information items.
    * **An atom** - returns the value for the requested information item.
    * **A list of atoms** - returns a map only with the requested information
      items.

  If the argument `spec` is omitted, all information items are returned;
  same as if the `spec` was the atom `:all`.

  The adapters are free to add the information specification keys they want.
  However, Nebulex suggests the adapters add the following keys:

    * `:server` - General information about the cache server (e.g., cache name,
      adapter, PID, etc.).
    * `:memory` - Memory consumption information (e.g., used memory,
      allocated memory, etc.).
    * `:stats` - Cache statistics (e.g., hits, misses, etc.).

  ## Examples

  The following examples assume the underlying adapter uses the implementation
  provided by `Nebulex.Adapters.Common.Info`.

      iex> {:ok, info} = MyCache.info()
      iex> info
      %{
        server: %{
          nbx_version: "3.0.0",
          cache_module: "MyCache",
          cache_adapter: "Nebulex.Adapters.Local",
          cache_name: "MyCache",
          cache_pid: #PID<0.111.0>
        },
        memory: %{
          total: 1_000_000,
          used: 0
        },
        stats: %{
          deletions: 0,
          evictions: 0,
          expirations: 0,
          hits: 0,
          misses: 0,
          updates: 0,
          writes: 0
        }
      }

      iex> {:ok, info} = MyCache.info(:server)
      iex> info
      %{
        nbx_version: "3.0.0",
        cache_module: "MyCache",
        cache_adapter: "Nebulex.Adapters.Local",
        cache_name: "MyCache",
        cache_pid: #PID<0.111.0>
      }

      iex> {:ok, info} = MyCache.info([:server, :stats])
      iex> info
      %{
        server: %{
          nbx_version: "3.0.0",
          cache_module: "MyCache",
          cache_adapter: "Nebulex.Adapters.Local",
          cache_name: "MyCache",
          cache_pid: #PID<0.111.0>
        },
        stats: %{
          deletions: 0,
          evictions: 0,
          expirations: 0,
          hits: 0,
          misses: 0,
          updates: 0,
          writes: 0
        }
      }

  """
  @doc group: "Info API"
  @callback info(spec :: info_spec(), opts()) :: ok_error_tuple(info_data())

  @doc """
  Same as `c:info/2`, but the command is executed on the cache
  instance given at the first argument `dynamic_cache`.

  See the ["Dynamic caches"](#module-dynamic-caches) section in the
  module documentation for more information.

  ## Examples

      MyCache.info(MyCache1, :all, [])

  """
  @doc group: "Info API"
  @callback info(dynamic_cache(), spec :: info_spec(), opts()) :: ok_error_tuple(info_data())

  @doc """
  Same as `c:info/2` but raises an exception if an error occurs.
  """
  @doc group: "Info API"
  @callback info!(spec :: info_spec(), opts()) :: info_data()

  @doc """
  Same as `c:info/3` but raises an exception if an error occurs.
  """
  @doc group: "Info API"
  @callback info!(dynamic_cache(), spec :: info_spec(), opts()) :: info_data()
end
