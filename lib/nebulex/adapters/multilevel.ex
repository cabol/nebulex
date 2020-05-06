defmodule Nebulex.Adapters.Multilevel do
  @moduledoc ~S"""
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

  ## Compile-Time Options

  In addition to `:otp_app` and `:adapter`, this adapter supports the next
  compile-time options:

    * `:levels` - The list of caches where each cache corresponds to a level.
      The order of the caches in the list defines the the order of the levels
      as well, for example, the first cache in the list will be the L1 cache
      (level 1) and so on; the Nth elemnt will be the LN cache. This option
      is mandatory, if it is not set or empty, an exception will be raised.

    * `:cache_model` - Specifies the cache model: `:inclusive` or `:exclusive`;
      defaults to `:inclusive`. In an inclusive cache, the same data can be
      present in all caches/levels. In an exclusive cache, data can be present
      in only one cache/level and a key cannot be found in the rest of caches
      at the same time. This option affects `get` operation only; if
      `:cache_model` is `:inclusive`, when the key is found in a level N,
      that entry is duplicated backwards (to all previous levels: 1..N-1).

    * `:fallback` - Defines a global fallback function when a key is not present
      in any cache level. Function is defined as: `(key -> value)`.

  ## Run-Time Options

  Some functions below accept the following options:

    * `:level` - It may be an integer greater than 0 that specifies the cache
      level where the operation will take place. By default, the evaluation
      is performed throughout the whole cache hierarchy (all levels).

    * `:fallback` - Defines a fallback function when a key is not present
      in any cache level. Function is defined as: `(key -> value)`. For example:
      `MultilevelCache.get("foo", fallback: fn(key) -> key * 2 end)`.

  ## Example

  `Nebulex.Cache` is the wrapper around the Cache. We can define the
  multi-level cache as follows:

      defmodule MyApp.MultilevelCache do
        use Nebulex.Cache,
          otp_app: :nebulex,
          adapter: Nebulex.Adapters.Multilevel,
          fallback: &__MODULE__.fallback/1,
          levels: [
            MyApp.MultilevelCache.L1,
            MyApp.MultilevelCache.L2
          ]

        defmodule L1 do
          use Nebulex.Cache,
            otp_app: :nebulex,
            adapter: Nebulex.Adapters.Local,
            backend: :shards
        end

        defmodule L2 do
          use Nebulex.Cache,
            otp_app: :nebulex,
            adapter: Nebulex.Adapters.Partitioned,
            primary: MyApp.MultilevelCache.L2.Primary

          defmodule Primary do
            use Nebulex.Cache,
              otp_app: :my_app,
              adapter: Nebulex.Adapters.Local,
              backend: :shards
          end
        end

        def fallback(_key) do
          # maybe fetch the data from Database
          nil
        end
      end

  Where the configuration for the Cache must be in your application
  environment, usually defined in your `config/config.exs`:

      config :my_app, MyApp.MultilevelCache.L1,
        gc_interval: Nebulex.Time.expiry_time(1, :hour),
        partitions: 2

      config :my_app, MyApp.MultilevelCache.L2.Primary,
        gc_interval: Nebulex.Time.expiry_time(1, :hour),
        partitions: 2

  Using the multilevel cache cache:

      # Retrieving data from cache
      MyCache.get("foo", fallback: fn(_key) ->
        # Maybe fetch the key from database
        "initial value"
      end)

      # Entry is set in all cache levels
      MyCache.put("foo", "bar")

      # Entry is set at second cache level
      MyCache.put("foo", "bar", level: 2)

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
  @behaviour Nebulex.Adapter.Queryable

  # Inherit default transaction implementation
  use Nebulex.Adapter.Transaction

  import Nebulex.Helpers

  # Multi-level Cache Models
  @models [:inclusive, :exclusive]

  ## Adapter

  @impl true
  defmacro __before_compile__(env) do
    opts = Module.get_attribute(env.module, :opts)
    cache_model = get_option(opts, :cache_model, &(&1 in @models), :inclusive)
    fallback = get_option(opts, :fallback, &is_function(&1, 1))

    levels =
      get_option(opts, :levels, &(is_list(&1) && length(&1) > 0)) ||
        raise ArgumentError, "expected levels: to be a list and have at least one level"

    quote do
      @doc """
      A convenience function for getting the cache levels.
      """
      def __levels__, do: unquote(levels)

      @doc """
      A convenience function for getting the cache model.
      """
      def __model__, do: unquote(cache_model)

      @doc """
      A convenience function for getting the default fallback.
      """
      def __fallback__, do: unquote(fallback)
    end
  end

  @impl true
  def init(opts) do
    cache = Keyword.fetch!(opts, :cache)

    children =
      for level <- cache.__levels__ do
        {level, Keyword.put(opts, :cache, level)}
      end

    child_spec =
      Nebulex.Adapters.Supervisor.child_spec(
        name: Module.concat(cache, Supervisor),
        strategy: :one_for_one,
        children: children
      )

    {:ok, child_spec}
  end

  @impl true
  def get(cache, key, opts) do
    fun = fn current, {_, prev} ->
      if value = current.__adapter__.get(current, key, opts) do
        {:halt, {value, prev}}
      else
        {:cont, {nil, [current | prev]}}
      end
    end

    cache.__levels__
    |> Enum.reduce_while({nil, []}, fun)
    |> maybe_fallback(cache, key, opts)
    |> maybe_replicate(cache)
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
  def put(cache, key, value, ttl, on_write, opts) do
    eval(cache, :put, [key, value, ttl, on_write, opts], opts)
  end

  @impl true
  def put_all(cache, entries, ttl, on_write, opts) do
    opts
    |> levels(cache)
    |> Enum.reduce_while(true, fn level, acc ->
      case level.__adapter__.put_all(level, entries, ttl, on_write, opts) do
        true ->
          {:cont, acc}

        false ->
          :ok = Enum.each(entries, &level.__adapter__.delete(level, elem(&1, 0), []))
          {:halt, on_write == :put}
      end
    end)
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
  def incr(cache, key, incr, ttl, opts) do
    eval(cache, :incr, [key, incr, ttl, opts], opts)
  end

  @impl true
  def ttl(cache, key) do
    eval_while(cache, :ttl, [key], nil)
  end

  @impl true
  def expire(cache, key, ttl) do
    Enum.reduce(cache.__levels__, false, fn level_cache, acc ->
      level_cache.__adapter__.expire(level_cache, key, ttl) or acc
    end)
  end

  @impl true
  def touch(cache, key) do
    Enum.reduce(cache.__levels__, false, fn level_cache, acc ->
      level_cache.__adapter__.touch(level_cache, key) or acc
    end)
  end

  @impl true
  def size(cache) do
    Enum.reduce(cache.__levels__, 0, fn level_cache, acc ->
      level_cache.__adapter__.size(level_cache) + acc
    end)
  end

  @impl true
  def flush(cache) do
    Enum.reduce(cache.__levels__, 0, fn level_cache, acc ->
      level_cache.__adapter__.flush(level_cache) + acc
    end)
  end

  ## Queryable

  @impl true
  def all(cache, query, opts) do
    for level_cache <- cache.__levels__,
        elems <- level_cache.__adapter__.all(level_cache, query, opts),
        do: elems
  end

  @impl true
  def stream(cache, query, opts) do
    Stream.resource(
      fn ->
        cache.__levels__
      end,
      fn
        [] ->
          {:halt, []}

        [level | levels] ->
          elements =
            level
            |> level.__adapter__.stream(query, opts)
            |> Enum.to_list()

          {elements, levels}
      end,
      & &1
    )
  end

  ## Helpers

  defp eval(ml_cache, fun, args, opts) do
    opts
    |> levels(ml_cache)
    |> eval(fun, args)
  end

  defp eval([l1 | next], fun, args) do
    Enum.reduce(next, apply(l1.__adapter__, fun, [l1 | args]), fn cache, acc ->
      ^acc = apply(cache.__adapter__, fun, [cache | args])
    end)
  end

  defp levels(opts, cache) do
    case Keyword.get(opts, :level) do
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
    value =
      if fallback = opts[:fallback] || cache.__fallback__,
        do: eval_fallback(fallback, key),
        else: nil

    {key, value, levels}
  end

  defp maybe_fallback({value, levels}, _, key, _opts) do
    {key, value, levels}
  end

  defp eval_fallback(fallback, key) when is_function(fallback, 1),
    do: fallback.(key)

  defp eval_fallback({m, f}, key) when is_atom(m) and is_atom(f),
    do: apply(m, f, [key])

  defp maybe_replicate({_, nil, _}, _), do: nil

  defp maybe_replicate({key, value, levels}, cache) do
    if cache.__model__ == :inclusive do
      :ok = Enum.each(levels, & &1.put(key, value, ttl: cache.ttl(key)))
    end

    value
  end
end
