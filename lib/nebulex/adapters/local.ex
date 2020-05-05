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

  ## Features

    * Configurable backend (`ets` or `:shards`).
    * Expiration – A status based on TTL (Time To Live) option. To maintain
      cache performance, expired entries may not be immediately flushed or
      evicted, they are expired or evicted on-demand, when the key is read.
    * Eviction – [Generational Garbage Collection](http://hexdocs.pm/nebulex/Nebulex.Adapters.Local.Generation.html).
    * Sharding – For intensive workloads, the Cache may also be partitioned
      (by using `:shards` backend and specifying the `:partitions` option).
    * Support for transactions via Erlang global name registration facility.

  ## Compile-Time Options

  In addition to `:otp_app` and `:adapter`, this adapter supports the next
  compile-time options:

    * `:backend` - Defines the backend or storage to be used for the adapter.
      Supported backends are: `:ets` and `:shards`. Defaults to `:ets`.

  ## Config Options

  These options can be set through the config file:

    * `:generations` - Max number of Cache generations. Defaults to `2`
      (normally two generations is enough).

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
      created explicitly, e.g.: `MyCache.new_generation([])`.

    * `:allocated_memory` - Max size in bytes allocated for a cache generation.
      If this option is set and the configured value is reached, a new
      generation is created so the oldest is deleted and force releasing memory
      space. If it is not set (or set to `nil`), the cleanup check to release
      memory is not performed (the default).

    * `:gc_cleanup_min_timeout` - The min timeout in milliseconds for triggering
      the next cleanup and memory check. This will be the timeout to use when
      the max allocated memory is reached. Defaults to `30_000`.

    * `:gc_cleanup_max_timeout` - The max timeout in milliseconds for triggering
      the next cleanup and memory check. This is the timeout used when the cache
      starts or the consumed memory is `0`. Defaults to `300_000`.

  ## Example

  `Nebulex.Cache` is the wrapper around the cache. We can define a
  local cache as follows:

      defmodule MyApp.LocalCache do
        use Nebulex.Cache,
          otp_app: :my_app,
          adapter: Nebulex.Adapters.Local,
          backend: :shards
      end

  Where the configuration for the cache must be in your application
  environment, usually defined in your `config/config.exs`:

      config :my_app, MyApp.LocalCache,
        gc_interval: 3_600_000,
        allocated_memory: 2_000_000_000,
        gc_cleanup_min_timeout: 10_000,
        gc_cleanup_max_timeout: 900_000

  For intensive workloads, the Cache may also be partitioned (by using `:shards`
  backend and specifying the `:partitions` option). If partitioning is required
  then a good default is to set the number of partitions to the number of
  schedulers available (the default):

      config :my_app, MyApp.LocalCache,
        gc_interval: 3_600_000,
        allocated_memory: 2_000_000_000,
        gc_cleanup_min_timeout: 10_000,
        gc_cleanup_max_timeout: 900_000,
        partitions: System.schedulers_online()

  For more information about the usage, check out `Nebulex.Cache`.

  ## Extended API

  This adapter provides some additional functions to the `Nebulex.Cache` API.
  Most of these functions are used internally by the adapter, but there is one
  function which is indeed provided to be used from the Cache API, and it is
  the function to create new generations: `new_generation/1`.

      MyApp.LocalCache.new_generation

  Other additional function that might be useful is: `__metadata__`,
  which is used to retrieve the Cache Metadata.

      MyApp.LocalCache.__metadata__

  The rest of the functions as we mentioned before, are for internal use.

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
  `nil | :unexpired | :expired`, if you are using a
  custom `:ets.match_spec()`, the return value depends on it.

  The same applies to `stream` function.
  """

  # Provide Cache Implementation
  @behaviour Nebulex.Adapter
  @behaviour Nebulex.Adapter.Queryable

  # Inherit default transaction implementation
  use Nebulex.Adapter.Transaction

  # Inherit default persistence implementation
  use Nebulex.Adapter.Persistence

  import Record

  alias Nebulex.Adapters.Local.{Backend, Generation}
  alias Nebulex.{Entry, Time}

  # Cache Entry
  defrecord(:entry,
    key: nil,
    value: nil,
    touched: nil,
    ttl: nil
  )

  # Suported Backends
  @backends ~w(ets shards)a

  ## Adapter

  @impl true
  defmacro __before_compile__(env) do
    opts = Module.get_attribute(env.module, :opts)
    backend = Keyword.get(opts, :backend, :ets)

    unless backend in @backends do
      raise ArgumentError, "supported backends: #{inspect(@backends)}, got: #{inspect(backend)}"
    end

    quote do
      alias Nebulex.Adapters.Local.Generation
      alias Nebulex.Adapters.Local.Metadata

      @doc """
      A convenience function for getting the current backend.
      """
      def __backend__, do: unquote(backend)

      @doc """
      A convenience function for getting the Cache metadata.
      """
      def __metadata__, do: Metadata.get(__MODULE__)

      @doc """
      A convenience function for creating new generations.
      """
      def new_generation(opts \\ []) do
        Generation.new(__MODULE__, opts)
      end
    end
  end

  @impl true
  def init(opts) do
    cache = Keyword.fetch!(opts, :cache)
    {:ok, Backend.child_spec(cache, opts)}
  end

  @impl true
  def get(cache, key, _opts) do
    cache.__metadata__.generations
    |> do_get(key, cache)
    |> return(:value)
  end

  defp do_get([newest | _] = generations, key, cache) do
    with nil <- fetch_from_gen(newest, key, cache) do
      generations
      |> retrieve_from_gens(key, cache)
      |> elem(1)
    end
  end

  defp fetch_from_gen(gen, key, cache, fun \\ &get_entry/4) do
    fun
    |> apply([gen, key, nil, cache])
    |> validate_ttl(gen, cache)
  end

  defp retrieve_from_gens([newest | olders], key, cache) do
    Enum.reduce_while(olders, {newest, nil}, fn gen, {newer, _} ->
      case fetch_from_gen(gen, key, cache, &pop_entry/4) do
        nil ->
          {:cont, {gen, nil}}

        cached ->
          true = cache.__backend__.insert(newer, cached)
          {:halt, {gen, cached}}
      end
    end)
  end

  @impl true
  def get_all(cache, keys, _opts) do
    Enum.reduce(keys, %{}, fn key, acc ->
      if obj = get(cache, key, []),
        do: Map.put(acc, key, obj),
        else: acc
    end)
  end

  @impl true
  def put(cache, key, value, ttl, on_write, _opts) do
    do_put(
      on_write,
      cache,
      entry(
        key: key,
        value: value,
        touched: Time.now(),
        ttl: ttl
      )
    )
  end

  defp do_put(:put, cache, entry) do
    put_entries(cache, entry)
  end

  defp do_put(:put_new, cache, entry) do
    put_new_entries(cache, entry)
  end

  defp do_put(:replace, cache, entry(key: key, value: value, ttl: ttl)) do
    update_entry(cache, key, [{3, value}, {4, nil}, {5, ttl}])
  end

  @impl true
  def put_all(cache, entries, ttl, on_write, _opts) do
    touched = Time.now()

    entries =
      for {key, value} <- entries, value != nil do
        entry(key: key, value: value, touched: touched, ttl: ttl)
      end

    do_put_all(cache, entries, on_write)
  end

  defp do_put_all(cache, entries, :put) do
    put_entries(cache, entries)
  end

  defp do_put_all(cache, entries, :put_new) do
    put_new_entries(cache, entries)
  end

  @impl true
  def delete(cache, key, _opts) do
    Enum.each(cache.__metadata__.generations, &cache.__backend__.delete(&1, key))
  end

  @impl true
  def take(cache, key, _opts) do
    Enum.reduce_while(cache.__metadata__.generations, nil, fn gen, acc ->
      case pop_entry(gen, key, nil, cache) do
        nil ->
          {:cont, acc}

        res ->
          value =
            res
            |> validate_ttl(gen, cache)
            |> return(:value)

          {:halt, value}
      end
    end)
  end

  @impl true
  def incr(cache, key, incr, ttl, _opts) do
    cache.__metadata__.generations
    |> hd()
    |> cache.__backend__.update_counter(
      key,
      {3, incr},
      entry(key: key, value: 0, touched: Time.now(), ttl: ttl)
    )
  end

  @impl true
  def has_key?(cache, key) do
    case get(cache, key, []) do
      nil -> false
      _ -> true
    end
  end

  @impl true
  def ttl(cache, key) do
    cache.__metadata__.generations
    |> do_get(key, cache)
    |> return()
    |> entry_ttl()
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
  def expire(cache, key, ttl) do
    update_entry(cache, key, [{4, Time.now()}, {5, ttl}])
  end

  @impl true
  def touch(cache, key) do
    update_entry(cache, key, [{4, Time.now()}])
  end

  @impl true
  def size(cache) do
    Enum.reduce(cache.__metadata__.generations, 0, fn gen, acc ->
      gen
      |> cache.__backend__.info(:size)
      |> Kernel.+(acc)
    end)
  end

  @impl true
  def flush(cache) do
    Generation.flush(cache)
  end

  ## Queryable

  @impl true
  def all(cache, query, opts) do
    query = validate_match_spec(query, opts)

    for gen <- cache.__metadata__.generations,
        elems <- cache.__backend__.select(gen, query),
        do: elems
  end

  @impl true
  def stream(cache, query, opts) do
    query
    |> validate_match_spec(opts)
    |> do_stream(cache, Keyword.get(opts, :page_size, 10))
  end

  defp do_stream(match_spec, cache, page_size) do
    Stream.resource(
      fn ->
        [newer | _] = generations = cache.__metadata__.generations
        result = cache.__backend__.select(newer, match_spec, page_size)
        {result, generations}
      end,
      fn
        {:"$end_of_table", [_gen]} ->
          {:halt, []}

        {:"$end_of_table", [_gen | generations]} ->
          result =
            generations
            |> hd()
            |> cache.__backend__.select(match_spec, page_size)

          {[], {result, generations}}

        {{elements, cont}, [_ | _] = generations} ->
          {elements, {cache.__backend__.select(cont), generations}}
      end,
      & &1
    )
  end

  ## Transaction

  @impl true
  def transaction(cache, opts, fun) do
    keys = Keyword.get(opts, :keys, [])
    nodes = Keyword.get(opts, :nodes, [node()])
    retries = Keyword.get(opts, :retries, :infinity)
    do_transaction(cache, keys, nodes, retries, fun)
  end

  ## Helpers

  defp get_entry(tab, key, default, cache) do
    case cache.__backend__.lookup(tab, key) do
      [] -> default
      [entry] -> entry
      entries -> entries
    end
  end

  defp pop_entry(tab, key, default, cache) do
    case cache.__backend__.take(tab, key) do
      [] -> default
      [entry] -> entry
      entries -> entries
    end
  end

  defp put_entries(cache, entry_or_entries) do
    cache.__metadata__.generations
    |> hd()
    |> cache.__backend__.insert(entry_or_entries)
  end

  defp put_new_entries(cache, entry_or_entries) do
    cache.__metadata__.generations
    |> hd()
    |> cache.__backend__.insert_new(entry_or_entries)
  end

  defp update_entry(cache, key, updates) do
    cache.__metadata__.generations
    |> hd()
    |> cache.__backend__.update_element(key, updates)
  end

  defp return(entry_or_entries, field \\ nil)
  defp return(nil, _field), do: nil
  defp return(entry(value: value), :value), do: value
  defp return(entry(key: _) = entry, _field), do: entry

  defp return(entries, field) when is_list(entries) do
    for entry <- entries, do: return(entry, field)
  end

  defp validate_ttl(nil, _, _), do: nil
  defp validate_ttl(entry(ttl: :infinity) = entry, _, _), do: entry

  defp validate_ttl(entry(key: key, touched: touched, ttl: ttl) = entry, gen, cache) do
    if Time.now() - touched >= ttl do
      true = cache.__backend__.delete(gen, key)
      nil
    else
      entry
    end
  end

  defp validate_ttl(entries, gen, cache) when is_list(entries) do
    Enum.filter(entries, fn entry ->
      not is_nil(validate_ttl(entry, gen, cache))
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
      :entry -> [%Entry{key: :"$1", value: :"$2", touched: :"$3", ttl: :"$4"}]
    end
  end
end
