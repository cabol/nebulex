defmodule Nebulex.Adapters.Local do
  @moduledoc ~S"""
  Adapter module for Local Generational Cache; inspired by
  [epocxy](https://github.com/duomark/epocxy).

  Generational caching using an ets table (or multiple ones when used with
  `:shards`) for each generation of cached data. Accesses hit the newer
  generation first, and migrate from the older generation to the newer
  generation when retrieved from the stale table. When a new generation
  is started, the oldest one is deleted. This is a form of mass garbage
  collection which avoids using timers and expiration of individual
  cached elements.

  This implementation of generation cache uses only two generations
  (which is more than enough) also referred like the `newer` and
  the `older`.

  ## Overall features

    * Configurable backend (`ets` or `:shards`).
    * Expiration – A status based on TTL (Time To Live) option. To maintain
      cache performance, expired entries may not be immediately removed or
      evicted, they are expired or evicted on-demand, when the key is read.
    * Eviction – [Generational Garbage Collection][gc].
    * Sharding – For intensive workloads, the Cache may also be partitioned
      (by using `:shards` backend and specifying the `:partitions` option).
    * Support for transactions via Erlang global name registration facility.
    * Support for stats.

  [gc]: http://hexdocs.pm/nebulex/Nebulex.Adapters.Local.Generation.html

  ## Options

  This adapter supports the following options and all of them can be given via
  the cache configuration:

    * `:backend` - Defines the backend or storage to be used for the adapter.
      Supported backends are: `:ets` and `:shards`. Defaults to `:ets`.

    * `:read_concurrency` - (boolean) Since this adapter uses ETS tables
      internally, this option is used when a new table is created; see
      `:ets.new/2`. Defaults to `true`.

    * `:write_concurrency` - (boolean) Since this adapter uses ETS tables
      internally, this option is used when a new table is created; see
      `:ets.new/2`. Defaults to `true`.

    * `:compressed` - (boolean) This option is used when a new ETS table is
      created and it defines whether or not it includes X as an option; see
      `:ets.new/2`. Defaults to `false`.

    * `:backend_type` - This option defines the type of ETS to be used
      (Defaults to `:set`). However, it is highly recommended to keep the
      default value, since there are commands not supported (unexpected
      exception may be raised) for types like `:bag` or `: duplicate_bag`.
      Please see the [ETS](https://erlang.org/doc/man/ets.html) docs
      for more information.

    * `:partitions` - If it is set, an integer > 0 is expected, otherwise,
      it defaults to `System.schedulers_online()`. This option is only
      available for `:shards` backend.

    * `:gc_interval` - If it is set, an integer > 0 is expected defining the
      interval time in milliseconds to garbage collection to run, delete the
      oldest generation and create a new one. If this option is not set,
      garbage collection is never executed, so new generations must be
      created explicitly, e.g.: `MyCache.new_generation(opts)`.

    * `:max_size` - If it is set, an integer > 0 is expected defining the
      max number of cached entries (cache limit). If it is not set (`nil`),
      the check to release memory is not performed (the default).

    * `:allocated_memory` - If it is set, an integer > 0 is expected defining
      the max size in bytes allocated for a cache generation. When this option
      is set and the configured value is reached, a new cache generation is
      created so the oldest is deleted and force releasing memory space.
      If it is not set (`nil`), the cleanup check to release memory is
      not performed (the default).

    * `:gc_cleanup_min_timeout` - An integer > 0 defining the min timeout in
      milliseconds for triggering the next cleanup and memory check. This will
      be the timeout to use when either the max size or max allocated memory
      is reached. Defaults to `10_000` (10 seconds).

    * `:gc_cleanup_max_timeout` - An integer > 0 defining the max timeout in
      milliseconds for triggering the next cleanup and memory check. This is
      the timeout used when the cache starts and there are few entries or the
      consumed memory is near to `0`. Defaults to `600_000` (10 minutes).

  ## Usage

  `Nebulex.Cache` is the wrapper around the cache. We can define a
  local cache as follows:

      defmodule MyApp.LocalCache do
        use Nebulex.Cache,
          otp_app: :my_app,
          adapter: Nebulex.Adapters.Local
      end

  Where the configuration for the cache must be in your application
  environment, usually defined in your `config/config.exs`:

      config :my_app, MyApp.LocalCache,
        gc_interval: :timer.hours(12),
        max_size: 1_000_000,
        allocated_memory: 2_000_000_000,
        gc_cleanup_min_timeout: :timer.seconds(10),
        gc_cleanup_max_timeout: :timer.minutes(10)

  For intensive workloads, the Cache may also be partitioned using `:shards`
  as cache backend (`backend: :shards`) and configuring the desired number of
  partitions via the `:partitions` option. Defaults to
  `System.schedulers_online()`.

      config :my_app, MyApp.LocalCache,
        gc_interval: :timer.hours(12),
        max_size: 1_000_000,
        allocated_memory: 2_000_000_000,
        gc_cleanup_min_timeout: :timer.seconds(10),
        gc_cleanup_max_timeout: :timer.minutes(10),
        backend: :shards,
        partitions: System.schedulers_online() * 2

  If your application was generated with a supervisor (by passing `--sup`
  to `mix new`) you will have a `lib/my_app/application.ex` file containing
  the application start callback that defines and starts your supervisor.
  You just need to edit the `start/2` function to start the cache as a
  supervisor on your application's supervisor:

      def start(_type, _args) do
        children = [
          {MyApp.LocalCache, []},
          ...
        ]

  See `Nebulex.Cache` for more information.

  ## Eviction configuration

  This section is to understand a bit better how the different configuration
  options work and have an idea what values to set; especially if it is the
  first time using Nebulex.

  ### `:ttl` option

  The `:ttl` option that is used to set the expiration time for a key, it
  doesn't work as eviction mechanism, since the local adapter implements a
  generational cache, the options that control the eviction process are:
  `:gc_interval`, `:gc_cleanup_min_timeout`, `:gc_cleanup_max_timeout`,
  `:max_size` and `:allocated_memory`. The `:ttl` is evaluated on-demand
  when a key is retrieved, and at that moment if it s expired, then remove
  it from the cache, hence, it can not be used as eviction method, it is
  more for keep the integrity and consistency in the cache. For this reason,
  it is highly recommended to configure always the eviction options mentioned
  before.

  ### Caveats when using `:ttl` option:

    * When using the `:ttl` option, ensure it is less than `:gc_interval`,
      otherwise, there may be a situation where the key is evicted and the
      `:ttl` hasn't happened yet (maybe because the garbage collector ran
      before the key had been fetched).
    * Assuming you have `:gc_interval` set to 2 hrs, then you put a new key
      with `:ttl` set to 1 hr, and 1 minute later the GC runs, that key will
      be moved to the older generation so it can be yet retrieved. On the other
      hand, if the key is never fetched till the next GC cycle (causing moving
      it to the newer generation), since the key is already in the oldest
      generation it will be evicted from the cache so it won't be retrievable
      anymore.

  ### Garbage collection or eviction options

  This adapter implements a generational cache, which means its main eviction
  mechanism is pushing a new cache generation and remove the oldest one. In
  this way, we ensure only the most frequently used keys are always available
  in the newer generation and the the least frequently used are evicted when
  the garbage collector runs, and the garbage collector is triggered uppon
  these conditions:

    * When the time interval defined by `:gc_interval` is completed.
      This makes the garbage-collector process to run creating a new
      generation and forcing to delete the oldest one.
    * When the "cleanup" timeout expires, and then the limits `:max_size`
      and `:allocated_memory` are checked, if one of those is reached,
      then the garbage collector runs (a new generation is created and
      the oldest one is deleted). The cleanup timeout is controlled by
      `:gc_cleanup_min_timeout` and `:gc_cleanup_max_timeout`, it works
      with an inverse linear backoff, which means the timeout is inverse
      proportional to the memory growth; the bigger the cache size is,
      the shorter the cleanup timeout will be.

  ### First-time configuration

  For configuring the cache with accurate and/or good values it is important
  to know several things in advance, like for example the size of an entry
  in average so we can calculate a good value for max size and/or allocated
  memory, how intensive will be the load in terms of reads and writes, etc.
  The problem is most of these aspects are unknown when it is a new app or
  we are using the cache for the first time. Therefore, the following
  recommendations will help you to configure the cache for the first time:

    * When configuring the `:gc_interval`, think about how that often the
      least frequently used entries should be evicted, or what is the desired
      retention period for the cached entries. For example, if `:gc_interval`
      is set to 1 hr, it means you will keep in cache only those entries that
      are retrieved periodically within a 2 hr period; `gc_interval * 2`,
      being 2 the number of generations. Longer than that, the GC will
      ensure is always evicted (the oldest generation is always deleted).
      If it is the first time using Nebulex, perhaps you can start with
      `gc_interval: :timer.hours(12)` (12 hrs), so the max retention
      period for the keys will be 1 day; but ensure you also set either the
      `:max_size` or `:allocated_memory`.
    * It is highly recommended to set either `:max_size` or `:allocated_memory`
      to ensure the oldest generation is deleted (least frequently used keys
      are evicted) when one of these limits is reached and also to avoid
      running out of memory. For example, for the `:allocated_memory` we can
      set 25% of the total memory, and for the `:max_size` something between
      `100_000` and `1_000_000`.
    * For `:gc_cleanup_min_timeout` we can set `10_000`, which means when the
      cache is reaching the size or memory limit, the polling period for the
      cleanup process will be 10 seconds. And for `:gc_cleanup_max_timeout`
      we can set `600_000`, which means when the cache is almost empty the
      polling period will be close to 10 minutes.

  ## Stats

  This adapter does support stats by using the default implementation
  provided by `Nebulex.Adapter.Stats`. The adapter also uses the
  `Nebulex.Telemetry.StatsHandler` to aggregate the stats and keep
  them updated. Therefore, it requires the Telemetry events are emitted
  by the adapter (the `:telemetry` option should not be set to `false`
  so the Telemetry events can be dispatched), otherwise, stats won't
  work properly.

  ## Queryable API

  The adapter supports as query parameter the following values:

    * `query` - `nil | :unexpired | :expired | :ets.match_spec()`

  Internally, an entry is represented by the tuple `{key, val, vsn, exp}`,
  which means the match pattern within the `:ets.match_spec()` must be
  something like `{:"$1", :"$2", :"$3", :"$4"}`. In order to make query
  building easier, you can use `Ex2ms` library.

  ## Examples

      # built-in queries
      MyCache.all()
      MyCache.all(:unexpired)
      MyCache.all(:expired)

      # using a custom match spec (all values > 10)
      spec = [{{:_, :"$1", :"$2", :_, :_}, [{:>, :"$2", 10}], [{{:"$1", :"$2"}}]}]
      MyCache.all(spec)

      # using Ex2ms
      import Ex2ms

      spec =
        fun do
          {_, key, value, _, _} when value > 10 -> {key, value}
        end

      MyCache.all(spec)

  The `:return` option applies only for built-in queries, such as:
  `nil | :unexpired | :expired`, if you are using a custom `:ets.match_spec()`,
  the return value depends on it.

  The same applies to the `stream` function.

  ## Extended API (convenience functions)

  This adapter provides some additional convenience functions to the
  `Nebulex.Cache` API.

  Creating new generations:

      MyCache.new_generation()
      MyCache.new_generation(reset_timer: false)

  Retrieving the current generations:

      MyCache.generations()

  Retrieving the newer generation:

      MyCache.newer_generation()

  """

  # Provide Cache Implementation
  @behaviour Nebulex.Adapter
  @behaviour Nebulex.Adapter.Entry
  @behaviour Nebulex.Adapter.Queryable

  # Inherit default transaction implementation
  use Nebulex.Adapter.Transaction

  # Inherit default persistence implementation
  use Nebulex.Adapter.Persistence

  # Inherit default stats implementation
  use Nebulex.Adapter.Stats

  import Nebulex.Adapter
  import Nebulex.Helpers
  import Record

  alias Nebulex.Adapter.Stats
  alias Nebulex.Adapters.Local.{Backend, Generation, Metadata}
  alias Nebulex.{Entry, Time}

  # Cache Entry
  defrecord(:entry,
    key: nil,
    value: nil,
    touched: nil,
    ttl: nil
  )

  # Supported Backends
  @backends ~w(ets shards)a

  # Inline common instructions
  @compile {:inline, list_gen: 1, newer_gen: 1, fetch_entry: 3, pop_entry: 3}

  ## Nebulex.Adapter

  @impl true
  defmacro __before_compile__(_env) do
    quote do
      @doc """
      A convenience function for creating new generations.
      """
      def new_generation(opts \\ []) do
        Generation.new(get_dynamic_cache(), opts)
      end

      @doc """
      A convenience function for reset the GC timer.
      """
      def reset_generation_timer do
        Generation.reset_timer(get_dynamic_cache())
      end

      @doc """
      A convenience function for retrieving the current generations.
      """
      def generations do
        Generation.list(get_dynamic_cache())
      end

      @doc """
      A convenience function for retrieving the newer generation.
      """
      def newer_generation do
        Generation.newer(get_dynamic_cache())
      end
    end
  end

  @impl true
  def init(opts) do
    # Required options
    cache = Keyword.fetch!(opts, :cache)
    telemetry = Keyword.fetch!(opts, :telemetry)
    telemetry_prefix = Keyword.fetch!(opts, :telemetry_prefix)

    # Init internal metadata table
    meta_tab = opts[:meta_tab] || Metadata.init()

    # Init stats_counter
    stats_counter = Stats.init(opts)

    # Resolve the backend to be used
    backend =
      opts
      |> Keyword.get(:backend, :ets)
      |> case do
        val when val in @backends ->
          val

        val ->
          raise "expected backend: option to be one of the supported backends " <>
                  "#{inspect(@backends)}, got: #{inspect(val)}"
      end

    # Build adapter metadata
    adapter_meta = %{
      cache: cache,
      name: opts[:name] || cache,
      telemetry: telemetry,
      telemetry_prefix: telemetry_prefix,
      meta_tab: meta_tab,
      stats_counter: stats_counter,
      backend: backend,
      started_at: DateTime.utc_now()
    }

    # Build adapter child_spec
    child_spec = Backend.child_spec(backend, [adapter_meta: adapter_meta] ++ opts)

    {:ok, child_spec, adapter_meta}
  end

  ## Nebulex.Adapter.Entry

  @impl true
  defspan fetch(adapter_meta, key, _opts) do
    adapter_meta.meta_tab
    |> list_gen()
    |> do_fetch(key, adapter_meta)
    |> return(:value)
  end

  defp do_fetch([newer], key, adapter_meta) do
    fetch_entry(newer, key, adapter_meta)
  end

  defp do_fetch([newer, older], key, adapter_meta) do
    with {:error, _} <- fetch_entry(newer, key, adapter_meta),
         {:ok, cached} <- pop_entry(older, key, adapter_meta) do
      true = adapter_meta.backend.insert(newer, cached)
      {:ok, cached}
    end
  end

  @impl true
  defspan get_all(adapter_meta, keys, opts) do
    adapter_meta = %{adapter_meta | telemetry: Map.get(adapter_meta, :in_span?, false)}

    keys
    |> Enum.reduce(%{}, fn key, acc ->
      case fetch(adapter_meta, key, opts) do
        {:ok, val} -> Map.put(acc, key, val)
        {:error, _} -> acc
      end
    end)
    |> wrap_ok()
  end

  @impl true
  defspan put(adapter_meta, key, value, ttl, on_write, _opts) do
    entry = entry(key: key, value: value, touched: Time.now(), ttl: ttl)
    wrap_ok do_put(on_write, adapter_meta.meta_tab, adapter_meta.backend, entry)
  end

  defp do_put(:put, meta_tab, backend, entry) do
    put_entries(meta_tab, backend, entry)
  end

  defp do_put(:put_new, meta_tab, backend, entry) do
    put_new_entries(meta_tab, backend, entry)
  end

  defp do_put(:replace, meta_tab, backend, entry(key: key, value: value, ttl: ttl)) do
    update_entry(meta_tab, backend, key, [{3, value}, {4, nil}, {5, ttl}])
  end

  @impl true
  defspan put_all(adapter_meta, entries, ttl, on_write, _opts) do
    entries =
      for {key, value} <- entries do
        entry(key: key, value: value, touched: Time.now(), ttl: ttl)
      end

    wrap_ok do_put_all(on_write, adapter_meta.meta_tab, adapter_meta.backend, entries)
  end

  defp do_put_all(:put, meta_tab, backend, entries) do
    put_entries(meta_tab, backend, entries)
  end

  defp do_put_all(:put_new, meta_tab, backend, entries) do
    put_new_entries(meta_tab, backend, entries)
  end

  @impl true
  defspan delete(adapter_meta, key, _opts) do
    adapter_meta.meta_tab
    |> list_gen()
    |> Enum.each(&adapter_meta.backend.delete(&1, key))
  end

  @impl true
  defspan take(adapter_meta, key, _opts) do
    adapter_meta.meta_tab
    |> list_gen()
    |> Enum.reduce_while(nil, fn gen, _acc ->
      case pop_entry(gen, key, adapter_meta) do
        {:ok, res} -> {:halt, return({:ok, res}, :value)}
        error -> {:cont, error}
      end
    end)
  end

  @impl true
  defspan update_counter(adapter_meta, key, amount, ttl, default, _opts) do
    adapter_meta.meta_tab
    |> newer_gen()
    |> adapter_meta.backend.update_counter(
      key,
      {3, amount},
      entry(key: key, value: default, touched: Time.now(), ttl: ttl)
    )
    |> wrap_ok()
  end

  @impl true
  def exists?(adapter_meta, key) do
    case fetch(adapter_meta, key, []) do
      {:ok, _} -> {:ok, true}
      {:error, _} -> {:ok, false}
    end
  end

  @impl true
  defspan ttl(adapter_meta, key) do
    with {:ok, res} <- adapter_meta.meta_tab |> list_gen() |> do_fetch(key, adapter_meta) do
      {:ok, entry_ttl(res)}
    end
  end

  defp entry_ttl(entry(ttl: :infinity)), do: :infinity

  defp entry_ttl(entry(ttl: ttl, touched: touched)) do
    ttl - (Time.now() - touched)
  end

  defp entry_ttl(entries) when is_list(entries) do
    for entry <- entries, do: entry_ttl(entry)
  end

  @impl true
  defspan expire(adapter_meta, key, ttl) do
    adapter_meta.meta_tab
    |> update_entry(adapter_meta.backend, key, [{4, Time.now()}, {5, ttl}])
    |> wrap_ok()
  end

  @impl true
  defspan touch(adapter_meta, key) do
    adapter_meta.meta_tab
    |> update_entry(adapter_meta.backend, key, [{4, Time.now()}])
    |> wrap_ok()
  end

  ## Nebulex.Adapter.Queryable

  @impl true
  defspan execute(adapter_meta, operation, query, opts) do
    do_execute(adapter_meta, operation, query, opts)
  end

  defp do_execute(%{meta_tab: meta_tab, backend: backend}, :count_all, nil, _opts) do
    meta_tab
    |> list_gen()
    |> Enum.reduce(0, fn gen, acc ->
      gen
      |> backend.info(:size)
      |> Kernel.+(acc)
    end)
    |> wrap_ok()
  end

  defp do_execute(%{meta_tab: meta_tab} = adapter_meta, :delete_all, nil, _opts) do
    with {:ok, count_all} <- do_execute(adapter_meta, :count_all, nil, []) do
      :ok = Generation.delete_all(meta_tab)
      {:ok, count_all}
    end
  end

  defp do_execute(%{meta_tab: meta_tab, backend: backend}, operation, query, opts) do
    with {:ok, query} <- validate_match_spec(query, opts) do
      query = maybe_match_spec_return_true(query, operation)

      {reducer, acc_in} =
        case operation do
          :all -> {&(backend.select(&1, query) ++ &2), []}
          :count_all -> {&(backend.select_count(&1, query) + &2), 0}
          :delete_all -> {&(backend.select_delete(&1, query) + &2), 0}
        end

      meta_tab
      |> list_gen()
      |> Enum.reduce(acc_in, reducer)
      |> wrap_ok()
    end
  end

  @impl true
  defspan stream(adapter_meta, query, opts) do
    with {:ok, query} <- validate_match_spec(query, opts) do
      adapter_meta
      |> do_stream(query, Keyword.get(opts, :page_size, 20))
      |> wrap_ok()
    end
  end

  defp do_stream(%{meta_tab: meta_tab, backend: backend}, match_spec, page_size) do
    Stream.resource(
      fn ->
        [newer | _] = generations = list_gen(meta_tab)
        result = backend.select(newer, match_spec, page_size)
        {result, generations}
      end,
      fn
        {:"$end_of_table", [_gen]} ->
          {:halt, []}

        {:"$end_of_table", [_gen | generations]} ->
          result =
            generations
            |> hd()
            |> backend.select(match_spec, page_size)

          {[], {result, generations}}

        {{elements, cont}, [_ | _] = generations} ->
          {elements, {backend.select(cont), generations}}
      end,
      & &1
    )
  end

  ## Nebulex.Adapter.Persistence

  @impl true
  defspan dump(adapter_meta, path, opts) do
    super(adapter_meta, path, opts)
  end

  @impl true
  defspan load(adapter_meta, path, opts) do
    super(adapter_meta, path, opts)
  end

  ## Nebulex.Adapter.Transaction

  @impl true
  defspan transaction(adapter_meta, opts, fun) do
    super(adapter_meta, opts, fun)
  end

  @impl true
  defspan in_transaction?(adapter_meta) do
    super(adapter_meta)
  end

  ## Nebulex.Adapter.Stats

  @impl true
  defspan stats(adapter_meta) do
    with {:ok, %Nebulex.Stats{} = stats} <- super(adapter_meta) do
      {:ok, %{stats | metadata: Map.put(stats.metadata, :started_at, adapter_meta.started_at)}}
    end
  end

  ## Helpers

  defp list_gen(meta_tab) do
    Metadata.fetch!(meta_tab, :generations)
  end

  defp newer_gen(meta_tab) do
    meta_tab
    |> Metadata.fetch!(:generations)
    |> hd()
  end

  defmacrop backend_call(adapter_meta, fun, tab, key) do
    quote do
      case unquote(adapter_meta).backend.unquote(fun)(unquote(tab), unquote(key)) do
        [] ->
          wrap_error Nebulex.KeyError, key: unquote(key), cache: unquote(adapter_meta).name

        [entry(ttl: :infinity) = entry] ->
          {:ok, entry}

        [entry(touched: touched, ttl: ttl) = entry] ->
          validate_ttl(entry, unquote(tab), unquote(adapter_meta))

        entries when is_list(entries) ->
          now = Time.now()
          {:ok, for(entry(touched: touched, ttl: ttl) = e <- entries, now - touched < ttl, do: e)}
      end
    end
  end

  defp validate_ttl(entry(key: key, touched: touched, ttl: ttl) = entry, tab, adapter_meta) do
    if Time.now() - touched >= ttl do
      true = adapter_meta.backend.delete(tab, key)
      wrap_error Nebulex.KeyError, key: key, cache: adapter_meta.name, reason: :expired
    else
      {:ok, entry}
    end
  end

  defp fetch_entry(tab, key, adapter_meta) do
    backend_call(adapter_meta, :lookup, tab, key)
  end

  defp pop_entry(tab, key, adapter_meta) do
    backend_call(adapter_meta, :take, tab, key)
  end

  defp put_entries(meta_tab, backend, entry_or_entries) do
    meta_tab
    |> newer_gen()
    |> backend.insert(entry_or_entries)
  end

  defp put_new_entries(meta_tab, backend, entry_or_entries) do
    meta_tab
    |> newer_gen()
    |> backend.insert_new(entry_or_entries)
  end

  defp update_entry(meta_tab, backend, key, updates) do
    meta_tab
    |> newer_gen()
    |> backend.update_element(key, updates)
  end

  defp return({:ok, entry(value: value)}, :value) do
    {:ok, value}
  end

  defp return({:ok, entries}, :value) when is_list(entries) do
    {:ok, for(entry(value: value) <- entries, do: value)}
  end

  defp return(other, _field) do
    other
  end

  defp validate_match_spec(spec, opts) when spec in [nil, :unexpired, :expired] do
    [
      {
        entry(key: :"$1", value: :"$2", touched: :"$3", ttl: :"$4"),
        if(spec = comp_match_spec(spec), do: [spec], else: []),
        ret_match_spec(opts)
      }
    ]
    |> wrap_ok()
  end

  defp validate_match_spec(spec, _opts) do
    case :ets.test_ms({nil, nil, nil, :infinity}, spec) do
      {:ok, _result} ->
        {:ok, spec}

      {:error, _result} ->
        msg = """
        expected query to be one of:

        nil | :unexpired | :expired | :ets.match_spec()

        but got:
        """

        wrap_error Nebulex.QueryError, message: msg, query: spec
    end
  end

  defp comp_match_spec(nil),
    do: nil

  defp comp_match_spec(:unexpired),
    do: {:orelse, {:==, :"$4", :infinity}, {:<, {:-, Time.now(), :"$3"}, :"$4"}}

  defp comp_match_spec(:expired),
    do: {:not, comp_match_spec(:unexpired)}

  defp ret_match_spec(opts) do
    case Keyword.get(opts, :return, :key) do
      :key -> [:"$1"]
      :value -> [:"$2"]
      {:key, :value} -> [{{:"$1", :"$2"}}]
      :entry -> [%Entry{key: :"$1", value: :"$2", touched: :"$3", ttl: :"$4"}]
    end
  end

  defp maybe_match_spec_return_true([{pattern, conds, _ret}], operation)
       when operation in [:delete_all, :count_all] do
    [{pattern, conds, [true]}]
  end

  defp maybe_match_spec_return_true(match_spec, _operation) do
    match_spec
  end
end
