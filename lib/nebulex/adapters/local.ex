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

  These options should be set in the config file and require
  recompilation in order to make an effect.

    * `:adapter` - The adapter name, in this case, `Nebulex.Adapters.Local`.

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

  `Nebulex.Cache` is the wrapper around the Cache. We can define a
  local cache as follows:

      defmodule MyApp.LocalCache do
        use Nebulex.Cache, otp_app: :my_app, adapter: Nebulex.Adapters.Local
      end

  Where the configuration for the Cache must be in your application
  environment, usually defined in your `config/config.exs`:

      config :my_app, MyApp.LocalCache,
        n_shards: 2,
        gc_interval: 3600,
        write_concurrency: true

  For more information about the usage, check `Nebulex.Cache`.

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
  """

  # Inherit default transaction implementation
  use Nebulex.Adapter.Transaction

  # Provide Cache Implementation
  @behaviour Nebulex.Adapter
  @behaviour Nebulex.Adapter.Multi
  @behaviour Nebulex.Adapter.List

  alias Nebulex.Adapters.Local.Generation
  alias Nebulex.Object
  alias Nebulex.Object.Version
  alias :shards_local, as: Local

  @list_api [:lpush, :rpush, :lpop, :rpop, :lrange]

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
  def init(cache, opts) do
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
  def get(cache, key, opts) do
    cache.__metadata__.generations
    |> do_get(cache, key, opts)
    |> Version.validate!(cache, opts)
    |> elem(1)
  end

  defp do_get([newest | _] = generations, cache, key, opts) do
    case fetch(cache, newest, key) do
      nil ->
        generations
        |> retrieve(cache, key, opts)
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

  defp retrieve([newest | olders], cache, key, opts) do
    Enum.reduce_while(olders, {newest, nil}, fn gen, {newer, _} ->
      if object = fetch(cache, gen, key, &local_pop/4) do
        # make sure we take the old timestamp since it will get set to
        # the default :infinity otherwise.
        opts = Keyword.put_new(opts, :ttl, diff_epoch(object.ttl))
        {:halt, {gen, local_set(newer, object, cache, opts)}}
      else
        {:cont, {gen, nil}}
      end
    end)
  end

  @impl true
  def set(cache, object, opts) do
    action =
      case Keyword.get(opts, :set) do
        :add ->
          {&do_add/3, [cache, object, opts]}

        :replace ->
          {&do_replace/3, [cache, object, opts]}

        nil ->
          {&do_set/3, [cache, object, opts]}
      end

    object.key
    |> Version.validate!(cache, opts)
    |> maybe_exec(:set, action)
  end

  defp do_set(_cache, %Object{value: nil}, _opts), do: nil

  defp do_set(cache, object, opts) do
    cache.__metadata__.generations
    |> hd()
    |> local_set(object, cache, opts)
  end

  defp do_add(cache, object, opts) do
    object =
      object
      |> Object.set_version(cache)
      |> set_ttl(opts)

    cache.__metadata__.generations
    |> hd()
    |> Local.insert_new(to_tuples(object), cache.__state__)
    |> case do
      true -> object
      false -> nil
    end
  end

  defp do_replace(cache, object, _opts) do
    object = Object.set_version(object, cache)

    cache
    |> local_update(object)
    |> case do
      true -> object
      false -> nil
    end
  end

  @impl true
  def delete(cache, key, opts) do
    key
    |> Version.validate!(cache, opts)
    |> maybe_exec(:delete, {&do_delete/2, [cache, key]})
  end

  defp do_delete(cache, key) do
    :ok = Enum.each(cache.__metadata__.generations, &Local.delete(&1, key, cache.__state__))
    %Object{key: key}
  end

  @impl true
  def take(cache, key, opts) do
    key
    |> Version.validate!(cache, opts)
    |> maybe_exec(:take, {&do_take/2, [cache, key]})
  end

  defp do_take(cache, key) do
    Enum.reduce_while(cache.__metadata__.generations, nil, fn gen, acc ->
      case Local.take(gen, key, cache.__state__) do
        [tuple] -> {:halt, from_tuple(tuple)}
        [] -> {:cont, acc}
      end
    end)
  end

  @impl true
  def has_key?(cache, key) do
    Enum.reduce_while(cache.__metadata__.generations, false, fn gen, acc ->
      if Local.member(gen, key, cache.__state__),
        do: {:halt, true},
        else: {:cont, acc}
    end)
  end

  @impl true
  def update_counter(cache, key, incr, opts) when is_integer(incr) do
    ttl =
      opts
      |> Keyword.get(:ttl)
      |> seconds_since_epoch()

    cache.__metadata__.generations
    |> hd()
    |> Local.update_counter(key, {2, incr}, {key, 0, nil, ttl}, cache.__state__)
  end

  def update_counter(_cache, _key, incr, _opts) do
    raise ArgumentError, "the incr must be a valid integer, got: #{inspect(incr)}"
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

  @impl true
  def keys(cache, _opts) do
    ms = [{{:"$1", :_, :_, :_}, [], [:"$1"]}]

    cache.__metadata__.generations
    |> Enum.reduce([], fn gen, acc ->
      Local.select(gen, ms, cache.__state__) ++ acc
    end)
    |> :lists.usort()
  end

  ## Multi

  @impl true
  def mget(cache, keys, _opts) do
    Enum.reduce(keys, %{}, fn key, acc ->
      if obj = get(cache, key, []),
        do: Map.put(acc, key, obj),
        else: acc
    end)
  end

  @impl true
  def mset(cache, objects, opts) do
    cache.__metadata__.generations
    |> hd()
    |> local_set(objects, cache, opts)

    :ok
  rescue
    _ -> {:error, for(o <- objects, do: o.key)}
  end

  ## Lists

  @impl true
  def lpush(cache, key, values, opts) do
    key
    |> Version.validate!(cache, opts)
    |> maybe_exec(:lpush, {&do_lpush/5, [cache, key, values, opts]})
  end

  defp do_lpush(cached, cache, key, values, opts) do
    do_push(cached, cache, key, opts, fn object ->
      Enum.reduce(values, object, &%{&2 | value: [&1 | &2.value]})
    end)
  end

  @impl true
  def rpush(cache, key, values, opts) do
    key
    |> Version.validate!(cache, opts)
    |> maybe_exec(:rpush, {&do_rpush/5, [cache, key, values, opts]})
  end

  defp do_rpush(cached, cache, key, values, opts) do
    do_push(cached, cache, key, opts, &%{&1 | value: &1.value ++ values})
  end

  defp do_push(cached, cache, key, opts, fun) do
    object =
      cached
      |> maybe_get(cache, key)
      |> case do
        nil -> %Object{key: key, value: []}
        obj -> obj
      end

    object = do_set(cache, fun.(object), opts)
    length(object.value)
  end

  @impl true
  def lpop(cache, key, opts) do
    key
    |> Version.validate!(cache, opts)
    |> maybe_exec(:lpop, {&do_lpop/4, [cache, key, opts]})
  end

  defp do_lpop(cached, cache, key, opts) do
    do_pop(cached, cache, key, opts, fn [value | rest] -> {value, rest} end)
  end

  @impl true
  def rpop(cache, key, opts) do
    key
    |> Version.validate!(cache, opts)
    |> maybe_exec(:rpop, {&do_rpop/4, [cache, key, opts]})
  end

  defp do_rpop(cached, cache, key, opts) do
    do_pop(cached, cache, key, opts, fn elements ->
      {rest, [tail]} = :lists.split(length(elements) - 1, elements)
      {tail, rest}
    end)
  end

  defp do_pop(cached, cache, key, opts, fun) do
    cached
    |> maybe_get(cache, key)
    |> case do
      nil ->
        nil

      %Object{value: []} ->
        nil

      %Object{value: elements} = obj ->
        {value, rest} = fun.(elements)
        _ = set(cache, %{obj | value: rest}, opts)
        value
    end
  end

  @impl true
  def lrange(cache, key, offset, limit, opts) do
    key
    |> Version.validate!(cache, opts)
    |> elem(1)
    |> maybe_get(cache, key)
    |> case do
      nil -> []
      %Object{value: []} -> []
      %Object{value: elements} -> :lists.sublist(elements, offset, limit)
    end
  end

  ## Transaction

  @impl true
  def transaction(cache, fun, opts) do
    keys = opts[:keys] || []
    nodes = opts[:nodes] || [node()]
    retries = opts[:retries] || :infinity
    do_transaction(cache, keys, nodes, retries, fun)
  end

  ## Helpers

  defp maybe_exec({:nothing, cached}, action, _cb) when action in [:lpush, :rpush],
    do: length(cached.value)

  defp maybe_exec({:nothing, cached}, :lpop, _cb),
    do: List.first(cached.value)

  defp maybe_exec({:nothing, cached}, :rpop, _cb),
    do: List.last(cached.value)

  defp maybe_exec({:nothing, cached}, _action, _cb),
    do: cached

  defp maybe_exec({:override, cached}, action, {fun, args}) when action in @list_api,
    do: apply(fun, [cached | args])

  defp maybe_exec({:override, _}, _action, {fun, args}),
    do: apply(fun, args)

  defp maybe_get(nil, cache, key),
    do: do_get(cache.__metadata__.generations, cache, key, [])

  defp maybe_get(%Object{key: key, value: nil}, cache, key),
    do: maybe_get(nil, cache, key)

  defp maybe_get(cached, _cache, _key),
    do: cached

  defp local_get(tab, key, default, state) do
    case Local.lookup(tab, key, state) do
      [] -> default
      [tuple] -> from_tuple(tuple)
    end
  end

  defp local_pop(tab, key, default, state) do
    case Local.take(tab, key, state) do
      [] -> default
      [tuple] -> from_tuple(tuple)
    end
  end

  defp local_set(generation, obj_or_objs, cache, opts) do
    obj_or_objs =
      obj_or_objs
      |> Object.set_version(cache)
      |> set_ttl(opts)

    true = Local.insert(generation, to_tuples(obj_or_objs), cache.__state__)
    obj_or_objs
  end

  defp local_update(cache, object) do
    cache.__metadata__.generations
    |> hd()
    |> Local.update_element(object.key, [{2, object.value}, {3, object.version}], cache.__state__)
  end

  defp from_tuple({key, val, vsn, ttl}) do
    %Object{key: key, value: val, version: vsn, ttl: ttl}
  end

  defp to_tuples(%Object{key: key, value: val, version: vsn, ttl: ttl}),
    do: {key, val, vsn, ttl}

  defp to_tuples(objs) do
    for %Object{key: key, value: val, version: vsn, ttl: ttl} <- objs do
      {key, val, vsn, ttl}
    end
  end

  defp set_ttl(%Object{} = obj, opts) do
    [obj] = set_ttl([obj], opts)
    obj
  end

  defp set_ttl(objs, opts) do
    opts
    |> Keyword.get(:ttl)
    |> case do
      nil -> objs
      ttl -> for obj <- objs, do: %{obj | ttl: seconds_since_epoch(ttl)}
    end
  end

  defp validate_ttl(nil, _, _), do: nil
  defp validate_ttl(%Object{ttl: :infinity} = object, _, _), do: object

  defp validate_ttl(%Object{ttl: ttl} = object, gen, cache) do
    if ttl > seconds_since_epoch(0) do
      object
    else
      true = Local.delete(gen, object.key, cache.__state__)
      nil
    end
  end

  defp seconds_since_epoch(diff) when is_integer(diff), do: unix_time() + diff
  defp seconds_since_epoch(_), do: :infinity

  defp diff_epoch(ttl) when is_integer(ttl), do: ttl - unix_time()
  defp diff_epoch(_), do: :infinity

  defp unix_time, do: DateTime.to_unix(DateTime.utc_now())
end
