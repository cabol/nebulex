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
      at the same time. This option affects get operation only.

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
  @behaviour Nebulex.Adapter.Transaction

  alias Nebulex.Object

  ## Adapter Impl

  @doc false
  defmacro __before_compile__(env) do
    otp_app = Module.get_attribute(env.module, :otp_app)
    config = Module.get_attribute(env.module, :config)
    cache_model = Keyword.get(config, :cache_model, :inclusive)
    fallback = Keyword.get(config, :fallback)
    levels = Keyword.get(config, :levels)

    unless levels do
      raise ArgumentError,
        "missing :levels configuration in config " <>
        "#{inspect otp_app}, #{inspect env.module}"
    end

    unless is_list(levels) && length(levels) > 0 do
      raise ArgumentError,
        ":levels configuration in config must have at least one level, " <>
        "got: #{inspect levels}"
    end

    quote do
      def __levels__, do: unquote(levels)

      def __model__, do: unquote(cache_model)

      def __fallback__, do: unquote(fallback)
    end
  end

  ## Adapter Impl

  @doc false
  def children_specs(_cache, _opts), do: []

  @doc """
  Retrieves the requested key (if it exists) checking the fastest,
  level 1 (L1) cache first; if it hits, the adapter proceeds at
  high speed. If that first cache misses, the next fastest cache
  (level 2, L2) is checked, and so on, before accessing external
  memory (that can be handled by the `:fallback` function).

  If `:cache_model` is `:inclusive`, when the key is found in a level N,
  that entry is duplicated backwards (to all previous levels: 1..N-1).

  ## Options

    * `:fallback` - Defines a fallback function when a key is not present
      in any cache level. Function is defined as: `(key -> value)`.

  See the "Shared options" section at the module documentation and alse
  `Nebulex.Cache`.

  ## Example

      MyCache.get("foo", fallback: fn(_key) ->
        # Maybe fetch the key from database
        "initial value"
      end)
  """
  def get(cache, key, opts) do
    fun =
      fn(current, {_, prev}) ->
        if object = current.get(key, Keyword.put(opts, :return, :object)) do
          {:halt, {object, [current | prev]}}
        else
          {:cont, {nil, [current | prev]}}
        end
      end

    cache.__levels__
    |> Enum.reduce_while({nil, []}, fun)
    |> maybe_fallback(cache, key, opts)
    |> maybe_replicate_data(cache, opts)
    |> validate_return(opts)
  end

  @doc """
  Sets the given `value` under `key` in the Cache.

  ## Options

    * `:level` - Check shared options in module documentation.

  ## Example

      # Entry is set in all cache levels
      MyCache.set("foo", "bar")

      # Entry is set at second cache level
      MyCache.set("foo", "bar", level: 2)
  """
  def set(_cache, _key, nil, _opts),
    do: nil
  def set(cache, key, value, opts) do
    eval(cache, :set, [key, value, opts], opts)
  end

  @doc """
  Deletes the cached entry in for a specific `key`.

  ## Options

    * `:level` - Check shared options in module documentation.

  ## Example

      # Entry is deleted from all cache levels
      MyCache.delete("foo")

      # Entry is deleted from second cache level
      MyCache.delete("foo", level: 2)
  """
  def delete(cache, key, opts) do
    eval(cache, :delete, [key, opts], opts)
  end

  @doc """
  Evaluates this operation on each cache level until get a non-empty result
  (different from nil or false), otherwise it returns the latest obtained
  result (last cache level).

  ## Examples

      MyCache.has_key?(:a)
  """
  def has_key?(cache, key) do
    eval_while(cache, :has_key?, [key], false)
  end

  @doc """
  Returns the total number of entries in all cache levels.

  ## Examples

      MyCache.size
  """
  def size(cache) do
    Enum.reduce(cache.__levels__, 0, fn(level_cache, acc) ->
      level_cache.size() + acc
    end)
  end

  @doc """
  Flushes all cache levels.

  ## Examples

      MyCache.flush
  """
  def flush(cache) do
    Enum.each(cache.__levels__, fn(level_cache) ->
      level_cache.flush()
    end)
  end

  @doc """
  Returns all cached keys in all cache levels.

  ## Examples

      MyCache.keys
  """
  def keys(cache) do
    cache.__levels__
    |> Enum.reduce([], fn(level_cache, acc) -> level_cache.keys() ++ acc end)
    |> :lists.usort()
  end

  @doc """
  Execute the reduce function in all cache levels.

  ## Examples

      MyCache.reduce({%{}, 0}, fn({key, value}, {acc1, acc2}) ->
        if Map.has_key?(acc1, key),
          do: {acc1, acc2},
          else: {Map.put(acc1, key, value), value + acc2}
      end)
  """
  def reduce(cache, acc_in, fun, opts) do
    Enum.reduce(cache.__levels__, acc_in, fn(level_cache, acc) ->
      level_cache.reduce(acc, fun, opts)
    end)
  end

  @doc """
  Returns a map with all cached entries in all cache levels.

  ## Examples

      MyCache.to_map
  """
  def to_map(cache, opts) do
    Enum.reduce(cache.__levels__, %{}, fn(level_cache, acc) ->
      opts
      |> level_cache.to_map()
      |> Map.merge(acc)
    end)
  end

  @doc """
  Evaluates this operation on each cache level until get a non-empty result
  (different from nil or false), otherwise it returns the latest obtained
  result (last cache level).

  ## Examples

      MyCache.pop(:a)
  """
  def pop(cache, key, opts) do
    eval_while(cache, :pop, [key, opts])
  end

  @doc """
  Gets the value from `key` and updates it, all in one pass.

  ## Options

    * `:level` - Check shared options in module documentation.

  ## Example

      {nil, "value!"} = MyCache.get_and_update(:a, fn current_value ->
        {current_value, "value!"}
      end)
  """
  def get_and_update(cache, key, fun, opts) when is_function(fun, 1) do
    eval(cache, :get_and_update, [key, fun, opts], opts)
  end

  @doc """
  Updates the cached `key` with the given function.

  ## Options

    * `:level` - Check shared options in module documentation.

  ## Example

      MyCache.update(:a, 1, &(&1 * 2))
  """
  def update(cache, key, initial, fun, opts) do
    eval(cache, :update, [key, initial, fun, opts], opts)
  end

  @doc """
  Updates (increment or decrement) the counter mapped to the given `key`.

  ## Options

    * `:level` - Check shared options in module documentation.

  ## Example

      # Counter is incremented in all cache levels
      MyCache.update_counter("foo", "bar")
  """
  def update_counter(cache, key, incr, opts) do
    eval(cache, :update_counter, [key, incr, opts], opts)
  end

  @doc """
  Runs the given function inside a transaction.

  A successful transaction returns the value returned by the function.

  ## Options

    * `:level` - Check shared options in module documentation.

  ## Example

      MyCache.transaction(fn ->
        1 = MyCache.set(:a, 1)
        true = MyCache.has_key?(:a)
        MyCache.get(:a)
      end)
  """
  def transaction(cache, opts, fun) do
    eval(cache, :transaction, [fun, opts])
  end

  @doc """
  Returns `true` if the given process is inside a transaction in any of the
  cache levels.
  """
  def in_transaction?(cache) do
    results =
      Enum.reduce(cache.__levels__, [], fn(level, acc) ->
        [level.in_transaction?() | acc]
      end)
    true in results
  end

  ## Helpers

  defp eval(ml_cache, fun, args, opts \\ []) do
    [l1 | next] = eval_levels(opts[:level], ml_cache)

    Enum.reduce(next, apply(l1, fun, args), fn(cache, acc) ->
      ^acc = apply(cache, fun, args)
    end)
  end

  defp eval_levels(nil, cache),
    do: cache.__levels__
  defp eval_levels(level, cache) when is_integer(level),
    do: [:lists.nth(level, cache.__levels__)]

  defp eval_while(ml_cache, fun, args, init \\ nil) do
    Enum.reduce_while(ml_cache.__levels__, init, fn(cache, acc) ->
      if return = apply(cache, fun, args) do
        {:halt, return}
      else
        {:cont, acc}
      end
    end)
  end

  defp maybe_fallback({nil, levels}, cache, key, opts) do
    object =
      if fallback = opts[:fallback] || cache. __fallback__,
        do: %Object{key: key, value: eval_fallback(fallback, key)},
        else: nil

    {object, levels}
  end
  defp maybe_fallback(return, _, _, _), do: return

  defp eval_fallback(fallback, key) when is_function(fallback, 1),
    do: fallback.(key)
  defp eval_fallback({m, f}, key) when is_atom(m) and is_atom(f),
    do: apply(m, f, [key])

  defp maybe_replicate_data({nil, _}, _, _),
    do: nil
  defp maybe_replicate_data({%Object{value: nil}, _}, _, _),
    do: nil
  defp maybe_replicate_data({object, levels}, cache, opts) do
    opts = Keyword.put(opts, :return, :object)

    replicas =
      case cache.__model__ do
        :exclusive -> []
        :inclusive -> levels
      end

    Enum.reduce(replicas, object, &(&1.set(&2.key, &2.value, opts)))
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
end
