defmodule Nebulex.Adapters.Local do
  @moduledoc """
  Adapter module for Local Generational Cache.

  It uses [ExShards](https://github.com/cabol/ex_shards) as memory backend
  (ETS tables are used internally).

  ## Features

    * Support for generational cache – inspired by [epocxy](https://github.com/duomark/epocxy)
    * Support for Sharding – handled by **ExShards**.
    * Support for garbage collection via `Nebulex.Adapters.Local.Generation`
    * Support for transactions via Erlang global name registration facility

  ## Options

  These options should be set in the config file and require
  recompilation in order to make an effect.

    * `:adapter` - The adapter name, in this case, `Nebulex.Adapters.Local`.

    * `:n_shards` - The number of partitions for each Cache generation table.
      Defaults to `:erlang.system_info(:schedulers_online)`.

    * `:n_generations` - Max number of Cache generations, defaults to `2`.

    * `:read_concurrency` - Indicates whether the tables that `ExShards`
      creates uses `:read_concurrency` or not (default: true).

    * `:write_concurrency` - Indicates whether the tables that `ExShards`
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

  alias ExShards.Local
  alias Nebulex.Adapters.Local.Generation
  alias Nebulex.Object

  ## Adapter Impl

  @doc false
  defmacro __before_compile__(env) do
    cache = env.module
    config = Module.get_attribute(cache, :config)
    n_shards = Keyword.get(config, :n_shards, System.schedulers_online())
    r_concurrency = Keyword.get(config, :read_concurrency, true)
    w_concurrency = Keyword.get(config, :write_concurrency, true)
    vsn_generator = Keyword.get(config, :version_generator)
    shards_sup_name = Module.concat([cache, LocalSupervisor])

    quote do
      alias ExShards.State
      alias Nebulex.Adapters.Local.Generation
      alias Nebulex.Adapters.Local.Metadata

      def __metadata__, do: Metadata.get(__MODULE__)

      def __state__, do: State.new(unquote(n_shards))

      def __shards_sup_name__, do: unquote(shards_sup_name)

      def __tab_opts__ do
        [
          n_shards: unquote(n_shards),
          sup_name: unquote(shards_sup_name),
          read_concurrency: unquote(r_concurrency),
          write_concurrency: unquote(w_concurrency)
        ]
      end

      def new_generation(opts \\ []), do: Generation.new(__MODULE__, opts)

      if unquote(vsn_generator) do
        def generate_vsn(obj) do
          unquote(vsn_generator).generate(obj)
        end
      else
        def generate_vsn(_), do: nil
      end
    end
  end

  @doc false
  def children_specs(cache, opts) do
    import Supervisor.Spec

    [
      supervisor(:shards_sup, [cache.__shards_sup_name__]),
      worker(Nebulex.Adapters.Local.Generation, [cache, opts])
    ]
  end

  @doc false
  def get(cache, key, opts) do
    get(cache.__metadata__.generations, cache, key, opts, &elem(&1, 1))
  end

  defp get(generations, cache, key, opts, post_hook \\ &(&1)) do
    generations
    |> do_get(cache, key, opts)
    |> post_hook.()
  end

  defp do_get([newest | _] = generations, cache, key, opts) do
    case fetch(cache, newest, key, opts) do
      nil -> retrieve(generations, cache, key, opts)
      ret -> {newest, ret}
    end
  end

  defp fetch(cache, gen, key, opts, fun \\ &local_get/4) do
    fun
    |> apply([gen, key, nil, cache.__state__])
    |> validate_vsn(:get, opts)
    |> validate_ttl(gen, cache)
    |> validate_return(opts)
  end

  defp retrieve([newest | olders], cache, key, opts) do
    Enum.reduce_while(olders, {newest, nil}, fn(gen, {newer, _}) ->
      if object = fetch(cache, gen, key, ret_obj(opts), &local_pop/4) do
        # make sure we take the old timestamp since it will get set to
        # the default :infinity otherwise.
        opts = Keyword.put_new(opts, :ttl, diff_epoch(object.ttl))
        {:halt, {gen, do_set(object, newer, cache, opts)}}
      else
        {:cont, {gen, nil}}
      end
    end)
  end

  @doc false
  def set(_cache, _key, nil, _opts),
    do: nil
  def set(cache, key, value, opts) do
    generations = cache.__metadata__.generations

    object =
      cond do
        opts[:version] == nil ->
          %Object{key: key, value: value}
        cached_obj = get(generations, cache, key, [return: :object], &elem(&1, 1)) ->
          validate_vsn(cached_obj, :set, [{:replace_value, value} | opts])
        true ->
          %Object{key: key, value: value, version: opts[:version]}
      end

    do_set(object, hd(generations), cache, opts)
  end

  defp do_set(%Object{value: nil}, _gen, _cache, _opts),
    do: nil
  defp do_set(object, gen, cache, opts) do
    version = cache.generate_vsn(object)

    ttl =
      if ttl_opt = opts[:ttl],
        do: seconds_since_epoch(ttl_opt),
        else: object.ttl

    %{object | version: version, ttl: ttl}
    |> set_object(gen, cache)
    |> validate_return(opts)
  end

  defp set_object(obj, gen, cache) do
    true = Local.insert(gen, {obj.key, obj.value, obj.version, obj.ttl}, cache.__state__)
    obj
  end

  @doc false
  def delete(cache, key, opts) do
    generations = cache.__metadata__.generations

    opts[:version]
    |> maybe_validate_vsn(generations, cache, key, opts)
    |> do_delete(generations, cache.__state__)
    |> Map.fetch!(:key)
  end

  defp maybe_validate_vsn(nil, _, _, key, _),
    do: %Object{key: key}
  defp maybe_validate_vsn(_version, generations, cache, key, opts) do
    generations
    |> get(cache, key, [return: :object, on_conflict: :nothing], &elem(&1, 1))
    |> validate_vsn(:delete, opts)
  end

  defp do_delete(nil, _, _),
    do: nil
  defp do_delete({:nothing, cached_obj}, _, _),
    do: cached_obj
  defp do_delete(%Object{} = object, generations, state) do
    :ok = Enum.each(generations, &Local.remove(&1, object.key, state))
    object
  end

  @doc false
  def has_key?(cache, key) do
    Enum.reduce_while(cache.__metadata__.generations, false, fn(gen, acc) ->
      if Local.has_key?(gen, key, cache.__state__) do
        {:halt, true}
      else
        {:cont, acc}
      end
    end)
  end

  @doc false
  def size(cache) do
    Enum.reduce(cache.__metadata__.generations, 0, fn(gen, acc) ->
      gen
      |> Local.info(:size, cache.__state__)
      |> Kernel.+(acc)
    end)
  end

  @doc false
  def flush(cache) do
    :ok = Generation.flush(cache)
    _ = cache.new_generation()
    :ok
  end

  @doc false
  def keys(cache) do
    ms = [{{:"$1", :_, :_, :_}, [], [:"$1"]}]

    cache.__metadata__.generations
    |> Enum.reduce([], fn(gen, acc) -> Local.select(gen, ms, cache.__state__) ++ acc end)
    |> :lists.usort()
  end

  @doc false
  def reduce(cache, acc_in, fun, opts) do
    Enum.reduce(cache.__metadata__.generations, acc_in, fn(gen, acc) ->
      Local.foldl(fn({key, val, vsn, ttl}, fold_acc) ->
        return =
          %Object{key: key, value: val, version: vsn, ttl: ttl}
          |> validate_return(opts)
        fun.({key, return}, fold_acc)
      end, acc, gen, cache.__state__)
    end)
  end

  @doc false
  def to_map(cache, opts) do
    match_spec =
      case Keyword.get(opts, :return, :key) do
        :object ->
          object_match = %Object{key: :"$1", value: :"$2", version: :"$3", ttl: :"$4"}
          [{{:"$1", :"$2", :"$3", :"$4"}, [], [{{:"$1", object_match}}]}]
        _ ->
          [{{:"$1", :"$2", :_, :_}, [], [{{:"$1", :"$2"}}]}]
      end

    Enum.reduce(cache.__metadata__.generations, %{}, fn(gen, acc) ->
      gen
      |> Local.select(match_spec, cache.__state__)
      |> :maps.from_list()
      |> Map.merge(acc)
    end)
  end

  @doc false
  def pop(cache, key, opts) do
    generations = cache.__metadata__.generations

    generations
    |> get(cache, key, opts)
    |> case do
      {_, nil} ->
        nil
      {_, ret} ->
        _ = do_delete(%Object{key: key}, generations, cache.__state__)
        ret
    end
  end

  @doc false
  def get_and_update(cache, key, fun, opts) when is_function(fun, 1) do
    generations = cache.__metadata__.generations
    {gen, current} = get(generations, cache, key, Keyword.put(opts, :return, :object))
    current = current || %Object{}

    case fun.(current.value) do
      {get, update} ->
        {get, do_set(%{current | key: key, value: update}, gen, cache, opts)}
      :pop ->
        _ = do_delete(%Object{key: key}, generations, cache.__state__)
        {current.value, nil}
      other ->
        raise ArgumentError,
          "the given function must return a two-element tuple or :pop, " <>
          "got: #{inspect(other)}"
    end
  end

  @doc false
  def update(cache, key, initial, fun, opts) do
    generations = cache.__metadata__.generations

    case get(generations, cache, key, Keyword.put(opts, :return, :object)) do
      {gen, nil} ->
        do_set(%Object{key: key, value: initial}, gen, cache, opts)
      {gen, obj} ->
        do_set(%{obj | key: key, value: fun.(obj.value)}, gen, cache, opts)
    end
  end

  @doc false
  def update_counter(cache, key, incr, opts) do
    ttl = seconds_since_epoch(opts[:ttl])

    try do
      cache.__metadata__.generations
      |> hd()
      |> Local.update_counter(key, {2, incr}, {key, 0, nil, ttl}, cache.__state__)
    rescue
      _exception ->
        reraise ArgumentError, System.stacktrace()
    end
  end

  @doc false
  def transaction(cache, opts, fun) do
    keys  = opts[:keys] || []
    nodes = opts[:nodes] || [node()]
    retries = opts[:retries] || :infinity
    do_transaction(cache, keys, nodes, retries, fun)
  end

  ## Helpers

  defp local_get(tab, key, default, state) do
    case Local.lookup(tab, key, state) do
      [] ->
        default
      [{^key, val, vsn, ttl}] ->
        %Object{key: key, value: val, version: vsn, ttl: ttl}
    end
  end

  def local_pop(tab, key, default, state) do
    case Local.take(tab, key, state) do
      [] ->
        default
      [{^key, val, vsn, ttl}] ->
        %Object{key: key, value: val, version: vsn, ttl: ttl}
    end
  end

  defp on_conflict(nil, :get, _, _),
    do: nil
  defp on_conflict(:replace, :set, cached, object),
    do: %{cached | value: object.value}
  defp on_conflict(:delete, :delete, cached, _),
    do: cached
  defp on_conflict(:nothing, :delete, cached, _),
    do: {:nothing, cached}
  defp on_conflict(:nothing, _, cached, _),
    do: cached
  defp on_conflict(:raise, op, cached, object),
    do: raise Nebulex.VersionConflictError, action: op, cached: cached, version: object.version
  defp on_conflict(other, _, _, _),
    do: raise ArgumentError, "unknown value for :on_conflict, got: #{inspect other}"

  defp validate_vsn(nil, _, _),
    do: nil
  defp validate_vsn(cached, op, opts) do
    version = opts[:version]
    value = opts[:replace_value]

    if version == nil or version == cached.version do
      if value,
        do: %{cached | value: value},
        else: cached
    else
      opts
      |> Keyword.get(:on_conflict, :raise)
      |> on_conflict(op, cached, %Object{key: cached.key, value: value, version: version})
    end
  end

  defp validate_ttl(nil, _, _),
    do: nil
  defp validate_ttl(%Object{ttl: :infinity} = object, _, _),
    do: object
  defp validate_ttl(%Object{ttl: ttl} = object, gen, cache) do
    if ttl > seconds_since_epoch(0) do
      object
    else
      true = Local.delete(gen, object.key, cache.__state__)
      nil
    end
  end

  defp validate_return(nil, _),
    do: nil
  defp validate_return(%Object{} = object, opts) do
    case Keyword.get(opts, :return, :value) do
      :object -> object
      :value  -> object.value
      :key    -> object.key
    end
  end

  defp seconds_since_epoch(diff) when is_integer(diff),
    do: unix_time() + diff
  defp seconds_since_epoch(_),
    do: :infinity

  defp diff_epoch(ttl) when is_integer(ttl),
    do: ttl - unix_time()
  defp diff_epoch(_),
    do: :infinity

  defp unix_time, do: DateTime.to_unix(DateTime.utc_now())

  defp ret_obj(opts), do: Keyword.put(opts, :return, :object)
end
