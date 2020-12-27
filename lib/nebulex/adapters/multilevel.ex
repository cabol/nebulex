defmodule Nebulex.Adapters.Multilevel do
  @moduledoc ~S"""
  Adapter module for Multi-level Cache.

  This is just a simple layer on top of local or distributed cache
  implementations that enables to have a cache hierarchy by levels.
  Multi-level caches generally operate by checking the fastest,
  level 1 (L1) cache first; if it hits, the adapter proceeds at
  high speed. If that first cache misses, the next fastest cache
  (level 2, L2) is checked, and so on, before accessing external
  memory (that can be handled by a `cacheable` decorator).

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

        defmodule L1 do
          use Nebulex.Cache,
            otp_app: :nebulex,
            adapter: Nebulex.Adapters.Local
        end

        defmodule L2 do
          use Nebulex.Cache,
            otp_app: :nebulex,
            adapter: Nebulex.Adapters.Partitioned
        end
      end

  Where the configuration for the cache and its levels must be in your
  application environment, usually defined in your `config/config.exs`:

      config :my_app, MyApp.Multilevel,
        model: :inclusive,
        levels: [
          {
            MyApp.Multilevel.L1,
            gc_interval: :timer.seconds(3600) * 12,
            backend: :shards
          },
          {
            MyApp.Multilevel.L2,
            primary: [
              gc_interval: :timer.seconds(3600) * 12,
              backend: :shards
            ]
          }
        ]

  If your application was generated with a supervisor (by passing `--sup`
  to `mix new`) you will have a `lib/my_app/application.ex` file containing
  the application start callback that defines and starts your supervisor.
  You just need to edit the `start/2` function to start the cache as a
  supervisor on your application's supervisor:

      def start(_type, _args) do
        children = [
          {MyApp.Multilevel, []},
          ...
        ]

  See `Nebulex.Cache` for more information.

  ## Options

  This adapter supports the following options and all of them can be given via
  the cache configuration:

    * `:levels` - This option is to define the levels, a list of tuples
      `{cache_level :: Nebulex.Cache.t(), opts :: Keyword.t()}`, where
      the first element is the module that defines the cache for that
      level, and the second one is the options that will be passed to
      that level in the `start/link/1` (which depends on the adapter
      this level is using). The order in which the levels are defined
      is the same the multi-level cache will use. For example, the first
      cache in the list will be the L1 cache (level 1) and so on;
      the Nth element will be the LN cache. This option is mandatory,
      if it is not set or empty, an exception will be raised.

    * `:model` - Specifies the cache model: `:inclusive` or `:exclusive`;
      defaults to `:inclusive`. In an inclusive cache, the same data can be
      present in all caches/levels. In an exclusive cache, data can be present
      in only one cache/level and a key cannot be found in the rest of caches
      at the same time. This option affects `get` operation only; if
      `:cache_model` is `:inclusive`, when the key is found in a level N,
      that entry is duplicated backwards (to all previous levels: 1..N-1).

  ## Shared options

  Almost all of the cache functions outlined in `Nebulex.Cache` module
  accept the following options:

    * `:level` - It may be an integer greater than 0 that specifies the cache
      level where the operation will take place. By default, the evaluation
      is performed throughout the whole cache hierarchy (all levels).

  ## Extended API

  This adapter provides one additional convenience function for retrieving
  the cache model for the given cache `name`:

      MyCache.model()
      MyCache.model(:cache_name)

  ## Caveats of multi-level adapter

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
  alias Nebulex.Cache.{Cluster, Stats}

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
    cache = Keyword.fetch!(opts, :cache)
    name = opts[:name] || cache

    # maybe use stats
    stat_counter = Stats.init(opts)

    # get cache levels
    levels =
      get_option(opts, :levels, &(Keyword.keyword?(&1) && length(&1) > 0)) ||
        raise """
        expected levels: to be a list with at least one level definition, e.g.:

        levels: [{MyCache.L1, gc_interval: 3_600_000, ...}, ...]
        """

    # get multilevel-cache model
    model = get_option(opts, :model, &(&1 in @models), :inclusive)

    {children, meta_list} =
      levels
      |> Enum.reverse()
      |> Enum.reduce({[], []}, fn {l_cache, l_opts}, {child_acc, meta_acc} ->
        meta = %{cache: l_cache, name: l_opts[:name]}
        l_opts = [stat_counter: stat_counter] ++ l_opts
        {[{l_cache, l_opts} | child_acc], [meta | meta_acc]}
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
      stat_counter: stat_counter
    }

    {:ok, child_spec, meta}
  end

  @impl true
  def get(%{levels: levels, model: model}, key, opts) do
    fun = fn level, {default, prev} ->
      if value = with_dynamic_cache(level, :get, [key, opts]) do
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
  def put(adapter_meta, key, value, _ttl, :put, opts) do
    :ok = eval(adapter_meta, :put, [key, value, opts], opts)
    true
  end

  def put(adapter_meta, key, value, _ttl, :put_new, opts) do
    eval(adapter_meta, :put_new, [key, value, opts], opts)
  end

  def put(adapter_meta, key, value, _ttl, :replace, opts) do
    eval(adapter_meta, :replace, [key, value, opts], opts)
  end

  @impl true
  def put_all(%{levels: levels}, entries, _ttl, on_write, opts) do
    action = if on_write == :put_new, do: :put_new_all, else: :put_all

    opts
    |> levels(levels)
    |> Enum.reduce_while({true, []}, fn level, {_, level_acc} ->
      case with_dynamic_cache(level, action, [entries, opts]) do
        :ok ->
          {:cont, {true, [level | level_acc]}}

        true ->
          {:cont, {true, [level | level_acc]}}

        false ->
          _ = delete_from_levels(level_acc, entries)
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

  defp do_take([l_meta | rest], nil, key, opts) do
    result = with_dynamic_cache(l_meta, :take, [key, opts])
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
  def incr(adapter_meta, key, incr, _ttl, opts) do
    eval(adapter_meta, :incr, [key, incr, opts], opts)
  end

  @impl true
  def ttl(adapter_meta, key) do
    eval_while(adapter_meta, :ttl, [key], nil)
  end

  @impl true
  def expire(%{levels: levels}, key, ttl) do
    Enum.reduce(levels, false, fn l_meta, acc ->
      with_dynamic_cache(l_meta, :expire, [key, ttl]) or acc
    end)
  end

  @impl true
  def touch(%{levels: levels}, key) do
    Enum.reduce(levels, false, fn l_meta, acc ->
      with_dynamic_cache(l_meta, :touch, [key]) or acc
    end)
  end

  @impl true
  def size(%{levels: levels}) do
    Enum.reduce(levels, 0, fn l_meta, acc ->
      with_dynamic_cache(l_meta, :size, []) + acc
    end)
  end

  @impl true
  def flush(%{levels: levels}) do
    Enum.reduce(levels, 0, fn l_meta, acc ->
      with_dynamic_cache(l_meta, :flush, []) + acc
    end)
  end

  ## Queryable

  @impl true
  def all(%{levels: levels}, query, opts) do
    for level <- levels,
        elems <- with_dynamic_cache(level, :all, [query, opts]),
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

        [level | levels] ->
          elements =
            level
            |> with_dynamic_cache(:stream, [query, opts])
            |> Enum.to_list()

          {elements, levels}
      end,
      & &1
    )
  end

  ## Transaction

  @impl true
  def transaction(%{levels: levels} = adapter_meta, opts, fun) do
    # Perhaps one of the levels is a distributed adapter,
    # then ensure the lock on the right cluster nodes.
    nodes =
      levels
      |> Enum.reduce([node()], fn %{name: name, cache: cache}, acc ->
        if cache.__adapter__ in [Nebulex.Adapters.Partitioned, Nebulex.Adapters.Replicated] do
          Cluster.get_nodes(name || cache) ++ acc
        else
          acc
        end
      end)
      |> Enum.uniq()

    super(adapter_meta, Keyword.put(opts, :nodes, nodes), fun)
  end

  ## Helpers

  defp with_dynamic_cache(%{cache: cache, name: nil}, action, args) do
    apply(cache, action, args)
  end

  defp with_dynamic_cache(%{cache: cache, name: name}, action, args) do
    cache.with_dynamic_cache(name, fn ->
      apply(cache, action, args)
    end)
  end

  defp eval(%{levels: levels}, fun, args, opts) do
    eval(levels, fun, args, opts)
  end

  defp eval(levels, fun, args, opts) when is_list(levels) do
    opts
    |> levels(levels)
    |> eval(fun, args)
  end

  defp eval([level_meta | next], fun, args) do
    Enum.reduce(next, with_dynamic_cache(level_meta, fun, args), fn l_meta, acc ->
      ^acc = with_dynamic_cache(l_meta, fun, args)
    end)
  end

  defp levels(opts, levels) do
    case Keyword.get(opts, :level) do
      nil -> levels
      level -> [Enum.at(levels, level - 1)]
    end
  end

  defp eval_while(%{levels: levels}, fun, args, init) do
    Enum.reduce_while(levels, init, fn level_meta, acc ->
      if return = with_dynamic_cache(level_meta, fun, args),
        do: {:halt, return},
        else: {:cont, acc}
    end)
  end

  defp delete_from_levels(levels, entries) do
    for level_meta <- levels, {key, _} <- entries do
      with_dynamic_cache(level_meta, :delete, [key, []])
    end
  end

  defp maybe_replicate({nil, _}, _, _), do: nil

  defp maybe_replicate({value, [level_meta | [_ | _] = levels]}, key, :inclusive) do
    ttl = with_dynamic_cache(level_meta, :ttl, [key]) || :infinity

    :ok =
      Enum.each(levels, fn l_meta ->
        _ = with_dynamic_cache(l_meta, :put, [key, value, [ttl: ttl]])
      end)

    value
  end

  defp maybe_replicate({value, _levels}, _key, _model) do
    value
  end
end
