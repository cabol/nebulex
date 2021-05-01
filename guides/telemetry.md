# Telemetry

This guide is not focused on explaining `:telemetry` itself, how it works, how
to configure it, and so on. Instead, we will show you how to instrument and
report on Cache Telemetry events in your application when using Nebulex.

For more information about `:telemetry`, you can check the
[documentation][telemetry], or the [Phoenix Telemetry][phx_telemetry]
guide is also recommended.

[telemetry]: https://github.com/beam-telemetry/telemetry
[phx_telemetry]: https://hexdocs.pm/phoenix/telemetry.html

## Telemetry Events

Many Elixir libraries (including Nebulex) are already using the `:telemetry`
package as a way to give users more insight into the behavior of their
applications, by emitting events at key moments in the application lifecycle.

### Nebulex built-in events

The following events are emitted by all Nebulex caches:

  * `[:nebulex, :cache, :init]` - it is dispatched whenever a cache starts.

    * Measurement: `%{system_time: System.monotonic_time()}`
    * Metadata: `%{cache: atom, opts: [term]}`

### Adapter-specific events

Nebulex currently suggests the adapters to dispatch the following Telemetry
events:

  * `[:my_app, :cache, :command, :start]` - Dispatched by the underlying cache
    adapter before an adapter callback is executed.

    * Measurement: `%{system_time: System.monotonic_time()}`
    * Metadata: `%{adapter_meta: map, function_name: atom, args: [term]}`

  * `[:my_app, :cache, :command, :stop]` - Dispatched by the underlying cache
    adapter after an adapter callback has been successfully executed.

    * Measurement: `%{duration: native_time}`
    * Metadata:

      ```elixir
      %{
        adapter_meta: map,
        function_name: atom,
        args: [term],
        result: term
      }
      ```

  * `[:my_app, :cache, :command, :exception]` - Dispatched by the underlying
    cache adapter when an exception is raised while the adapter callback is
    executed.

    * Measurement: `%{duration: native_time}`
    * Metadata:

      ```elixir
      %{
        adapter_meta: map,
        function_name: atom,
        args: [term],
        kind: :error | :exit | :throw,
        reason: term,
        stacktrace: term
      }
      ```

## Nebulex Metrics

Assuming you have defined the cache `MyApp.Cache` with the default
`:telemetry_prefix`, using `Telemetry.Metrics`, you can define a
counter metric, which counts how many cache commands were completed:

```elixir
Telemetry.Metrics.counter("my_app.cache.command.stop.duration")
```

or you could use a distribution metric to see how many commands were completed
in particular time buckets:

```elixir
Telemetry.Metrics.distribution(
  "my_app.cache.command.stop.duration",
  buckets: [100, 200, 300]
)
```

So far, these metrics are only helpful to be able to see just the total number
of executed cache commands. What if you wanted to see the average command
duration, minimum and maximum, or percentiles, but aggregated per command
or callback name? In this case, one could define a summary metric like so:

```elixir
Telemetry.Metrics.summary(
  "my_app.cache.command.stop.duration",
  unit: {:native, :millisecond},
  tags: [:function_name]
)
```

As it is described above in the **"Adapter-specific events"** section, the event
includes the invoked callback name into the metadata as `:function_name`, then
we can add it to the metric's tags.

### Extracting tag values from adapter's metadata

