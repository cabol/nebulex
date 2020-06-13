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

  We can define a multi-level cache as follows:

      defmodule MyApp.Multilevel do
        use Nebulex.Cache,
          otp_app: :nebulex,
          adapter: Nebulex.Adapters.Multilevel
      end

  Where the configuration for the Cache must be in your application
  environment, usually defined in your `config/config.exs`:

      config :my_app, MyApp.Multilevel,
        model: :inclusive,
        levels: [
          l1: [
            gc_interval: 86_400_000,
            backend: :shards,
            partitions: 2
          ],
          l2: [
            adapter: Nebulex.Adapters.Partitioned,
            primary: [
              gc_interval: 86_400_000,
              backend: :shards,
              partitions: 2
            ]
          ]
        ]

  For more information about the usage, see `Nebulex.Cache` documentation.

  ## Options

  This adapter supports the following options and all of them can be given via
  the cache configuration:

    * `:levels` - A keyword list that defines each cache level configuration.
      The key is used as the name for that cache level, and the value is the
      level config, which depends on the adapter to use. The order in which
      the levels are defined is the same the multi-level cache will use. For
      example, the first cache in the list will be the L1 cache (level 1) and
      so on; the Nth elemnt will be the LN cache. This option is mandatory,
      if it is not set or empty, an exception will be raised.
      See "Shared Level Options" below.

    * `:model` - Specifies the cache model: `:inclusive` or `:exclusive`;
      defaults to `:inclusive`. In an inclusive cache, the same data can be
      present in all caches/levels. In an exclusive cache, data can be present
      in only one cache/level and a key cannot be found in the rest of caches
      at the same time. This option affects `get` operation only; if
      `:cache_model` is `:inclusive`, when the key is found in a level N,
      that entry is duplicated backwards (to all previous levels: 1..N-1).

  ## Shared Level Options

    * `:adapter` - The adapter to be used for the configured level.
      Defaults to `Nebulex.Adapters.Local`.

  **The rest of the options depend on the adapter to use.**

  ## Run-Time Options

  Some of the cache functions accept the following runtime options:

    * `:level` - It may be an integer greater than 0 that specifies the cache
      level where the operation will take place. By default, the evaluation
      is performed throughout the whole cache hierarchy (all levels).

  ## Extended API

  This adapter provides one additional convenience function for retrieving
  the cache model for the given cache `name`:

      MyCache.model()
      MyCache.model(:cache_name)

  ## Limitations

  Because this adapter reuses other existing/configured adapters, it inherits
  all their limitations too. Therefore, it is highly recommended to check the
  documentation of the adapters to use.
  """

  # Provide Cache Implementation
  @behaviour Nebulex.Adapter
  @behaviour Nebulex.Adapter.Queryable

  # Inherit default transaction implementation
  use Nebulex.Adapter.Transaction

  import Nebulex.Helpers

  alias Nebulex.Adapter
  alias Nebulex.Cache.Stats

  # Multi-level Cache Models
  @models [:inclusive, :exclusive]

  ## Adapter

  @impl true
  defmacro __before_compile__(_env) do
    quote do
      @doc """
      A convenience function to get the cache model.
      """
      def model(name \\ __MODULE__) do
        Adapter.with_meta(name, fn _adapter, %{model: model} ->
          model
        end)
      end
    end
  end

  @impl true
  def init(opts) do
    # required cache name
    name = opts[:name] || Keyword.fetch!(opts, :cache)

    # get cache levels
    levels =
      get_option(opts, :levels, &(Keyword.keyword?(&1) && length(&1) > 0)) ||
        raise "expected levels: to be a keyword with at least one entry"

    # get rest of the multilevel options
    model = get_option(opts, :model, &(&1 in @models), :inclusive)
    fallback = get_option(opts, :fallback, &is_function(&1, 1))
    stat_counter = Stats.init(opts)

    {children, meta_list} =
      levels
      |> Enum.reverse()
      |> Enum.reduce({[], []}, fn {l_name, l_opts}, {child_acc, meta_acc} ->
        {adapter, l_opts} = Keyword.pop(l_opts, :adapter, Nebulex.Adapters.Local)
        adapter = assert_behaviour(adapter, Nebulex.Adapter, "adapter")
        l_name = normalize_module_name([name, l_name])
        l_opts = [name: l_name, stat_counter: stat_counter] ++ l_opts
        {:ok, child, meta} = adapter.init(l_opts)
        {[child | child_acc], [{adapter, meta} | meta_acc]}
      end)

    child_spec =
      Nebulex.Adapters.Supervisor.child_spec(
        name: normalize_module_name([name, Supervisor]),
        strategy: :one_for_one,
        children: children
      )

    meta = %{
      name: name,
      levels: meta_list,
      model: model,
      fallback: fallback,
      stat_counter: stat_counter
    }

    {:ok, child_spec, meta}
  end

  @impl true
  def get(%{levels: levels, model: model}, key, opts) do
    fun = fn {adapter, meta} = level, {default, prev} ->
      if value = adapter.get(meta, key, opts) do
        {:halt, {value, [level | prev]}}
      else
        {:cont, {default, [level | prev]}}
      end
    end

    opts
    |> levels(levels)
    |> Enum.reduce_while({nil, []}, fun)
    |> maybe_replicate(key, model)
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
  def put(adapter_meta, key, value, ttl, on_write, opts) do
    eval(adapter_meta, :put, [key, value, ttl, on_write, opts], opts)
  end

  @impl true
  def put_all(%{levels: levels}, entries, ttl, on_write, opts) do
    opts
    |> levels(levels)
    |> Enum.reduce_while({true, []}, fn {adapter, meta} = level, {_, level_acc} ->
      case adapter.put_all(meta, entries, ttl, on_write, opts) do
        true ->
          {:cont, {true, [level | level_acc]}}

        false ->
          _ = delete_fromm_levels(level_acc, entries)
          {:halt, {on_write == :put, level_acc}}
      end
    end)
    |> elem(0)
  end

  @impl true
  def delete(adapter_meta, key, opts) do
    eval(adapter_meta, :delete, [key, opts], opts)
  end

  @impl true
  def take(%{levels: levels}, key, opts) do
    opts
    |> levels(levels)
    |> do_take(nil, key, opts)
  end

  defp do_take([], result, _key, _opts), do: result

  defp do_take([{adapter, meta} | rest], nil, key, opts) do
    result = adapter.take(meta, key, opts)
    do_take(rest, result, key, opts)
  end

  defp do_take(levels, result, key, _opts) do
    _ = eval(levels, :delete, [key, []])
    result
  end

  @impl true
  def has_key?(adapter_meta, key) do
    eval_while(adapter_meta, :has_key?, [key], false)
  end

  @impl true
  def incr(adapter_meta, key, incr, ttl, opts) do
    eval(adapter_meta, :incr, [key, incr, ttl, opts], opts)
  end

  @impl true
  def ttl(adapter_meta, key) do
    eval_while(adapter_meta, :ttl, [key], nil)
  end

  @impl true
  def expire(%{levels: levels}, key, ttl) do
    Enum.reduce(levels, false, fn {adapter, meta}, acc ->
      adapter.expire(meta, key, ttl) or acc
    end)
  end

  @impl true
  def touch(%{levels: levels}, key) do
    Enum.reduce(levels, false, fn {adapter, meta}, acc ->
      adapter.touch(meta, key) or acc
    end)
  end

  @impl true
  def size(%{levels: levels}) do
    Enum.reduce(levels, 0, fn {adapter, meta}, acc ->
      adapter.size(meta) + acc
    end)
  end

  @impl true
  def flush(%{levels: levels}) do
    Enum.reduce(levels, 0, fn {adapter, meta}, acc ->
      adapter.flush(meta) + acc
    end)
  end

  ## Queryable

  @impl true
  def all(%{levels: levels}, query, opts) do
    for {adapter, meta} <- levels,
        elems <- adapter.all(meta, query, opts),
        do: elems
  end

  @impl true
  def stream(%{levels: levels}, query, opts) do
    Stream.resource(
      fn ->
        levels
      end,
      fn
        [] ->
          {:halt, []}

        [{adapter, meta} | levels] ->
          elements =
            meta
            |> adapter.stream(query, opts)
            |> Enum.to_list()

          {elements, levels}
      end,
      & &1
    )
  end

  ## Helpers

  defp eval(%{levels: levels}, fun, args, opts) do
    eval(levels, fun, args, opts)
  end

  defp eval(levels, fun, args, opts) when is_list(levels) do
    opts
    |> levels(levels)
    |> eval(fun, args)
  end

  defp eval([{level, meta} | next], fun, args) do
    Enum.reduce(next, apply(level, fun, [meta | args]), fn {level, meta}, acc ->
      ^acc = apply(level, fun, [meta | args])
    end)
  end

  defp levels(opts, levels) do
    case Keyword.get(opts, :level) do
      nil -> levels
      level -> [Enum.at(levels, level - 1)]
    end
  end

  defp eval_while(%{levels: levels}, fun, args, init) do
    Enum.reduce_while(levels, init, fn {adapter, meta}, acc ->
      if return = apply(adapter, fun, [meta | args]),
        do: {:halt, return},
        else: {:cont, acc}
    end)
  end

  defp delete_fromm_levels(levels, entries) do
    for {adapter, meta} <- levels, {key, _} <- entries do
      adapter.delete(meta, key, [])
    end
  end

  defp maybe_replicate({nil, _}, _, _), do: nil

  defp maybe_replicate({value, [{adapter, meta} | [_ | _] = levels]}, key, :inclusive) do
    ttl = adapter.ttl(meta, key) || :infinity

    :ok =
      Enum.each(levels, fn {l_adapter, l_meta} ->
        _ = l_adapter.put(l_meta, key, value, ttl, :put, [])
      end)

    value
  end

  defp maybe_replicate({value, _levels}, _key, _model) do
    value
  end
end
