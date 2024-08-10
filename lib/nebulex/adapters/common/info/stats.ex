defmodule Nebulex.Adapters.Common.Info.Stats do
  @moduledoc """
  Stats implementation using [Erlang counters][erl_counters].

  Adapters are directly responsible for implementing the `Nebulex.Adapter.Info`
  behaviour and adding an info spec for stats. However, this module provides a
  simple implementation for stats using [Erlang counters][erl_counters].

  An info specification `stats` is added to the info data, which is a map
  with the following keys or measurements:

    * `:hits` - The requested data is successfully retrieved from the cache.

    * `:misses` - When a system or application makes a request to retrieve
      data from a cache, but that specific data is not currently in cache
      memory. A cache miss occurs either because the data was never placed
      in the cache, or because the data was removed (“evicted”) from the
      cache by either the caching system itself or an external application
      that specifically made that eviction request.

    * `:evictions` - Eviction by the caching system itself occurs when
      space needs to be freed up to add new data to the cache, or if
      the time-to-live policy on the data expired.

    * `:expirations` - When the time-to-live policy on the data expired.

    * `:updates` - When existing data is successfully updated.

    * `:writes` - When data is inserted or overwritten.

    * `:deletions` - The data was intentionally removed by either the
      caching system or an external application that specifically made
      that deletion request.

  See the `Nebulex.Adapters.Local` adapter and `Nebulex.Adapters.Common.Info`
  for more information about the usage.

  [erl_counters]: https://erlang.org/doc/man/counters.html
  """

  alias __MODULE__.TelemetryHandler
  alias Nebulex.Telemetry

  ## Types & Constants

  @typedoc "The stat type"
  @type stat() ::
          :hits
          | :misses
          | :evictions
          | :expirations
          | :writes
          | :updates
          | :deletions

  @typedoc "Stats type"
  @type stats() :: %{required(stat()) => integer()}

  # Supported stats
  @stats [
    :hits,
    :misses,
    :evictions,
    :expirations,
    :writes,
    :updates,
    :deletions
  ]

  ## API

  @doc """
  Returns the Erlang's counter to be used by the adapter for keeping the cache
  stats. It also initiates the Telemetry handler for handling and/or updating
  the cache stats in runtime under the hood.

  Any adapter using `Nebulex.Adapters.Common.Info` implementation must call
  this init function in the `c:Nebulex.Adapter.init/1` callback and include
  the returned counter within the adapter metadata under the key
  `:stats_counter`. See the `Nebulex.Adapters.Nil` for example.

  ## Example

      Nebulex.Adapters.Common.Info.Stats.init([:telemetry, :prefix])

  """
  @spec init(telemetry_prefix :: [atom()]) :: :counters.counters_ref()
  def init(telemetry_prefix) do
    stats_counter = :counters.new(7, [:write_concurrency])

    _ =
      Telemetry.attach_many(
        stats_counter,
        [telemetry_prefix ++ [:command, :stop]],
        &TelemetryHandler.handle_event/4,
        stats_counter
      )

    stats_counter
  end

  @doc """
  Increments counter(s) for the given stat(s) by `incr`.

  ## Examples

      Nebulex.Adapters.Common.Info.Stats.incr(stats_counter, :hits)

      Nebulex.Adapters.Common.Info.Stats.incr(stats_counter, :writes, 10)

      Nebulex.Adapters.Common.Info.Stats.incr(stats_counter, [:misses, :deletions])

  """
  @spec incr(:counters.counters_ref(), atom() | [atom()], integer()) :: :ok
  def incr(counter, stats, incr \\ 1)

  def incr(ref, :hits, incr), do: :counters.add(ref, 1, incr)
  def incr(ref, :misses, incr), do: :counters.add(ref, 2, incr)
  def incr(ref, :evictions, incr), do: :counters.add(ref, 3, incr)
  def incr(ref, :expirations, incr), do: :counters.add(ref, 4, incr)
  def incr(ref, :writes, incr), do: :counters.add(ref, 5, incr)
  def incr(ref, :updates, incr), do: :counters.add(ref, 6, incr)
  def incr(ref, :deletions, incr), do: :counters.add(ref, 7, incr)
  def incr(ref, l, incr) when is_list(l), do: Enum.each(l, &incr(ref, &1, incr))

  @doc """
  Returns a map with all counters/stats count.

  ## Examples

      Nebulex.Adapters.Common.Info.Stats.count(stats_counter)

  """
  @spec count(:counters.counters_ref()) :: stats()
  def count(ref) do
    for s <- @stats, into: %{}, do: {s, count(ref, s)}
  end

  @doc """
  Returns the current count for the stats counter given by `stat`.

  ## Examples

      Nebulex.Adapters.Common.Info.Stats.count(stats_counter, :hits)

  """
  @spec count(:counters.counters_ref(), stat()) :: integer()
  def count(ref, stat)

  def count(ref, :hits), do: :counters.get(ref, 1)
  def count(ref, :misses), do: :counters.get(ref, 2)
  def count(ref, :evictions), do: :counters.get(ref, 3)
  def count(ref, :expirations), do: :counters.get(ref, 4)
  def count(ref, :writes), do: :counters.get(ref, 5)
  def count(ref, :updates), do: :counters.get(ref, 6)
  def count(ref, :deletions), do: :counters.get(ref, 7)

  @doc """
  Convenience function for returning a map with all stats set to `0`.
  """
  @spec new() :: stats()
  def new do
    %{
      deletions: 0,
      evictions: 0,
      expirations: 0,
      hits: 0,
      misses: 0,
      updates: 0,
      writes: 0
    }
  end
end
