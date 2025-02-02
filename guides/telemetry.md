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

See ["Telemetry Events"][nbx_telemetry_events] documentation for more
information about the emitted events, their measurements, and metadata.

[nbx_telemetry_events]: https://hexdocs.pm/nebulex/Nebulex.Cache.html#module-telemetry-events

## Nebulex Metrics

Assuming you have defined the cache `MyApp.Cache` with the default
`:telemetry_prefix`, using `Telemetry.Metrics`, you can define a
counter metric, which counts how many cache commands were completed:

```elixir
Telemetry.Metrics.counter("nebulex.cache.command.stop.duration")
```

or you could use a distribution metric to see how many commands were completed
in particular time buckets:

```elixir
Telemetry.Metrics.distribution(
  "nebulex.cache.command.stop.duration",
  buckets: [100, 200, 300]
)
```

So far, these metrics are only helpful to be able to see just the total number
of executed cache commands. What if you wanted to see the average command
duration, minimum and maximum, or percentiles, but aggregated per command
or callback name? In this case, one could define a summary metric like so:

```elixir
Telemetry.Metrics.summary(
  "nebulex.cache.command.stop.duration",
  unit: {:native, :millisecond},
  tags: [:command]
)
```

### Extracting tag values from adapter's metadata

Let's add another metric for the command event, this time to group by
**command**, **cache**, and **name** (in case of dynamic caches):

```elixir
Telemetry.Metrics.summary(
  "nebulex.cache.command.stop.duration",
  unit: {:native, :millisecond},
  tags: [:command, :cache, :name],
  tag_values:
    &%{
      cache: &1.adapter_meta.cache,
      name: &1.adapter_meta.name,
      command: &1.command
    }
)
```

We've introduced the `:tag_values` option here, because we need to perform a
transformation on the event metadata in order to get to the values we need.
