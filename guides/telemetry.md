# Telemetry

This guide aims to show you how to instrument and report on `:telemetry` events
in your application for cache statistics.

This guide is not focused on explaining `:telemetry`, how it works, configure
it, and so on. Instead, it is focused on how we can use `:telemetry` for
reporting cache stats. For more information about `:telemetry` you can check
the docs, or the [Phoenix Telemetry](https://hexdocs.pm/phoenix/telemetry.html)
guide is also recommended.

## Instrumenting Nebulex Caches

Each adapter is responsible for providing stats by implementing
`Nebulex.Adapter.Stats` behaviour. Nevertheless, Nebulex provides a default
implementation using [Erlang counters][erl_counters], which is supported by
the built-in adapters (with all callbacks overridable).
See `Nebulex.Adapter.Stats` for more information.

[erl_counters]: https://erlang.org/doc/man/counters.html

Furthermore, when the `:stats` option is enabled, we can use Telemetry for
emitting the current stat values.

First of all, let's configure the dependencies adding `:telemetry_metrics`
and `:telemetry_poller` packages:

```elixir
def deps do
  [
    {:nebulex, "2.0.0-rc.2"},
    {:shards, "~> 1.0"},
    {:decorator, "~> 1.3"},
    {:telemetry, "~> 0.4"},
    {:telemetry_metrics, "~> 0.6"},
    {:telemetry_poller, "~> 0.5"}
  ]
end
```

Then define the cache and add the configuration:

```elixir
defmodule MyApp.Cache do
  use Nebulex.Cache,
    otp_app: :my_app,
    adapter: Nebulex.Adapters.Local
end
```

Could be configured:

```elixir
config :my_app, MyApp.Cache,
  stats: true,
  backend: :shards,
  gc_interval: 86_400_000,
  max_size: 1_000_000,
  gc_cleanup_min_timeout: 10_000,
  gc_cleanup_max_timeout: 900_000
```

Create your Telemetry supervisor at `lib/my_app/telemetry.ex`:

```elixir
# lib/my_app/telemetry.ex
defmodule MyApp.Telemetry do
  use Supervisor
  import Telemetry.Metrics

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  def init(_arg) do
    children = [
      # Configure `:telemetry_poller` for reporting the cache stats
      {:telemetry_poller, measurements: periodic_measurements(), period: 10_000},

      # For example, we use the console reporter, but you can change it.
      # See `:telemetry_metrics` for for information.
      {Telemetry.Metrics.ConsoleReporter, metrics: metrics()}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  defp metrics do
    [
      # Nebulex Stats Metrics
      last_value("nebulex.cache.stats.hits", tags: [:cache]),
      last_value("nebulex.cache.stats.misses", tags: [:cache]),
      last_value("nebulex.cache.stats.writes", tags: [:cache]),
      last_value("nebulex.cache.stats.evictions", tags: [:cache]),
      last_value("nebulex.cache.stats.expirations", tags: [:cache]),

      # VM Metrics
      summary("vm.memory.total", unit: {:byte, :kilobyte}),
      summary("vm.total_run_queue_lengths.total"),
      summary("vm.total_run_queue_lengths.cpu"),
      summary("vm.total_run_queue_lengths.io")
    ]
  end

  defp periodic_measurements do
    [
      {MyApp.Cache, :dispatch_stats, []}
    ]
  end
end
```

> Make sure to replace `MyApp` by your actual application name.

Then add to your main application's supervision tree
(usually in `lib/my_app/application.ex`):

```elixir
children = [
  MyApp.Cache,
  MyApp.Telemetry,
  ...
]
```

Now start an IEx session and call the server:

```
iex(1)> MyApp.Cache.get 1
nil
iex(2)> MyApp.Cache.put 1, 1, ttl: 10
:ok
iex(3)> MyApp.Cache.get 1
1
iex(4)> MyApp.Cache.put 2, 2
:ok
iex(5)> MyApp.Cache.delete 2
:ok
iex(6)> Process.sleep(20)
:ok
iex(7)> MyApp.Cache.get 1
nil
```

and you should see something like the following output:

```
[Telemetry.Metrics.ConsoleReporter] Got new event!
Event name: nebulex.cache.stats
All measurements: %{evictions: 2, expirations: 1, hits: 1, misses: 2, writes: 2}
All metadata: %{cache: MyApp.Cache}

Metric measurement: :hits (last_value)
With value: 1
Tag values: %{cache: MyApp.Cache}

Metric measurement: :misses (last_value)
With value: 2
Tag values: %{cache: MyApp.Cache}

Metric measurement: :writes (last_value)
With value: 2
Tag values: %{cache: MyApp.Cache}

Metric measurement: :evictions (last_value)
With value: 2
Tag values: %{cache: MyApp.Cache}

Metric measurement: :expirations (last_value)
With value: 1
Tag values: %{cache: MyApp.Cache}
```

## Adding other custom metrics

In the same way, you can, for instance, add another periodic measurement for
reporting the cache size.

Using our previous cache:

```elixir
defmodule MyApp.Cache do
  use Nebulex.Cache,
    otp_app: :my_app,
    adapter: Nebulex.Adapters.Local

  def dispatch_cache_size do
    :telemetry.execute(
      [:nebulex, :cache, :size],
      %{value: size()},
      %{cache: __MODULE__, node: node()}
    )
  end
end
```

And add it to the list of periodic measurements in our previously defined
supervisor:

```elixir
defp periodic_measurements do
  [
    {MyApp.Cache, :dispatch_stats, [[metadata: %{node: node()}]]},
    {MyApp.Cache, :dispatch_cache_size, []}
  ]
end
```

> **NOTE:** Notice we added in the metadata the node name so that we can use it
  in the tags of the metrics.

Metrics:

```elixir
defp metrics do
  [
    # Nebulex Stats Metrics
    last_value("nebulex.cache.stats.hits", tags: [:cache, :node]),
    last_value("nebulex.cache.stats.misses", tags: [:cache, :node]),
    last_value("nebulex.cache.stats.writes", tags: [:cache, :node]),
    last_value("nebulex.cache.stats.evictions", tags: [:cache, :node]),
    last_value("nebulex.cache.stats.expirations", tags: [:cache, :node]),

    # Nebulex custom Metrics
    last_value("nebulex.cache.size.value", tags: [:cache, :node]),

    # VM Metrics
    summary("vm.memory.total", unit: {:byte, :kilobyte}),
    summary("vm.total_run_queue_lengths.total"),
    summary("vm.total_run_queue_lengths.cpu"),
    summary("vm.total_run_queue_lengths.io")
  ]
end
```

If you start an IEx session like previously, you should see the new metric too:

```
[Telemetry.Metrics.ConsoleReporter] Got new event!
Event name: nebulex.cache.stats
All measurements: %{evictions: 0, expirations: 0, hits: 0, misses: 0, writes: 0}
All metadata: %{cache: MyApp.Cache, node: :nonode@nohost}

Metric measurement: :hits (last_value)
With value: 0
Tag values: %{cache: MyApp.Cache, node: :nonode@nohost}

Metric measurement: :misses (last_value)
With value: 0
Tag values: %{cache: MyApp.Cache, node: :nonode@nohost}

Metric measurement: :writes (last_value)
With value: 0
Tag values: %{cache: MyApp.Cache, node: :nonode@nohost}

Metric measurement: :evictions (last_value)
With value: 0
Tag values: %{cache: MyApp.Cache, node: :nonode@nohost}

Metric measurement: :expirations (last_value)
With value: 0
Tag values: %{cache: MyApp.Cache, node: :nonode@nohost}

[Telemetry.Metrics.ConsoleReporter] Got new event!
Event name: nebulex.cache.size
All measurements: %{value: 0}
All metadata: %{cache: MyApp.Cache, node: :nonode@nohost}

Metric measurement: :value (last_value)
With value: 0
Tag values: %{cache: MyApp.Cache, node: :nonode@nohost}
```

## Instrumenting Multi-level caches

When using the multi-level adapter the returned stats measurements may look
a bit different, because the multi-level adapter works as a wrapper for the
configured cache levels, so the returned measurements are grouped and
consolidated by level. For example, suppose you have the cache:

```elixir
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
```

Then, when you run `MyApp.Multilevel.stats()` you get something like:

```elixir
%Nebulex.Stats{
  measurements: %{
    l1: %{evictions: 0, expirations: 0, hits: 0, misses: 0, writes: 0},
    l2: %{evictions: 0, expirations: 0, hits: 0, misses: 0, writes: 0},
    l3: %{evictions: 0, expirations: 0, hits: 0, misses: 0, writes: 0}
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
```

As you can see, the measurements map has the stats grouped by level, every key
is an atom specifying the level and the value is a map with the stats and/or
measurements for that level. Based on that, you could define the Telemetry
metrics in this way:

```elixir
[
  # L1 metrics
  last_value("nebulex.cache.stats.l1.hits",
  event_name: "nebulex.cache.stats",
  measurement: &get_in(&1, [:l1, :hits]),
  tags: [:cache]
  ),
  last_value("nebulex.cache.stats.l1.misses",
    event_name: "nebulex.cache.stats",
    measurement: &get_in(&1, [:l1, :misses]),
    tags: [:cache]
  ),
  last_value("nebulex.cache.stats.l1.writes",
    event_name: "nebulex.cache.stats",
    measurement: &get_in(&1, [:l1, :writes]),
    tags: [:cache]
  ),
  last_value("nebulex.cache.stats.l1.evictions",
    event_name: "nebulex.cache.stats",
    measurement: &get_in(&1, [:l1, :evictions]),
    tags: [:cache]
  ),
  last_value("nebulex.cache.stats.l1.expirations",
    event_name: "nebulex.cache.stats",
    measurement: &get_in(&1, [:l1, :expirations]),
    tags: [:cache]
  ),

  # L2 metrics
  last_value("nebulex.cache.stats.l2.hits",
    event_name: "nebulex.cache.stats",
    measurement: &get_in(&1, [:l2, :hits]),
    tags: [:cache]
  ),
  ...
]
```

If what you need is the aggregated stats for all levels, you can always define
your own function to emit the Telemetry events. You just need to call
`MyApp.Multilevel.stats()` and then you add the logic to process the results
in the way you need. On the other hand, if you are using Datadog through the
StatsD reporter, you could do the aggregation directly in Datadog.
