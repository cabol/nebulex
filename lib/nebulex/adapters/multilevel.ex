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
            gc_interval: :timer.hours(12),
            backend: :shards
          },
          {
            MyApp.Multilevel.L2,
            primary: [
              gc_interval: :timer.hours(12),
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

  ## Telemetry events

  This adapter emits all recommended Telemetry events, and documented
  in `Nebulex.Cache` module (see **"Adapter-specific events"** section).

  Since the multi-level adapter is a layer/wrapper on top of other existing
  adapters, each cache level may Telemetry emit events independently.
  For example, for the cache defined before `MyApp.Multilevel`, the next
  events will be emitted for the main multi-level cache:

    * `[:my_app, :multilevel, :command, :start]`
    * `[:my_app, :multilevel, :command, :stop]`
    * `[:my_app, :multilevel, :command, :exception]`

  For the L1 (configured with the local adapter):

    * `[:my_app, :multilevel, :l1, :command, :start]`
    * `[:my_app, :multilevel, :l1, :command, :stop]`
    * `[:my_app, :multilevel, :l1, :command, :exception]`

  For the L2 (configured with the partitioned adapter):

    * `[:my_app, :multilevel, :l2, :command, :start]`
    * `[:my_app, :multilevel, :l2, :primary, :command, :start]`
    * `[:my_app, :multilevel, :l2, :command, :stop]`
    * `[:my_app, :multilevel, :l2, :primary, :command, :stop]`
    * `[:my_app, :multilevel, :l2, :command, :exception]`
    * `[:my_app, :multilevel, :l2, :primary, :command, :exception]`

  See also the [Telemetry guide](http://hexdocs.pm/nebulex/telemetry.html)
  for more information and examples.

  ## Stats

  Since the multi-level adapter works as a wrapper for the configured cache
  levels, the support for stats depends on the underlying levels. Also, the
  measurements are consolidated per level, they are not aggregated. For example,
  if we enable the stats for the multi-level cache defined previously and run:

      MyApp.Multilevel.stats()

  The returned stats will look like:

      %Nebulex.Stats{
        measurements: %{
          l1: %{evictions: 0, expirations: 0, hits: 0, misses: 0, writes: 0},
          l2: %{evictions: 0, expirations: 0, hits: 0, misses: 0, writes: 0}
        },
        metadata: %{
          l1: %{
            cache: NMyApp.Multilevel.L1,
            started_at: ~U[2021-01-10 13:06:04.075084Z]
          },
          l2: %{
            cache: MyApp.Multilevel.L2.Primary,
            started_at: ~U[2021-01-10 13:06:04.089888Z]
          },
          cache: MyApp.Multilevel,
          started_at: ~U[2021-01-10 13:06:04.066750Z]
        }
      }

  **IMPORTANT:** Those cache levels with stats disabled won't be included
  into the returned stats (they are skipped). If a cache level is using
  an adapter that does not support stats, you may get unexpected errors.
  Therefore, and as overall recommendation, check out the documentation
  for adapters used by the underlying cache levels and ensure they
  implement the `Nebulex.Adapter.Stats` behaviour.

  ### Stats with Telemetry

  In case you are using Telemetry metrics, you can define the metrics per
  level, for example:

      last_value("nebulex.cache.stats.l1.hits",
        event_name: "nebulex.cache.stats",
        measurement: &get_in(&1, [:l1, :hits]),
        tags: [:cache]
      )
      last_value("nebulex.cache.stats.l1.misses",
        event_name: "nebulex.cache.stats",
        measurement: &get_in(&1, [:l1, :misses]),
        tags: [:cache]
      )

  > See the section **"Instrumenting Multi-level caches"** in the
    [Telemetry guide](http://hexdocs.pm/nebulex/telemetry.html)
    for more information.

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
  @behaviour Nebulex.Adapter.Entry
  @behaviour Nebulex.Adapter.Queryable
  @behaviour Nebulex.Adapter.Stats

  # Inherit default transaction implementation
  use Nebulex.Adapter.Transaction

  import Nebulex.Adapter
  import Nebulex.Helpers

  alias Nebulex.Cache.Cluster

  # Multi-level Cache Models
  @models [:inclusive, :exclusive]

  ## Nebulex.Adapter

  @impl true
  defmacro __before_compile__(_env) do
    quote do
      @doc """
      A convenience function to get the cache model.
      """
      def model(name \\ __MODULE__) do
        with_meta(name, fn _adapter, %{model: model} ->
          model
        end)
      end
    end
  end

  @impl true
  def init(opts) do
    # Required options
    telemetry_prefix = Keyword.fetch!(opts, :telemetry_prefix)
    telemetry = Keyword.fetch!(opts, :telemetry)
    cache = Keyword.fetch!(opts, :cache)
    name = opts[:name] || cache

    # Maybe use stats
    stats = get_boolean_option(opts, :stats)

    # Get cache levels
    levels =
      get_option(
        opts,
        :levels,
        "a list with at least one level definition",
        &(Keyword.keyword?(&1) && length(&1) > 0)
      )

    # Get multilevel-cache model
    model = get_option(opts, :model, ":inclusive or :exclusive", &(&1 in @models), :inclusive)

    # Build multi-level specs
    {children, meta_list, _} = children(levels, telemetry_prefix, telemetry, stats)

    # Build adapter spec
    child_spec =
      Nebulex.Adapters.Supervisor.child_spec(
        name: normalize_module_name([name, Supervisor]),
        strategy: :one_for_one,
        children: children
      )

    adapter_meta = %{
      telemetry_prefix: telemetry_prefix,
      telemetry: telemetry,
      name: name,
      levels: meta_list,
      model: model,
      stats: stats,
      started_at: DateTime.utc_now()
    }

    {:ok, child_spec, adapter_meta}
  end

  # sobelow_skip ["DOS.BinToAtom"]
  defp children(levels, telemetry_prefix, telemetry, stats) do
    levels
    |> Enum.reverse()
    |> Enum.reduce({[], [], length(levels)}, fn {l_cache, l_opts}, {child_acc, meta_acc, n} ->
      l_opts =
        Keyword.merge(
          [
            telemetry_prefix: telemetry_prefix ++ [:"l#{n}"],
            telemetry: telemetry,
            stats: stats
          ],
          l_opts
        )

      meta = %{cache: l_cache, name: l_opts[:name]}

      {[{l_cache, l_opts} | child_acc], [meta | meta_acc], n - 1}
    end)
  end

  ## Nebulex.Adapter.Entry

  @impl true
  defspan get(adapter_meta, key, opts) do
    fun = fn level, {default, prev} ->
      if value = with_dynamic_cache(level, :get, [key, opts]) do
        {:halt, {value, [level | prev]}}
      else
        {:cont, {default, [level | prev]}}
      end
    end

    opts
    |> levels(adapter_meta.levels)
    |> Enum.reduce_while({nil, []}, fun)
    |> maybe_replicate(key, adapter_meta.model)
  end

  @impl true
  defspan get_all(adapter_meta, keys, opts) do
    fun = fn level, {keys_acc, map_acc} ->
      map = with_dynamic_cache(level, :get_all, [keys_acc, opts])
      map_acc = Map.merge(map_acc, map)

      case keys_acc -- Map.keys(map) do
        [] -> {:halt, {[], map_acc}}
        keys_acc -> {:cont, {keys_acc, map_acc}}
      end
    end

    opts
    |> levels(adapter_meta.levels)
    |> Enum.reduce_while({keys, %{}}, fun)
    |> elem(1)
  end

  @impl true
  defspan put(adapter_meta, key, value, _ttl, on_write, opts) do
    case on_write do
      :put ->
        :ok = eval(adapter_meta, :put, [key, value, opts], opts)
        true

      :put_new ->
        eval(adapter_meta, :put_new, [key, value, opts], opts)

      :replace ->
        eval(adapter_meta, :replace, [key, value, opts], opts)
    end
  end

  @impl true
  defspan put_all(adapter_meta, entries, _ttl, on_write, opts) do
    action = if on_write == :put_new, do: :put_new_all, else: :put_all

    reducer = fn level, {_, level_acc} ->
      case with_dynamic_cache(level, action, [entries, opts]) do
        :ok ->
          {:cont, {true, [level | level_acc]}}

        true ->
          {:cont, {true, [level | level_acc]}}

        false ->
          _ = delete_from_levels(level_acc, entries)
          {:halt, {on_write == :put, level_acc}}
      end
    end

    opts
    |> levels(adapter_meta.levels)
    |> Enum.reduce_while({true, []}, reducer)
    |> elem(0)
  end

  @impl true
  defspan delete(adapter_meta, key, opts) do
    eval(adapter_meta, :delete, [key, opts], opts)
  end

  @impl true
  defspan take(adapter_meta, key, opts) do
    opts
    |> levels(adapter_meta.levels)
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
  defspan exists?(adapter_meta, key) do
    eval_while(adapter_meta, :exists?, [key], false)
  end

  @impl true
  defspan update_counter(adapter_meta, key, amount, _ttl, _default, opts) do
    eval(adapter_meta, :incr, [key, amount, opts], opts)
  end

  @impl true
  defspan ttl(adapter_meta, key) do
    eval_while(adapter_meta, :ttl, [key], nil)
  end

  @impl true
  defspan expire(adapter_meta, key, ttl) do
    Enum.reduce(adapter_meta.levels, false, fn l_meta, acc ->
      with_dynamic_cache(l_meta, :expire, [key, ttl]) or acc
    end)
  end

  @impl true
  defspan touch(adapter_meta, key) do
    Enum.reduce(adapter_meta.levels, false, fn l_meta, acc ->
      with_dynamic_cache(l_meta, :touch, [key]) or acc
    end)
  end

  ## Nebulex.Adapter.Queryable

  @impl true
  defspan execute(adapter_meta, operation, query, opts) do
    {reducer, acc_in} =
      case operation do
        :all -> {&(&1 ++ &2), []}
        _ -> {&(&1 + &2), 0}
      end

    Enum.reduce(adapter_meta.levels, acc_in, fn level, acc ->
      level
      |> with_dynamic_cache(operation, [query, opts])
      |> reducer.(acc)
    end)
  end

  @impl true
  defspan stream(adapter_meta, query, opts) do
    Stream.resource(
      fn ->
        adapter_meta.levels
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

  ## Nebulex.Adapter.Transaction

  @impl true
  defspan transaction(adapter_meta, opts, fun) do
    # Perhaps one of the levels is a distributed adapter,
    # then ensure the lock on the right cluster nodes.
    nodes =
      adapter_meta.levels
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

  @impl true
  defspan in_transaction?(adapter_meta) do
    super(adapter_meta)
  end

  ## Nebulex.Adapter.Stats

  @impl true
  defspan stats(adapter_meta) do
    if adapter_meta.stats do
      init_acc = %Nebulex.Stats{
        metadata: %{
          cache: adapter_meta.name || adapter_meta.cache,
          started_at: adapter_meta.started_at
        }
      }

      adapter_meta.levels
      |> Enum.with_index(1)
      |> Enum.reduce(init_acc, &update_stats/2)
    end
  end

  # We can safely disable this warning since the atom created dynamically is
  # always re-used; the number of levels is limited and known before hand.
  # sobelow_skip ["DOS.BinToAtom"]
  defp update_stats({meta, idx}, stats_acc) do
    if stats = with_dynamic_cache(meta, :stats, []) do
      level_idx = :"l#{idx}"
      measurements = Map.put(stats_acc.measurements, level_idx, stats.measurements)
      metadata = Map.put(stats_acc.metadata, level_idx, stats.metadata)
      %{stats_acc | measurements: measurements, metadata: metadata}
    else
      stats_acc
    end
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
