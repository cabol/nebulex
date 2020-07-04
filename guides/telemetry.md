# Telemetry

This guide aims to show you how to instrument and report on `:telemetry` events
in your application for cache statistics.

This guide is not focused on explaining `:telemetry`, how it works, configure
it, and so on. Instead, it is focused on how we can use `:telemetry` for
reporting cache stats. For more information about `:telemetry` you can check
the docs, or the [Phoenix Telemetry](https://hexdocs.pm/phoenix/telemetry.html)
guide is also recommended.

## Instrumenting Nebulex Caches

The stats support is something each adapter is responsible for. However,
Nebulex built-in adapters support the stats suggested and defined by
`Nebulex.Cache.Stats`. Besides, when the `:stats` option is enabled,
we can use Telemetry for emitting the current stat values.

First of all, let's configure the dependencies adding `:telemetry_metrics`
and `:telemetry_poller` packages:

```elixir
def deps do
  [
    {:nebulex, "~> 2.0"},
    {:shards, "~> 0.6"},   #=> For using :shards as backend
    {:decorator, "~> 1.3"} #=> For using Caching Annotations
    {:telemetry_metrics, "~> 0.5"},
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

  # Use stats helpers
  use Nebulex.Cache.Stats
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
      {:telemetry_poller, measurements: periodic_measurements(), period: 10_000}

      # For example, we use the console reporter, but you can change it.
      # See `:telemetry_metrics` for for information.
      {Telemetry.Metrics.ConsoleReporter, metrics: metrics()}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  defp metrics do
    [
      # Nebulex Stats Metrics
      last_value("my_app.cache.stats.hits"),
      last_value("my_app.cache.stats.misses"),
      last_value("my_app.cache.stats.writes"),
      last_value("my_app.cache.stats.evictions"),
      last_value("my_app.cache.stats.expirations"),

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

Make sure to replace `MyApp` by your actual application name.

Then add to your main application's supervision tree
(usually in `lib/my_app/application.ex`):

```elixir
children = [
  MyApp.Cache,
  MyAppWeb.Telemetry,
  ...
]
```

Now start an IEx session and call the server:

```
iex(1)> MyApp.Cache.put 1, 1
```

and you should see something like the following output:

```
[Telemetry.Metrics.ConsoleReporter] Got new event!
Event name: my_app.cache.stats
All measurements: %{evictions: 0, expirations: 0, hits: 0, misses: 0, writes: 1}
All metadata: %{cache: MyApp.Cache}

Metric measurement: :hits (last_value)
With value: 0
Tag values: %{}

Metric measurement: :misses (last_value)
With value: 0
Tag values: %{}

Metric measurement: :writes (last_value)
With value: 1
Tag values: %{}

Metric measurement: :evictions (last_value)
With value: 0
Tag values: %{}

Metric measurement: :expirations (last_value)
With value: 0
Tag values: %{}
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

  # Use stats helpers
  use Nebulex.Cache.Stats

  def dispatch_cache_size do
    :telemetry.execute(
      [:my_app, :cache, :size],
      %{value: size()},
      %{cache: __MODULE__}
    )
  end
end
```

And add it to the list of periodic measurements in our previously defined
supervisor:

```elixir
defp periodic_measurements do
  [
    {MyApp.Cache, :dispatch_stats, []},
    {MyApp.Cache, :dispatch_cache_size, []}
  ]
end
```

Metrics:

```elixir
defp metrics do
  [
    # Nebulex Stats Metrics
    last_value("my_app.cache.stats.hits"),
    last_value("my_app.cache.stats.misses"),
    last_value("my_app.cache.stats.writes"),
    last_value("my_app.cache.stats.evictions"),
    last_value("my_app.cache.stats.expirations"),

    # Nebulex custom Metrics
    last_value("my_app.cache.size.value"),

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
Event name: my_app.cache.size
All measurements: %{value: 0}
All metadata: %{cache: MyApp.Cache}

Metric measurement: :value (last_value)
With value: 0
Tag values: %{}
```
