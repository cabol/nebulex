defmodule Nebulex.Adapters.Local do
  @moduledoc """
  Adapter module for Local Generational Cache.

  It uses `ExShards.Local` as memory backend (it uses ETS tables internally).

  ## Features

    * Support for multi-generation Cache
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
      creates uses `:write_concurrency` or not (default: false).

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

  # Provide Cache Implementation
  @behaviour Nebulex.Adapter

  alias Nebulex.Object
  alias ExShards.Local

  ## Adapter Impl

  @doc false
  defmacro __before_compile__(env) do
    cache = env.module
    config = Module.get_attribute(cache, :config)
    n_shards = Keyword.get(config, :n_shards, :erlang.system_info(:schedulers_online))
    r_concurrency = Keyword.get(config, :read_concurrency, true)
    w_concurrency = Keyword.get(config, :write_concurrency, false)
    vsn_generator = Keyword.get(config, :version_generator, Nebulex.Version.Default)
    shards_sup_name = String.to_atom("#{cache}.Local.Supervisor")

    quote do
      def __metadata__, do: Nebulex.Adapters.Local.Metadata.get(__MODULE__)

      def __state__, do: ExShards.State.new(unquote(n_shards))

      def __shards_sup_name__, do: unquote(shards_sup_name)

      def __tab_opts__ do
        [n_shards: unquote(n_shards),
         sup_name: unquote(shards_sup_name),
         read_concurrency: unquote(r_concurrency),
         write_concurrency: unquote(w_concurrency)]
      end

      def __version__, do: unquote(vsn_generator)

      def new_generation(opts \\ []) do
        Nebulex.Adapters.Local.Generation.new(__MODULE__, opts)
      end
    end
  end

  @doc false
  def children(cache, opts) do
    import Supervisor.Spec

    [supervisor(:shards_sup, [cache.__shards_sup_name__]),
     worker(Nebulex.Adapters.Local.Generation, [cache, opts])]
  end

  @doc false
  def get(cache, key, opts \\ []) do
    get(cache.__metadata__.generations, cache, key, opts, &elem(&1, 1))
  end

  defp get([newest | olders], cache, key, opts, post_hook \\ &(&1)) do
    if ret = get_or_pop(:get, cache, newest, key, opts) do
      {newest, ret}
    else
      Enum.reduce_while(olders, {newest, nil}, fn(gen, {newer, _}) ->
        if object = get_or_pop(:pop, cache, gen, key, ret_obj(opts)) do
          {:halt, {gen, do_set(object, newer, cache, opts)}}
        else
          {:cont, {gen, nil}}
        end
      end)
    end
    |> post_hook.()
  end

  defp get_or_pop(fun, cache, gen, key, opts) do
    Local
    |> apply(fun, [gen, key, nil, cache.__state__])
    |> validate_vsn(:get, opts)
    |> validate_ttl(gen, cache)
    |> validate_return(opts)
  end

  @doc false
  def set(cache, key, value, opts \\ []) do
    generations = cache.__metadata__.generations

    cond do
      opts[:version] == nil ->
        Object.new(key, value)
      cached_obj = get(generations, cache, key, [return: :object], &elem(&1, 1)) ->
        validate_vsn(cached_obj, :set, [{:replace_value, value} | opts])
      true ->
        Object.new(key, value, opts[:version])
    end
    |> do_set(hd(generations), cache, opts)
  end

  defp do_set(object, gen, cache, opts) do
    version = cache.__version__.generate(object)
    ttl = seconds_since_epoch(opts[:ttl])

    %{object | version: version, ttl: ttl}
    |> set_object(gen, cache)
    |> validate_return(opts)
  end

  defp set_object(object, gen, cache) do
    _ = Local.put(gen, object.key, object, cache.__state__)
    object
  end

  @doc false
  def delete(cache, key, opts \\ []) do
    generations = cache.__metadata__.generations

    if opts[:version] do
      generations
      |> get(cache, key, [return: :object, on_conflict: :nothing], &elem(&1, 1))
      |> validate_vsn(:delete, opts)
    else
      Object.new(key)
    end
    |> do_delete(generations, cache.__state__)
    |> validate_return(opts)
  end

  defp do_delete(nil, _, _),
    do: nil
  defp do_delete({:skip, cached_obj}, _, _),
    do: cached_obj
  defp do_delete(%Object{} = object, generations, state) do
    _ = Enum.each(generations, &Local.remove(&1, object.key, state))
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
  def pop(cache, key, opts \\ []) do
    generations = cache.__metadata__.generations

    generations
    |> get(cache, key, opts)
    |> case do
      {_, nil} ->
        nil
      {_, ret} ->
        _ = do_delete(Object.new(key), generations, cache.__state__)
        ret
    end
  end

  @doc false
  def get_and_update(cache, key, fun, opts \\ []) when is_function(fun, 1) do
    generations = cache.__metadata__.generations
    opts = Keyword.delete(opts, :return)
    {gen, current} = get(generations, cache, key, opts)

    case fun.(current) do
      {get, update} ->
        {get, do_set(Object.new(key, update), gen, cache, opts)}
      :pop ->
        _ = do_delete(Object.new(key), generations, cache.__state__)
        {current, nil}
      other ->
        raise ArgumentError,
          "the given function must return a two-element tuple or :pop, " <>
          "got: #{inspect(other)}"
    end
  end

  @doc false
  def update(cache, key, initial, fun, opts \\ []) do
    generations = cache.__metadata__.generations
    opts = Keyword.delete(opts, :return)

    case get(generations, cache, key, opts) do
      {gen, nil} ->
        do_set(Object.new(key, initial), gen, cache, opts)
      {gen, val} ->
        do_set(Object.new(key, fun.(val)), gen, cache, opts)
    end
  end

  @doc false
  def transaction(cache, key \\ nil, fun) do
    :global.trans({{cache, key}, self()}, fun, [node()])
  end

  ## Helpers

  defp on_conflict(nil, :get, _, _),
    do: nil
  defp on_conflict(:replace, :set, cached, object),
    do: %{cached | value: object.value}
  defp on_conflict(:delete, :delete, cached, _),
    do: cached
  defp on_conflict(:nothing, :delete, cached, _),
    do: {:skip, cached}
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
      |> on_conflict(op, cached, Object.new(cached.key, value, version))
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
      _ = Local.remove(gen, object.key, cache.__state__)
      nil
    end
  end

  defp validate_return(nil, _),
    do: nil
  defp validate_return(object, opts) do
    case Keyword.get(opts, :return, :value) do
      :object -> object
      :value  -> object.value
      :key    -> object.key
    end
  end

  defp seconds_since_epoch(nil),
    do: :infinity
  defp seconds_since_epoch(diff) when is_integer(diff) do
    {mega, secs, _} = :os.timestamp()
    mega * 1000000 + secs + diff
  end

  defp ret_obj(opts), do: Keyword.put(opts, :return, :object)
end
