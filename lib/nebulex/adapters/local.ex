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

  ## Features

    * Configurable backend (`ets` or `:shards`).
    * Expiration – A status based on TTL (Time To Live) option. To maintain
      cache performance, expired entries may not be immediately flushed or
      evicted, they are expired or evicted on-demand, when the key is read.
    * Eviction – [Generational Garbage Collection](http://hexdocs.pm/nebulex/Nebulex.Adapters.Local.Generation.html).
    * Sharding – For intensive workloads, the Cache may also be partitioned
      (by using `:shards` backend and specifying the `:partitions` option).
    * Support for transactions via Erlang global name registration facility.

  ## Options

  This adapter supports the following options and all of them can be given via
  the cache configuration:

    * `:backend` - Defines the backend or storage to be used for the adapter.
      Supported backends are: `:ets` and `:shards`. Defaults to `:ets`.

    * `:read_concurrency` - Since this adapter uses ETS tables internally,
      this option is used when a new table is created. See `:ets.new/2`.
      Defaults to `true`.

    * `:write_concurrency` - Since this adapter uses ETS tables internally,
      this option is used when a new table is created. See `:ets.new/2`.
      Defaults to `true`.

     * `:compressed` - This option is used when a new ETS table is created and
       it defines whether or not it includes X as an option. See `:ets.new/2`.
       Defaults to `false`.

    * `:backend_type` - This option defines the type of ETS to be used
      (Defaults to `:set`). However, it is highly recommended to keep the
      default value, since there are commands not supported (unexpected
      exception may be raised) for types like `:bag` or `: duplicate_bag`.
      Please see the [ETS](https://erlang.org/doc/man/ets.html) docs
      for more information.

    * `:partitions` - The number of partitions in the Cache. This option is only
      available for `:shards` backend. Defaults to `System.schedulers_online()`.

    * `:gc_interval` - Interval time in milliseconds to garbage collection to
      run, delete the oldest generation and create a new one. If this option is
      not set, garbage collection is never executed, so new generations must be
      created explicitly, e.g.: `MyCache.new_generation(name_or_pid, opts)`.

    * `:max_size` - Max number of cached entries (cache limit). If it is not
      set (`nil`), the check to release memory is not performed (the default).

    * `:allocated_memory` - Max size in bytes allocated for a cache generation.
      If this option is set and the configured value is reached, a new cache
      generation is created so the oldest is deleted and force releasing memory
      space. If it is not set (`nil`), the cleanup check to release memory is
      not performed (the default).

    * `:gc_cleanup_min_timeout` - The min timeout in milliseconds for triggering
      the next cleanup and memory check. This will be the timeout to use when
      either the max size or max allocated memory is reached.
      Defaults to `10_000` (10 seconds).

    * `:gc_cleanup_max_timeout` - The max timeout in milliseconds for triggering
      the next cleanup and memory check. This is the timeout used when the cache
      starts and there are few entries or the consumed memory is near to `0`.
      Defaults to `600_000` (10 minutes).

  ## Example

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
        backend: :shards,
        gc_interval: :timer.seconds(3600),
        max_size: 200_000,
        allocated_memory: 2_000_000_000,
        gc_cleanup_min_timeout: 10_000,
        gc_cleanup_max_timeout: 600_000

  For intensive workloads, the Cache may also be partitioned (by using `:shards`
  backend and specifying the `:partitions` option). If partitioning is required
  then a good default is to set the number of partitions to the number of
  schedulers available (the default):

      config :my_app, MyApp.LocalCache,
        backend: :shards,
        gc_interval: :timer.seconds(3600),
        max_size: 200_000,
        allocated_memory: 2_000_000_000,
        gc_cleanup_min_timeout: 10_000,
        gc_cleanup_max_timeout: 600_000,
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
      being 2 the number of generations. Longer than that, the GC will ensure
      is always evicted (the oldest generation is always flushed/deleted).
      If it is the first time using Nebulex, perhaps you can start with
      `gc_interval: :timer.seconds(43_200)` (12 hrs), so the max retention
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
      spec = [{{:"$1", :"$2", :_, :_}, [{:>, :"$2", 10}], [{{:"$1", :"$2"}}]}]
      MyCache.all(spec)

      # using Ex2ms
      import Ex2ms

      spec =
        fun do
          {key, value, _version, _expire_at} when value > 10 -> {key, value}
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
      MyCache.new_generation(:my_cache, [])

  Retrieving the current generations:

      MyCache.generations()
      MyCache.generations(:my_cache)

  Retrieving the newer generation:

      MyCache.newer_generation()
      MyCache.newer_generation(:my_cache)

  """

  # Provide Cache Implementation
  @behaviour Nebulex.Adapter
  @behaviour Nebulex.Adapter.Entry
  @behaviour Nebulex.Adapter.Storage
  @behaviour Nebulex.Adapter.Queryable

  # Inherit default transaction implementation
  use Nebulex.Adapter.Transaction

  # Inherit default persistence implementation
  use Nebulex.Adapter.Persistence

  # Inherit default stats implementation
  use Nebulex.Adapter.Stats

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

  @compile {:inline, list_gen: 1, newer_gen: 1}

  ## Adapter

  @impl true
  defmacro __before_compile__(_env) do
    quote do
      @doc """
      A convenience function for creating new generations.
      """
      defdelegate new_generation(name_or_pid \\ __MODULE__, opts \\ []), to: Generation, as: :new

      @doc """
      A convenience function for retrieving the current generations.
      """
      defdelegate generations(name_or_pid \\ __MODULE__), to: Generation, as: :list

      @doc """
      A convenience function for retrieving the newer generation.
      """
      defdelegate newer_generation(name_or_pid \\ __MODULE__), to: Generation, as: :newer
    end
  end

  @impl true
  def init(opts) do
    # resolve the backend to be used
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

    # init internal metadata table
    meta_tab = opts[:meta_tab] || Metadata.init()

    child =
      Backend.child_spec(
        backend,
        [backend: backend, meta_tab: meta_tab] ++ opts
      )

    meta = %{
      backend: backend,
      meta_tab: meta_tab,
      stats_counter: opts[:stats_counter] || Stats.init(opts)
    }

    {:ok, child, meta}
  end

  @impl true
  def get(%{meta_tab: meta_tab, backend: backend, stats_counter: ref}, key, _opts) do
    meta_tab
    |> list_gen()
    |> do_get(key, backend, ref)
    |> return(:value)
    |> update_stats(:get, ref)
  end

  defp do_get([newer], key, backend, ref) do
    gen_fetch(newer, key, backend, ref)
  end

  defp do_get([newer, older], key, backend, ref) do
    with nil <- gen_fetch(newer, key, backend, ref),
         entry(key: ^key) = cached <- gen_fetch(older, key, backend, ref, &pop_entry/4) do
      true = backend.insert(newer, cached)
      cached
    end
  end

  defp gen_fetch(gen, key, backend, ref, fun \\ &get_entry/4) do
    gen
    |> fun.(key, nil, backend)
    |> validate_ttl(gen, backend, ref)
  end

  @impl true
  def get_all(adapter_meta, keys, _opts) do
    Enum.reduce(keys, %{}, fn key, acc ->
      if obj = get(adapter_meta, key, []),
        do: Map.put(acc, key, obj),
        else: acc
    end)
  end

  @impl true
  def put(
        %{meta_tab: meta_tab, backend: backend, stats_counter: ref},
        key,
        value,
        ttl,
        on_write,
        _opts
      ) do
    do_put(
      on_write,
      meta_tab,
      backend,
      ref,
      entry(
        key: key,
        value: value,
        touched: Time.now(),
        ttl: ttl
      )
    )
  end

  defp do_put(:put, meta_tab, backend, ref, entry) do
    meta_tab
    |> put_entries(backend, entry)
    |> update_stats(:put, ref)
  end

  defp do_put(:put_new, meta_tab, backend, ref, entry) do
    meta_tab
    |> put_new_entries(backend, entry)
    |> update_stats(:put, ref)
  end

  defp do_put(:replace, meta_tab, backend, ref, entry(key: key, value: value, ttl: ttl)) do
    meta_tab
    |> update_entry(backend, key, [{3, value}, {4, nil}, {5, ttl}])
    |> update_stats(:put, ref)
  end

  @impl true
  def put_all(
        %{meta_tab: meta_tab, backend: backend, stats_counter: ref},
        entries,
        ttl,
        on_write,
        _opts
      ) do
    touched = Time.now()

    entries =
      for {key, value} <- entries, value != nil do
        entry(key: key, value: value, touched: touched, ttl: ttl)
      end

    do_put_all(on_write, meta_tab, backend, ref, entries)
  end

  defp do_put_all(:put, meta_tab, backend, ref, entries) do
    meta_tab
    |> put_entries(backend, entries)
    |> update_stats(:put_all, {ref, entries})
  end

  defp do_put_all(:put_new, meta_tab, backend, ref, entries) do
    meta_tab
    |> put_new_entries(backend, entries)
    |> update_stats(:put_all, {ref, entries})
  end

  @impl true
  def delete(%{meta_tab: meta_tab, backend: backend, stats_counter: ref}, key, _opts) do
    meta_tab
    |> list_gen()
    |> Enum.each(&backend.delete(&1, key))
    |> update_stats(:delete, ref)
  end

  @impl true
  def take(%{meta_tab: meta_tab, backend: backend, stats_counter: ref}, key, _opts) do
    meta_tab
    |> list_gen()
    |> Enum.reduce_while(nil, fn gen, acc ->
      case pop_entry(gen, key, nil, backend) do
        nil ->
          {:cont, acc}

        res ->
          value =
            res
            |> validate_ttl(gen, backend, ref)
            |> return(:value)

          {:halt, value}
      end
    end)
    |> update_stats(:take, ref)
  end

  @impl true
  def incr(%{meta_tab: meta_tab, backend: backend, stats_counter: ref}, key, incr, ttl, opts) do
    default = get_option(opts, :default, &is_integer/1, 0)

    meta_tab
    |> newer_gen()
    |> backend.update_counter(
      key,
      {3, incr},
      entry(key: key, value: default, touched: Time.now(), ttl: ttl)
    )
    |> update_stats(:write, ref)
  end

  @impl true
  def has_key?(adapter_meta, key) do
    case get(adapter_meta, key, []) do
      nil -> false
      _ -> true
    end
  end

  @impl true
  def ttl(%{meta_tab: meta_tab, backend: backend, stats_counter: ref}, key) do
    meta_tab
    |> list_gen()
    |> do_get(key, backend, ref)
    |> return()
    |> entry_ttl()
    |> update_stats(:get, ref)
  end

  defp entry_ttl(nil), do: nil
  defp entry_ttl(entry(ttl: :infinity)), do: :infinity

  defp entry_ttl(entry(ttl: ttl, touched: touched)) do
    ttl - (Time.now() - touched)
  end

  defp entry_ttl(entries) when is_list(entries) do
    for entry <- entries, do: entry_ttl(entry)
  end

  @impl true
  def expire(%{meta_tab: meta_tab, backend: backend, stats_counter: ref}, key, ttl) do
    meta_tab
    |> update_entry(backend, key, [{4, Time.now()}, {5, ttl}])
    |> update_stats(:put, ref)
  end

  @impl true
  def touch(%{meta_tab: meta_tab, backend: backend, stats_counter: ref}, key) do
    meta_tab
    |> update_entry(backend, key, [{4, Time.now()}])
    |> update_stats(:put, ref)
  end

  @impl true
  def size(%{meta_tab: meta_tab, backend: backend}) do
    meta_tab
    |> list_gen()
    |> Enum.reduce(0, fn gen, acc ->
      gen
      |> backend.info(:size)
      |> Kernel.+(acc)
    end)
  end

  @impl true
  def flush(%{meta_tab: meta_tab, stats_counter: ref}) do
    meta_tab
    |> Generation.flush()
    |> update_stats(:flush, ref)
  end

  ## Queryable

  @impl true
  def all(%{meta_tab: meta_tab, backend: backend}, query, opts) do
    query = validate_match_spec(query, opts)

    for gen <- list_gen(meta_tab),
        elems <- backend.select(gen, query),
        do: elems
  end

  @impl true
  def stream(adapter_meta, query, opts) do
    query
    |> validate_match_spec(opts)
    |> do_stream(adapter_meta, Keyword.get(opts, :page_size, 20))
  end

  defp do_stream(match_spec, %{meta_tab: meta_tab, backend: backend}, page_size) do
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

  ## Helpers

  defp list_gen(meta_tab) do
    Metadata.fetch!(meta_tab, :generations)
  end

  defp newer_gen(meta_tab) do
    meta_tab
    |> Metadata.fetch!(:generations)
    |> hd()
  end

  defp get_entry(tab, key, default, backend) do
    case backend.lookup(tab, key) do
      [] -> default
      [entry] -> entry
      entries -> entries
    end
  end

  defp pop_entry(tab, key, default, backend) do
    case backend.take(tab, key) do
      [] -> default
      [entry] -> entry
      entries -> entries
    end
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

  defp return(entry_or_entries, field \\ nil)

  defp return(nil, _field), do: nil
  defp return(entry(value: value), :value), do: value
  defp return(entry(key: _) = entry, _field), do: entry

  defp return(entries, field) when is_list(entries) do
    for entry <- entries, do: return(entry, field)
  end

  defp validate_ttl(nil, _, _, _), do: nil
  defp validate_ttl(entry(ttl: :infinity) = entry, _, _, _), do: entry

  defp validate_ttl(entry(key: key, touched: touched, ttl: ttl) = entry, gen, backend, ref) do
    if Time.now() - touched >= ttl do
      true = backend.delete(gen, key)
      update_stats(nil, :expired, ref)
    else
      entry
    end
  end

  defp validate_ttl(entries, gen, backend, ref) when is_list(entries) do
    Enum.filter(entries, fn entry ->
      not is_nil(validate_ttl(entry, gen, backend, ref))
    end)
  end

  defp validate_match_spec(spec, opts) when spec in [nil, :unexpired, :expired] do
    [
      {
        entry(key: :"$1", value: :"$2", touched: :"$3", ttl: :"$4"),
        if(spec = comp_match_spec(spec), do: [spec], else: []),
        ret_match_spec(opts)
      }
    ]
  end

  defp validate_match_spec(spec, _opts) do
    case :ets.test_ms({nil, nil, nil, :infinity}, spec) do
      {:ok, _result} ->
        spec

      {:error, _result} ->
        raise Nebulex.QueryError, message: "invalid match spec", query: spec
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

  defp update_stats(value, _action, nil), do: value
  defp update_stats(value, _action, {nil, _}), do: value

  defp update_stats(nil, :get, counter_ref) do
    :ok = Stats.incr(counter_ref, :misses)
    nil
  end

  defp update_stats(value, :get, counter_ref) do
    :ok = Stats.incr(counter_ref, :hits)
    value
  end

  defp update_stats(value, :expired, counter_ref) do
    :ok = Stats.incr(counter_ref, :evictions)
    :ok = Stats.incr(counter_ref, :expirations)
    value
  end

  defp update_stats(value, :write, counter_ref) do
    :ok = Stats.incr(counter_ref, :writes)
    value
  end

  defp update_stats(true, :put, counter_ref) do
    :ok = Stats.incr(counter_ref, :writes)
    true
  end

  defp update_stats(true, :put_all, {counter_ref, entries}) do
    :ok = Stats.incr(counter_ref, :writes, length(entries))
    true
  end

  defp update_stats(value, :delete, counter_ref) do
    :ok = Stats.incr(counter_ref, :evictions)
    value
  end

  defp update_stats(nil, :take, counter_ref) do
    :ok = Stats.incr(counter_ref, :misses)
    nil
  end

  defp update_stats(value, :take, counter_ref) do
    :ok = Stats.incr(counter_ref, :hits)
    :ok = Stats.incr(counter_ref, :evictions)
    value
  end

  defp update_stats(value, :flush, counter_ref) do
    :ok = Stats.incr(counter_ref, :evictions, value)
    value
  end

  defp update_stats(value, _action, _counter_ref) do
    value
  end
end
