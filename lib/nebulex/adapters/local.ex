defmodule Nebulex.Adapters.Local do
  @moduledoc """
  Adapter module for Local Generational Cache.

  It uses [Shards](https://github.com/cabol/shards) as in-memory backend
  (ETS tables are used internally) through the Elixir's wrapper
  [ExShards](https://github.com/cabol/ex_shards).

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

  @impl true
  defmacro __before_compile__(env) do
    cache = env.module
    config = Module.get_attribute(cache, :config)
    n_shards = Keyword.get(config, :n_shards, System.schedulers_online())
    r_concurrency = Keyword.get(config, :read_concurrency, true)
    w_concurrency = Keyword.get(config, :write_concurrency, true)
    vsn_generator = Keyword.get(config, :version_generator)
    shards_sup_name = Module.concat([cache, ShardsSupervisor])

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

  @impl true
  def init(cache, opts) do
    {:ok, children(cache, opts)}
  end

  defp children(cache, opts) do
    [
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
  end

  @impl true
  def get(cache, key, opts) do
    do_get(cache.__metadata__.generations, cache, key, opts)
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
    Enum.reduce_while(olders, {newest, nil}, fn(gen, {newer, _}) ->
      if object = fetch(cache, gen, key, &local_pop/4) do
        # make sure we take the old timestamp since it will get set to
        # the default :infinity otherwise.
        opts = Keyword.put_new(opts, :ttl, diff_epoch(object.ttl))
        {:halt, {gen, do_set(newer, object, cache, opts)}}
      else
        {:cont, {gen, nil}}
      end
    end)
  end

  @impl true
  def set(cache, object, opts) do
    cache.__metadata__.generations
    |> hd()
    |> do_set(object, cache, opts)
  end

  defp do_set(generation, object, cache, opts) do
    object =
      object
      |> cache.set_object_vsn()
      |> set_ttl(opts)

    true = Local.insert(generation, object_to_tuple(object), cache.__state__)
    object
  end

  @impl true
  def delete(cache, key, _opts) do
    :ok = Enum.each(cache.__metadata__.generations, &Local.remove(&1, key, cache.__state__))
    %Object{key: key}
  end

  @impl true
  def has_key?(cache, key) do
    Enum.reduce_while(cache.__metadata__.generations, false, fn(gen, acc) ->
      if Local.has_key?(gen, key, cache.__state__),
        do: {:halt, true},
        else: {:cont, acc}
    end)
  end

  @impl true
  def update_counter(cache, key, incr, opts) do
    ttl =
      opts
      |> Keyword.get(:ttl)
      |> seconds_since_epoch

    try do
      cache.__metadata__.generations
      |> hd()
      |> Local.update_counter(key, {2, incr}, {key, 0, nil, ttl}, cache.__state__)
    rescue
      _exception ->
        reraise ArgumentError, System.stacktrace()
    end
  end

  @impl true
  def size(cache) do
    Enum.reduce(cache.__metadata__.generations, 0, fn(gen, acc) ->
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
  def keys(cache) do
    ms = [{{:"$1", :_, :_, :_}, [], [:"$1"]}]

    cache.__metadata__.generations
    |> Enum.reduce([], fn(gen, acc) ->
      Local.select(gen, ms, cache.__state__) ++ acc
    end)
    |> :lists.usort()
  end

  @impl true
  def reduce(cache, acc_in, fun, _opts) do
    Enum.reduce(cache.__metadata__.generations, acc_in, fn(gen, acc) ->
      Local.foldl(fn({key, val, vsn, ttl}, fold_acc) ->
        object = %Object{key: key, value: val, version: vsn, ttl: ttl}
        fun.(object, fold_acc)
      end, acc, gen, cache.__state__)
    end)
  end

  @impl true
  def to_map(cache, opts) do
    match_spec =
      case Keyword.get(opts, :return, :key) do
        :object ->
          obj_match = %Object{key: :"$1", value: :"$2", version: :"$3", ttl: :"$4"}
          [{{:"$1", :"$2", :"$3", :"$4"}, [], [{{:"$1", obj_match}}]}]

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

  @impl true
  def transaction(cache, fun, opts) do
    keys  = opts[:keys] || []
    nodes = opts[:nodes] || [node()]
    retries = opts[:retries] || :infinity
    do_transaction(cache, keys, nodes, retries, fun)
  end

  ## Helpers

  defp local_get(tab, key, default, state) do
    case Local.lookup(tab, key, state) do
      []    -> default
      [raw] -> tuple_to_object(raw)
    end
  end

  defp local_pop(tab, key, default, state) do
    case Local.take(tab, key, state) do
      []    -> default
      [raw] -> tuple_to_object(raw)
    end
  end

  defp tuple_to_object({key, val, vsn, ttl}),
    do: %Object{key: key, value: val, version: vsn, ttl: ttl}

  defp object_to_tuple(%Object{key: key, value: val, version: vsn, ttl: ttl}),
    do: {key, val, vsn, ttl}

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

  defp set_ttl(object, opts) do
    opts
    |> Keyword.get(:ttl)
    |> case do
      nil -> object
      opt -> %{object | ttl: seconds_since_epoch(opt)}
    end
  end

  defp seconds_since_epoch(diff) when is_integer(diff), do: unix_time() + diff
  defp seconds_since_epoch(_), do: :infinity

  defp diff_epoch(ttl) when is_integer(ttl), do: ttl - unix_time()
  defp diff_epoch(_), do: :infinity

  defp unix_time, do: DateTime.to_unix(DateTime.utc_now())
end
