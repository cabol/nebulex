defmodule Nebulex.Adapters.Local do
  @moduledoc """
  Adapter module for Local Generational Cache.

  It uses [Shards](https://github.com/cabol/shards) as in-memory backend
  (ETS tables are used internally).

  ## Features

    * Support for generational cache – inspired by
      [epocxy](https://github.com/duomark/epocxy).

    * Support for Sharding – handled by `:shards`.

    * Support for garbage collection via `Nebulex.Adapters.Local.Generation`

    * Support for transactions via Erlang global name registration facility

  ## Options

  These options can be set through the config file:

    * `:n_shards` - The number of partitions for each Cache generation table.
      Defaults to `:erlang.system_info(:schedulers_online)`.

    * `:n_generations` - Max number of Cache generations, defaults to `2`.

    * `:read_concurrency` - Indicates whether the tables that `:shards`
      creates uses `:read_concurrency` or not (default: true).

    * `:write_concurrency` - Indicates whether the tables that `:shards`
      creates uses `:write_concurrency` or not (default: true).

    * `:gc_interval` - Interval time in seconds to garbage collection to run,
      delete the oldest generation and create a new one. If this option is
      not set, garbage collection is never executed, so new generations
      must be created explicitly, e.g.: `MyCache.new_generation([])`.

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
        n_shards: 2,
        gc_interval: 3600,
        write_concurrency: true

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

    * `query` - `nil | :all_unexpired | :all_expired | :ets.match_spec()`

  Internally, an entry is represented by the tuple `{key, val, vsn, exp}`,
  which means the match pattern within the `:ets.match_spec()` must be
  something like `{:"$1", :"$2", :"$3", :"$4"}`. In order to make query
  building easier, you can use `Ex2ms` library.

  ## Examples

      # built-in queries
      MyCache.all()
      MyCache.all(:all_unexpired)
      MyCache.all(:all_expired)

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
  `nil | :all_unexpired | :all_expired`, if you are using a
  custom `:ets.match_spec()`, the return value depends on it.

  The same applies to `stream` function.
  """

  # Inherit default transaction implementation
  use Nebulex.Adapter.Transaction

  # Provide Cache Implementation
  @behaviour Nebulex.Adapter
  @behaviour Nebulex.Adapter.Queryable

  alias Nebulex.Adapters.Local.Generation
  alias Nebulex.Object
  alias :shards_local, as: Local

  ## Adapter

  @impl true
  defmacro __before_compile__(env) do
    cache = env.module
    config = Module.get_attribute(cache, :config)
    n_shards = Keyword.get(config, :n_shards, System.schedulers_online())
    r_concurrency = Keyword.get(config, :read_concurrency, true)
    w_concurrency = Keyword.get(config, :write_concurrency, true)
    shards_sup_name = Module.concat([cache, ShardsSupervisor])

    quote do
      alias Nebulex.Adapters.Local.Generation
      alias Nebulex.Adapters.Local.Metadata

      def __metadata__, do: Metadata.get(__MODULE__)

      def __state__, do: :shards_state.new(unquote(n_shards))

      def __shards_sup_name__, do: unquote(shards_sup_name)

      def __tab_opts__ do
        [
          n_shards: unquote(n_shards),
          sup_name: unquote(shards_sup_name),
          read_concurrency: unquote(r_concurrency),
          write_concurrency: unquote(w_concurrency)
        ]
      end

      def new_generation(opts \\ []) do
        Generation.new(__MODULE__, opts)
      end
    end
  end

  @impl true
  def init(opts) do
    cache = Keyword.fetch!(opts, :cache)

    children = [
      %{
        id: cache.__shards_sup_name__,
        start: {:shards_sup, :start_link, [cache.__shards_sup_name__]},
        type: :supervisor
      },
      %{
        id: Generation,
        start: {Generation, :start_link, [cache, opts]}
      }
    ]

    {:ok, children}
  end

  @impl true
  def get(cache, key, _opts) do
    cache.__metadata__.generations
    |> do_get(cache, key)
    |> entry_to_object()
  end

  defp do_get([newest | _] = generations, cache, key) do
    case fetch(cache, newest, key) do
      nil ->
        generations
        |> retrieve(cache, key)
        |> elem(1)

      ret ->
        ret
    end
  end

  defp fetch(cache, gen, key, fun \\ &local_get/4) do
    fun
    |> apply([gen, key, nil, cache.__state__])
    |> validate_ttl(gen, cache)
  end

  defp retrieve([newest | olders], cache, key) do
    Enum.reduce_while(olders, {newest, nil}, fn gen, {newer, _} ->
      case fetch(cache, gen, key, &local_pop/4) do
        nil ->
          {:cont, {gen, nil}}

        {k, v, vsn, exp} ->
          # make sure we take the old timestamp since it will get set to
          # the default :infinity otherwise.
          entry = {k, v, vsn, diff_epoch(exp)}
          true = Local.insert(newer, entry, cache.__state__)
          {:halt, {gen, entry}}
      end
    end)
  end

  @impl true
  def get_many(cache, keys, _opts) do
    Enum.reduce(keys, %{}, fn key, acc ->
      if obj = get(cache, key, []),
        do: Map.put(acc, key, obj),
        else: acc
    end)
  end

  @impl true
  def set(cache, object, opts) do
    opts
    |> Keyword.get(:action, :set)
    |> do_set(cache, object)
  end

  defp do_set(:set, cache, %Object{key: key, value: val, version: vsn, expire_at: exp}) do
    local_set(cache, {key, val, vsn, exp})
  end

  defp do_set(:add, cache, %Object{key: key, value: val, version: vsn, expire_at: exp}) do
    cache.__metadata__.generations
    |> hd()
    |> Local.insert_new({key, val, vsn, exp}, cache.__state__)
  end

  defp do_set(:replace, cache, %Object{key: key, value: val, version: vsn, expire_at: exp}) do
    local_update(cache, key, [{2, val}, {3, vsn}, {4, exp}])
  end

  @impl true
  def set_many(cache, objects, _opts) do
    entries =
      for %Object{key: key, value: value, version: version, expire_at: expire_at} <- objects,
          value != nil do
        {key, value, version, expire_at}
      end

    true = local_set(cache, entries)
    :ok
  rescue
    _ -> {:error, for(o <- objects, do: o.key)}
  end

  @impl true
  def delete(cache, key, _opts) do
    Enum.each(cache.__metadata__.generations, &Local.delete(&1, key, cache.__state__))
  end

  @impl true
  def take(cache, key, _opts) do
    Enum.reduce_while(cache.__metadata__.generations, nil, fn gen, acc ->
      case Local.take(gen, key, cache.__state__) do
        [entry] -> {:halt, entry_to_object(entry)}
        [] -> {:cont, acc}
      end
    end)
  end

  @impl true
  def has_key?(cache, key) do
    Enum.reduce_while(cache.__metadata__.generations, false, fn gen, acc ->
      if has_key?(gen, key, Object.ts(), cache.__state__),
        do: {:halt, true},
        else: {:cont, acc}
    end)
  end

  defp has_key?(gen, key, now, state) do
    case Local.lookup_element(gen, key, 4, state) do
      exp when not is_nil(exp) and exp <= now ->
        true = Local.delete(gen, key, state)
        false

      _ ->
        true
    end
  rescue
    ArgumentError -> false
  end

  @impl true
  def object_info(cache, key, attr) do
    Enum.reduce_while(cache.__metadata__.generations, nil, fn gen, acc ->
      case {fetch(cache, gen, key), attr} do
        {{_, _, _, exp}, :ttl} ->
          {:halt, Object.remaining_ttl(exp)}

        {{_, _, vsn, _}, :version} ->
          {:halt, vsn}

        {nil, _} ->
          {:cont, acc}
      end
    end)
  end

  @impl true
  def expire(cache, key, ttl) do
    expire_at = Object.expire_at(ttl)

    case local_update(cache, key, {4, expire_at}) do
      true -> expire_at || :infinity
      false -> nil
    end
  end

  @impl true
  def update_counter(cache, key, incr, opts) do
    exp =
      opts
      |> Keyword.get(:ttl)
      |> Object.expire_at()

    cache.__metadata__.generations
    |> hd()
    |> Local.update_counter(key, {2, incr}, {key, 0, nil, exp}, cache.__state__)
  end

  @impl true
  def size(cache) do
    Enum.reduce(cache.__metadata__.generations, 0, fn gen, acc ->
      gen
      |> Local.info(:size, cache.__state__)
      |> Kernel.+(acc)
    end)
  end

  @impl true
  def flush(cache) do
    :ok = Generation.flush(cache)
    _ = cache.new_generation()
    :ok
  end

  ## Queryable

  @impl true
  def all(cache, query, opts) do
    query = validate_match_spec(query, opts)

    for gen <- cache.__metadata__.generations,
        elems <- Local.select(gen, query, cache.__state__),
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
        result = Local.select(newer, match_spec, page_size, cache.__state__)
        {result, generations}
      end,
      fn
        {:"$end_of_table", [_gen]} ->
          {:halt, []}

        {:"$end_of_table", [_gen | generations]} ->
          result =
            generations
            |> hd()
            |> Local.select(match_spec, page_size, cache.__state__)

          {[], {result, generations}}

        {{elements, cont}, [_ | _] = generations} ->
          {elements, {Local.select(cont), generations}}
      end,
      & &1
    )
  end

  ## Transaction

  @impl true
  def transaction(cache, fun, opts) do
    keys = Keyword.get(opts, :keys, [])
    nodes = Keyword.get(opts, :nodes, [node()])
    retries = Keyword.get(opts, :retries, :infinity)
    do_transaction(cache, keys, nodes, retries, fun)
  end

  ## Helpers

  defp local_get(tab, key, default, state) do
    case Local.lookup(tab, key, state) do
      [] -> default
      [entry] -> entry
    end
  end

  defp local_pop(tab, key, default, state) do
    case Local.take(tab, key, state) do
      [] -> default
      [entry] -> entry
    end
  end

  defp local_set(cache, entries) do
    cache.__metadata__.generations
    |> hd()
    |> Local.insert(entries, cache.__state__)
  end

  defp local_update(cache, key, updates) do
    cache.__metadata__.generations
    |> hd()
    |> Local.update_element(key, updates, cache.__state__)
  end

  defp entry_to_object(nil), do: nil

  defp entry_to_object({key, val, vsn, :infinity}) do
    %Object{key: key, value: val, version: vsn}
  end

  defp entry_to_object({key, val, vsn, expire_at}) do
    %Object{key: key, value: val, version: vsn, expire_at: expire_at}
  end

  defp validate_ttl(nil, _, _), do: nil
  defp validate_ttl({_, _, _, nil} = entry, _, _), do: entry

  defp validate_ttl({key, _, _, expire_at} = entry, gen, cache) do
    if expire_at > Object.ts() do
      entry
    else
      true = Local.delete(gen, key, cache.__state__)
      nil
    end
  end

  defp diff_epoch(ttl) when is_integer(ttl), do: ttl - Object.ts()
  defp diff_epoch(_), do: :infinity

  defp validate_match_spec(spec, opts) when spec in [nil, :all_unexpired, :all_expired] do
    [
      {
        {:"$1", :"$2", :"$3", :"$4"},
        if(spec = comp_match_spec(spec), do: [spec], else: []),
        ret_match_spec(opts)
      }
    ]
  end

  defp validate_match_spec(spec, _opts) do
    case Local.test_ms({nil, nil, nil, :infinity}, spec) do
      {:ok, _result} ->
        spec

      {:error, _result} ->
        raise Nebulex.QueryError, message: "invalid match spec", query: spec
    end
  end

  defp comp_match_spec(nil),
    do: nil

  defp comp_match_spec(:all_unexpired),
    do: {:orelse, {:==, :"$4", nil}, {:>, :"$4", Object.ts()}}

  defp comp_match_spec(:all_expired),
    do: {:not, comp_match_spec(:all_unexpired)}

  defp ret_match_spec(opts) do
    case Keyword.get(opts, :return, :key) do
      :key -> [:"$1"]
      :value -> [:"$2"]
      :object -> [%Object{key: :"$1", value: :"$2", version: :"$3", expire_at: :"$4"}]
    end
  end
end
