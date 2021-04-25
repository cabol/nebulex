defmodule Nebulex.Adapter.Stats do
  @moduledoc """
  Specifies the stats API required from adapters.

  Each adapter is responsible for providing support for stats by implementing
  this behaviour. However, this module brings with a default implementation
  using [Erlang counters][https://erlang.org/doc/man/counters.html], with all
  callbacks overridable, which is supported by the built-in adapters.

  See `Nebulex.Adapters.Local` for more information about how this can be used
  from the adapter, and also [Nebulex Telemetry Guide][telemetry_guide] to learn
  how to use the Cache with Telemetry.

  [telemetry_guide]: http://hexdocs.pm/nebulex/telemetry.html
  """

  @doc """
  Returns `Nebulex.Stats.t()` with the current stats values.

  If the stats are disabled for the cache, then `nil` is returned.

  The adapter may also include additional custom measurements,
  as well as metadata.

  See `c:Nebulex.Cache.stats/0`.
  """
  @callback stats(Nebulex.Adapter.adapter_meta()) :: Nebulex.Stats.t() | nil

  @doc false
  defmacro __using__(_opts) do
    quote do
      @behaviour Nebulex.Adapter.Stats

      @impl true
      def stats(adapter_meta) do
        if counter_ref = adapter_meta[:stats_counter] do
          %Nebulex.Stats{
            measurements: %{
              hits: :counters.get(counter_ref, 1),
              misses: :counters.get(counter_ref, 2),
              writes: :counters.get(counter_ref, 3),
              updates: :counters.get(counter_ref, 4),
              evictions: :counters.get(counter_ref, 5),
              expirations: :counters.get(counter_ref, 6)
            },
            metadata: %{
              cache: adapter_meta[:name] || adapter_meta[:cache]
            }
          }
        end
      end

      defoverridable stats: 1
    end
  end

  import Nebulex.Helpers

  @doc """
  Initializes the Erlang's counter to be used by the adapter. See the module
  documentation for more information about the stats default implementation.

  Returns `nil` is the option `:stats` is set to `false` or it is not set at
  all; the stats will be skipped.

  ## Example

      Nebulex.Adapter.Stats.init(opts)

  > **NOTE:** This function is usually called by the adapter in case it uses
    the default implementation; the adapter should feed `Nebulex.Stats.t()`
    counters.

  See adapters documentation for more information about stats implementation.
  """
  @spec init(Keyword.t()) :: :counters.counters_ref() | nil
  def init(opts) do
    case get_boolean_option(opts, :stats, false) do
      true -> :counters.new(6, [:write_concurrency])
      false -> nil
    end
  end

  @doc """
  Increments the `counter`'s `stat_name` by the given `incr` value.

  ## Examples

      Nebulex.Adapter.Stats.incr(stats_counter, :hits)

      Nebulex.Adapter.Stats.incr(stats_counter, :writes, 10)

  > **NOTE:** This function is usually called by the adapter in case it uses
    the default implementation; the adapter should feed `Nebulex.Stats.t()`
    counters.

  See adapters documentation for more information about stats implementation.
  """
  @spec incr(:counters.counters_ref() | nil, atom, integer) :: :ok
  def incr(counter, stat_name, incr \\ 1)

  def incr(nil, _stat, _incr), do: :ok
  def incr(ref, :hits, incr), do: :counters.add(ref, 1, incr)
  def incr(ref, :misses, incr), do: :counters.add(ref, 2, incr)
  def incr(ref, :writes, incr), do: :counters.add(ref, 3, incr)
  def incr(ref, :updates, incr), do: :counters.add(ref, 4, incr)
  def incr(ref, :evictions, incr), do: :counters.add(ref, 5, incr)
  def incr(ref, :expirations, incr), do: :counters.add(ref, 6, incr)
end