Let's add another metric for the command event, this time to group by cache and
function name (invoked adapter's callback name):

```elixir
Telemetry.Metrics.summary(
  "my_app.cache.command.stop.duration",
  unit: {:native, :millisecond},
  tags: [:cache, :function_name],
  tag_values: &Map.put(&1, :cache, &1.adapter_meta.cache)
)
```

We've introduced the `:tag_values` option here, because we need to perform a
transformation on the event metadata in order to get to the values we need.

## Cache Stats

Each adapter is responsible for providing stats by implementing
`Nebulex.Adapter.Stats` behaviour. However, Nebulex provides a simple default
implementation using [Erlang counters][erl_counters], which is used by
the built-in local adapter. The local adapter uses
`Nebulex.Telemetry.StatsHandler` to aggregate the stats and keep
them updated, therefore, it requires the Telemetry events are dispatched
by the adapter, otherwise, it won't work properly.

[erl_counters]: https://erlang.org/doc/man/counters.html

Furthermore, when the `:stats` option is enabled, we can use Telemetry for
emitting the current stat values.

First of all, make sure you have added `:telemetry`, `:telemetry_metrics`, and
`:telemetry_poller` packages as dependencies to your `mix.exs` file.

Let's define out cache module:

```elixir
defmodule MyApp.Cache do
  use Nebulex.Cache,
    otp_app: :my_app,
    adapter: Nebulex.Adapters.Local
end
```

Make sure the `:stats` option is set to `true`, for example in the
configuration:

```elixir
config :my_app, MyApp.Cache,
  stats: true,
  backend: :shards,
  gc_interval: :timer.hours(12),
  max_size: 1_000_000,
  gc_cleanup_min_timeout: :timer.seconds(10),
  gc_cleanup_max_timeout: :timer.minutes(10)
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
      last_value("my_app.cache.stats.hits", tags: [:cache]),
      last_value("my_app.cache.stats.misses", tags: [:cache]),
      last_value("my_app.cache.stats.writes", tags: [:cache]),
      last_value("my_app.cache.stats.updates", tags: [:cache]),
      last_value("my_app.cache.stats.evictions", tags: [:cache]),
      last_value("my_app.cache.stats.expirations", tags: [:cache])
    ]
  end

  defp periodic_measurements do
    [
      {MyApp.Cache, :dispatch_stats, []}
    ]
  end
end
```

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
iex(2)> MyApp.Cache.replace 1, 11
true
```

and you should see something like the following output:

```
[Telemetry.Metrics.ConsoleReporter] Got new event!
Event name: my_app.cache.stats
All measurements: %{evictions: 2, expirations: 1, hits: 1, misses: 2, updates: 1, writes: 2}
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

Metric measurement: :updates (last_value)
With value: 1
Tag values: %{cache: MyApp.Cache}

Metric measurement: :evictions (last_value)
With value: 2
Tag values: %{cache: MyApp.Cache}

Metric measurement: :expirations (last_value)
With value: 1
Tag values: %{cache: MyApp.Cache}
```

### Custom metrics

In the same way, for instance, you can add another periodic measurement for
reporting the cache size:

```elixir
defmodule MyApp.Cache do
  use Nebulex.Cache,
    otp_app: :my_app,
    adapter: Nebulex.Adapters.Local

  def dispatch_cache_size do
    :telemetry.execute(
      [:my_app, :cache, :size],
      %{value: size()},
      %{cache: __MODULE__, node: node()}
    )
  end
end
```

Now let's add a new periodic measurement to invoke `dispatch_cache_size()`
through `:telemetry_poller`:

```elixir
defp periodic_measurements do
  [
    {MyApp.Cache, :dispatch_stats, [[metadata: %{node: node()}]]},
    {MyApp.Cache, :dispatch_cache_size, []}
  ]
end
```

> Notice the node name was added to the metadata so we can use it in the
  metric's tags.

Metrics:

```elixir
defp metrics do
  [
    # Nebulex Stats Metrics
    last_value("my_app.cache.stats.hits", tags: [:cache, :node]),
    last_value("my_app.cache.stats.misses", tags: [:cache, :node]),
    last_value("my_app.cache.stats.writes", tags: [:cache, :node]),
    last_value("my_app.cache.stats.updates", tags: [:cache, :node]),
    last_value("my_app.cache.stats.evictions", tags: [:cache, :node]),
    last_value("my_app.cache.stats.expirations", tags: [:cache, :node]),

    # Nebulex custom Metrics
    last_value("my_app.cache.size.value", tags: [:cache, :node])
  ]
end
```

If you start an IEx session like previously, you should see the new metric too:

```
[Telemetry.Metrics.ConsoleReporter] Got new event!
Event name: my_app.cache.stats
All measurements: %{evictions: 0, expirations: 0, hits: 0, misses: 0, updates: 0, writes: 0}
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

Metric measurement: :updates (last_value)
With value: 0
Tag values: %{cache: MyApp.Cache, node: :nonode@nohost}

Metric measurement: :evictions (last_value)
With value: 0
Tag values: %{cache: MyApp.Cache, node: :nonode@nohost}

Metric measurement: :expirations (last_value)
With value: 0
Tag values: %{cache: MyApp.Cache, node: :nonode@nohost}

[Telemetry.Metrics.ConsoleReporter] Got new event!
Event name: my_app.cache.size
All measurements: %{value: 0}
All metadata: %{cache: MyApp.Cache, node: :nonode@nohost}

Metric measurement: :value (last_value)
With value: 0
Tag values: %{cache: MyApp.Cache, node: :nonode@nohost}
```

## Multi-level Cache Stats

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
    l1: %{evictions: 0, expirations: 0, hits: 0, misses: 0, updates: 0, writes: 0},
    l2: %{evictions: 0, expirations: 0, hits: 0, misses: 0, updates: 0, writes: 0},
    l3: %{evictions: 0, expirations: 0, hits: 0, misses: 0, updates: 0, writes: 0}
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
  last_value("my_app.cache.stats.l1.hits",
    event_name: "my_app.cache.stats",
    measurement: &get_in(&1, [:l1, :hits]),
    tags: [:cache]
  ),
  last_value("my_app.cache.stats.l1.misses",
    event_name: "my_app.cache.stats",
    measurement: &get_in(&1, [:l1, :misses]),
    tags: [:cache]
  ),
  last_value("my_app.cache.stats.l1.writes",
    event_name: "my_app.cache.stats",
    measurement: &get_in(&1, [:l1, :writes]),
    tags: [:cache]
  ),
  last_value("my_app.cache.stats.l1.updates",
    event_name: "my_app.cache.stats",
    measurement: &get_in(&1, [:l1, :updates]),
    tags: [:cache]
  ),
  last_value("my_app.cache.stats.l1.evictions",
    event_name: "my_app.cache.stats",
    measurement: &get_in(&1, [:l1, :evictions]),
    tags: [:cache]
  ),
  last_value("my_app.cache.stats.l1.expirations",
    event_name: "my_app.cache.stats",
    measurement: &get_in(&1, [:l1, :expirations]),
    tags: [:cache]
  ),

  # L2 metrics
  last_value("my_app.cache.stats.l2.hits",
    event_name: "my_app.cache.stats",
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
