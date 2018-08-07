defmodule Nebulex.Adapters.Multilevel do
  @moduledoc """
  Adapter module for Multi-level Cache.

  This is just a simple layer on top of local or distributed cache
  implementations that enables to have a cache hierarchy by levels.
  Multi-level caches generally operate by checking the fastest,
  level 1 (L1) cache first; if it hits, the adapter proceeds at
  high speed. If that first cache misses, the next fastest cache
  (level 2, L2) is checked, and so on, before accessing external
  memory (that can be handled by a `:fallback` function).

  For write functions, the "Write Through" policy is applied by default;
  this policy ensures that the data is stored safely as it is written
  throughout the hierarchy. However, it is possible to force the write
  operation in a specific level (although it is not recommended) via
  `level` option, where the value is a positive integer greater than 0.

  ## Options

  These options should be set in the config file and require
  recompilation in order to make an effect.

    * `:adapter` - The adapter name, in this case, `Nebulex.Adapters.Multilevel`

    * `:cache_model` - Specifies the cache model: `:inclusive` or `:exclusive`;
      defaults to `:inclusive`. In an inclusive cache, the same data can be
      present in all caches/levels. In an exclusive cache, data can be present
      in only one cache/level and a key cannot be found in the rest of caches
      at the same time. This option affects `get` operation only; if
      `:cache_model` is `:inclusive`, when the key is found in a level N,
      that entry is duplicated backwards (to all previous levels: 1..N-1).

    * `:levels` - The list of caches where each cache corresponds to a level.
      The order of the caches in the list defines the the order of the levels
      as well, for example, the first cache in the list will be the L1 cache
      (level 1) and so on; the Nth elemnt will be the LN cache. This option
      is mandatory, if it is not set or empty, an exception will be raised.

    * `:fallback` - Defines a fallback function when a key is not present
      in any cache level. Function is defined as: `(key -> value)`.

  The `:fallback` can be defined in two ways: at compile-time and at run-time.
  At compile-time, in the cache config, set the module that implements the
  function:

      config :my_app, MyApp.MultilevelCache,
        fallback: &MyMapp.AnyModule/1

  And at run-time, passing the function as an option within the `opts` argument
  (only valid for `get` function):

      MultilevelCache.get("foo", fallback: fn(key) -> key * 2 end)

  ## Shared Options

  Some functions below accept the following options:

    * `:level` - It may be an integer greater than 0 that specifies the cache
      level where the operation will take place. By default, the evaluation
      is performed throughout the whole cache hierarchy (all levels).

  ## Example

  `Nebulex.Cache` is the wrapper around the Cache. We can define the
  multi-level cache as follows:

      defmodule MyApp.MultilevelCache do
        use Nebulex.Cache, otp_app: :nebulex, adapter: Nebulex.Adapters.Multilevel

        defmodule L1 do
          use Nebulex.Cache, otp_app: :nebulex, adapter: Nebulex.Adapters.Local
        end

        defmodule L2 do
          use Nebulex.Cache, otp_app: :nebulex, adapter: Nebulex.Adapters.Dist
        end

        def fallback(_key) do
          # maybe fetch the data from Database
          nil
        end
      end

      defmodule MyApp.LocalCache do
        use Nebulex.Cache, otp_app: :my_app, adapter: Nebulex.Adapters.Local
      end

  Where the configuration for the Cache must be in your application
  environment, usually defined in your `config/config.exs`:

      config :my_app, MyApp.MultilevelCache,
        levels: [
          MyApp.MultilevelCache.L1,
          MyApp.MultilevelCache.L2
        ],
        fallback: &MyApp.MultilevelCache.fallback/1

      config :my_app, MyApp.MultilevelCache.L1,
        n_shards: 2,
        gc_interval: 3600

      config :my_app, MyApp.MultilevelCache.L2,
        local: MyApp.LocalCache

      config :my_app, MyApp.LocalCache,
        n_shards: 2,
        gc_interval: 3600

  Using the multilevel cache cache:

      # Retrieving data from cache
      MyCache.get("foo", fallback: fn(_key) ->
        # Maybe fetch the key from database
        "initial value"
      end)

      # Entry is set in all cache levels
      MyCache.set("foo", "bar")

      # Entry is set at second cache level
      MyCache.set("foo", "bar", level: 2)

      # Entry is deleted from all cache levels
      MyCache.delete("foo")

      # Entry is deleted from second cache level
      MyCache.delete("foo", level: 2)

  ## Extended API

  This adapter provides some additional functions to the `Nebulex.Cache` API.

  ### `__levels__`

  This function returns the configured level list.

      MyCache.__levels__

  ### `__model__`

  This function returns the multi-level cache model.

      MyCache.__model__

  ### `__fallback__`

  This function returns the default fallback function.

      MyCache.__fallback__

  ## Limitations

  Because this adapter reuses other existing/configured adapters, it inherits
  all their limitations too. Therefore, it is highly recommended to check the
  documentation of the used adapters.
  """

  # Provide Cache Implementation
  @behaviour Nebulex.Adapter
  @behaviour Nebulex.Adapter.List
  @behaviour Nebulex.Adapter.Transaction

  alias Nebulex.Object

  ## Adapter

  @impl true
  defmacro __before_compile__(env) do
    otp_app = Module.get_attribute(env.module, :otp_app)
    config = Module.get_attribute(env.module, :config)
    cache_model = Keyword.get(config, :cache_model, :inclusive)
    fallback = Keyword.get(config, :fallback)
    levels = Keyword.get(config, :levels)

    unless levels do
      raise ArgumentError,
            "missing :levels configuration in config " <>
              "#{inspect(otp_app)}, #{inspect(env.module)}"
    end

    unless is_list(levels) && length(levels) > 0 do
      raise ArgumentError,
            ":levels configuration in config must have at least one level, " <>
              "got: #{inspect(levels)}"
    end

    quote do
      def __levels__, do: unquote(levels)

      def __model__, do: unquote(cache_model)

      def __fallback__, do: unquote(fallback)
    end
  end

  @impl true
  def init(_cache, _opts), do: {:ok, []}

  @impl true
  def get(cache, key, opts) do
    fun = fn current, {_, prev} ->
      if object = current.__adapter__.get(current, key, opts) do
        {:halt, {object, [current | prev]}}
      else
        {:cont, {nil, [current | prev]}}
      end
    end

    cache.__levels__
    |> Enum.reduce_while({nil, []}, fun)
    |> maybe_fallback(cache, key, opts)
    |> maybe_replicate_data(cache, opts)
  end

  @impl true
  def mget(cache, keys, _opts) do
    Enum.reduce(keys, %{}, fn key, acc ->
      if obj = get(cache, key, []),
        do: Map.put(acc, key, obj),
        else: acc
    end)
  end

  @impl true
  def set(cache, object, opts) do
    eval(cache, :set, [object, opts], opts)
  end

  @impl true
  def mset(cache, objects, opts) do
    opts
    |> levels(cache)
    |> Enum.reduce({objects, []}, fn level, {objs, acc} ->
      do_mset(level, objs, opts, acc)
    end)
    |> case do
      {_, []} -> :ok
      {_, err} -> {:error, err}
    end
  end

  @impl true
  def add(cache, object, opts) do
    eval(cache, :add, [object, opts], opts)
  end

  @impl true
  def delete(cache, key, opts) do
    eval(cache, :delete, [key, opts], opts)
  end

  @impl true
  def take(cache, key, opts) do
    opts
    |> levels(cache)
    |> do_take(nil, key, opts)
  end

  defp do_take([], result, _key, _opts), do: result

  defp do_take([level | rest], nil, key, opts) do
    result = level.__adapter__.take(level, key, opts)
    do_take(rest, result, key, opts)
  end

  defp do_take(levels, result, key, _opts) do
    _ = eval(levels, :delete, [key, []])
    result
  end

  @impl true
  def has_key?(cache, key) do
    eval_while(cache, :has_key?, [key], false)
  end

  @impl true
  def get_and_update(cache, key, fun, opts) do
    eval(cache, :get_and_update, [key, fun, opts], opts)
  end

  @impl true
  def update(cache, key, initial, fun, opts) do
    eval(cache, :update, [key, initial, fun, opts], opts)
  end

  @impl true
  def update_counter(cache, key, incr, opts) do
    eval(cache, :update_counter, [key, incr, opts], opts)
  end

  @impl true
  def size(cache) do
    Enum.reduce(cache.__levels__, 0, fn level_cache, acc ->
      level_cache.__adapter__.size(level_cache) + acc
    end)
  end

  @impl true
  def flush(cache) do
    Enum.each(cache.__levels__, fn level_cache ->
      level_cache.__adapter__.flush(level_cache)
    end)
  end

  @impl true
  def keys(cache) do
    cache.__levels__
    |> Enum.reduce([], fn level_cache, acc ->
      level_cache.__adapter__.keys(level_cache) ++ acc
    end)
    |> :lists.usort()
  end

  ## Lists

  @impl true
  def lpush(cache, key, value, opts) do
    eval(cache, :lpush, [key, value, opts], opts)
  end

  @impl true
  def rpush(cache, key, value, opts) do
    eval(cache, :rpush, [key, value, opts], opts)
  end

  @impl true
  def lpop(cache, key, opts) do
    eval(cache, :lpop, [key, opts], opts)
  end

  @impl true
  def rpop(cache, key, opts) do
    eval(cache, :rpop, [key, opts], opts)
  end

  @impl true
  def lrange(cache, key, offset, limit, opts) do
    eval(cache, :lrange, [key, offset, limit, opts], opts)
  end

  ## Transaction

  @impl true
  def transaction(cache, fun, opts) do
    eval(cache, :transaction, [fun, opts], [])
  end

  @impl true
  def in_transaction?(cache) do
    results =
      Enum.reduce(cache.__levels__, [], fn level, acc ->
        [level.in_transaction?() | acc]
      end)

    true in results
  end

  ## Helpers

  defp eval(ml_cache, fun, args, opts) do
    eval(levels(opts, ml_cache), fun, args)
  end

  defp eval([l1 | next], fun, args) do
    Enum.reduce(next, apply(l1.__adapter__, fun, [l1 | args]), fn cache, acc ->
      ^acc = apply(cache.__adapter__, fun, [cache | args])
    end)
  end

  defp levels(opts, cache) do
    opts
    |> Keyword.get(:level)
    |> case do
      nil -> cache.__levels__
      level -> [:lists.nth(level, cache.__levels__)]
    end
  end

  defp eval_while(ml_cache, fun, args, init) do
    Enum.reduce_while(ml_cache.__levels__, init, fn cache, acc ->
      if return = apply(cache.__adapter__, fun, [cache | args]),
        do: {:halt, return},
        else: {:cont, acc}
    end)
  end

  defp maybe_fallback({nil, levels}, cache, key, opts) do
    object =
      if fallback = opts[:fallback] || cache.__fallback__,
        do: %Object{key: key, value: eval_fallback(fallback, key)},
        else: nil

    {object, levels}
  end

  defp maybe_fallback(return, _, _, _), do: return

  defp eval_fallback(fallback, key) when is_function(fallback, 1), do: fallback.(key)
  defp eval_fallback({m, f}, key) when is_atom(m) and is_atom(f), do: apply(m, f, [key])

  defp maybe_replicate_data({nil, _}, _, _), do: nil
  defp maybe_replicate_data({%Object{value: nil}, _}, _, _), do: nil

  defp maybe_replicate_data({object, levels}, cache, opts) do
    cache.__model__
    |> case do
      :exclusive -> []
      :inclusive -> levels
    end
    |> Enum.reduce(object, & &1.__adapter__.set(&1, &2, opts))
  end

  defp do_mset(cache, objs, opts, acc) do
    case cache.__adapter__.mset(cache, objs, opts) do
      :ok ->
        {objs, acc}

      {:error, err_keys} ->
        objs = for %Object{key: key} = obj <- objs, not (key in err_keys), do: obj
        {objs, err_keys ++ acc}
    end
  end
end
