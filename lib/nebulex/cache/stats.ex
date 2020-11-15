defmodule Nebulex.Cache.Stats do
  @moduledoc """
  This module defines the supported built-in stats.

  By default, each adapter is responsible for providing stats support.
  However, Nebulex suggests supporting the built-in stats described
  in this module, which are also supported by the built-in adapters.

  ## Usage

  First of all, we define a cache:

      defmodule MyApp.Cache do
        use Nebulex.Cache,
          otp_app: :nebulex,
          adapter: Nebulex.Adapters.Local
      end

  Then we configure it enabling the stats, like so:

      config :my_app, MyApp.Cache,
        stats: true,
        gc_interval: 86_400_000, #=> 1 day
        max_size: 200_000,
        gc_cleanup_min_timeout: 10_000,
        gc_cleanup_max_timeout: 900_000

  > Remember to add the cache on your application's supervision tree.

  Since we are using a built-in adapter and the stats have been enabled
  (`stats: true`), the stat counters will be automatically fed by the
  adapter.

  You can ask for the current stats values at any time by calling:

      Nebulex.Cache.Stats.info(MyApp.Cache)

  ## Using stats helpers

  You can inject the stats helpers in the cache like this:

      defmodule MyApp.Cache do
        use Nebulex.Cache,
          otp_app: :nebulex,
          adapter: Nebulex.Adapters.Local

        # Use stats helpers
        use Nebulex.Cache.Stats
      end

  ### Retrieving stats info

      MyApp.Cache.stats_info()

  By calling this injected helper, the function `Nebulex.Cache.Stats.info/1`
  is called under-the-hood, but the cache name is resolved automatically.

  ### Dispatching telemetry events

      MyApp.Cache.dispatch_stats()

      MyApp.Cache.dispatch_stats(event_prefix: [:my_cache, :stats])

  By calling this injected helper, the function `Nebulex.Cache.Stats.dispatch/2`
  is called under-the-hood, but the cache name is resolved automatically.

  ## Telemetry events

  Integrating telemetry is very easy since with the helper function
  `MyApp.Cache.dispatch_stats/1` (via the `__using__` macro) described
  previously you can emit telemetry events with the current stats at any time.
  What we need to resolve is, how to make it in such a way that every X period
  of time the stats are emitted automatically.

  To do so, we can use `:telemetry_poller` and define a custom measurement:

      :telemetry_poller.start_link(
        measurements: [
          {MyApp.Cache, :dispatch_stats, []},
        ],
        # configure sampling period - default is :timer.seconds(5)
        period: :timer.seconds(10),
        name: :my_cache_stats_poller
      )

  Or you can also start the `:telemetry_poller` process along with your
  application supervision tree, like so:

      def start(_type, _args) do
        my_cache_stats_poller_opts = [
          measurements: [
            {MyApp.Cache, :dispatch_stats, []},
          ],
          period: :timer.seconds(10),
          name: :my_cache_stats_poller
        ]

        children = [
          {MyApp.Cache, []},
          {:telemetry_poller, my_cache_stats_poller_opts}
        ]

        opts = [strategy: :one_for_one, name: MyApp.Supervisor]
        Supervisor.start_link(children, opts)
      end

  See [Nebulex Telemetry Guide](http://hexdocs.pm/nebulex/telemetry.html).
  """

  # Stats Struct
  defstruct hits: 0, misses: 0, writes: 0, evictions: 0, expirations: 0

  @type t :: %__MODULE__{
          hits: non_neg_integer,
          misses: non_neg_integer,
          writes: non_neg_integer,
          evictions: non_neg_integer,
          expirations: non_neg_integer
        }

  @type stat :: :hits | :misses | :writes | :evictions | :expirations

  @doc false
  defmacro __using__(_opts) do
    quote do
      alias Nebulex.Cache.Stats

      @doc false
      def stats_info do
        Stats.info(get_dynamic_cache())
      end

      if Code.ensure_loaded?(:telemetry) do
        @doc false
        def dispatch_stats(opts \\ []) do
          Stats.dispatch(get_dynamic_cache(), opts)
        end
      end
    end
  end

  import Nebulex.Helpers

  alias Nebulex.Adapter

  ## API

  @doc """
  Initializes the Erlang's counter to be used for the calling Cache and feed
  the stat values; see the module documentation for more information about
  the supported stats.

  Returns `nil` is the option `:stats` is set to `false` or it is not set at
  all; the stats will be skipped.

  ## Example

      Nebulex.Cache.Stats.init(opts)

  > **NOTE:** This function is normally called by the adapter in
    case it supports the Nebulex suggested stats; the adapter
    should feed `Nebulex.Cache.Stats.t()` counters.

  See built-in adapters for more information about the usage.
  """
  @spec init(Keyword.t()) :: :counters.counters_ref() | nil
  def init(opts) do
    case get_option(opts, :stats, &is_boolean(&1), false) do
      true -> :counters.new(5, [:write_concurrency])
      false -> nil
    end
  end

  @doc """
  Increments the `counter`'s stat `stat` by the given `incr` value.

  ## Examples

      Nebulex.Cache.Stats.incr(stat_counter, :hits)

      Nebulex.Cache.Stats.incr(stat_counter, :writes, 10)

  > **NOTE:** This function is normally called by the adapter in
    case it supports the Nebulex suggested stats; the adapter
    should feed `Nebulex.Cache.Stats.t()` counters.

  See built-in adapters for more information about the usage.
  """
  @spec incr(:counters.counters_ref() | nil, stat, integer) :: :ok
  def incr(counter, stat, incr \\ 1)

  def incr(nil, _stat, _incr), do: :ok
  def incr(ref, :hits, incr), do: :counters.add(ref, 1, incr)
  def incr(ref, :misses, incr), do: :counters.add(ref, 2, incr)
  def incr(ref, :writes, incr), do: :counters.add(ref, 3, incr)
  def incr(ref, :evictions, incr), do: :counters.add(ref, 4, incr)
  def incr(ref, :expirations, incr), do: :counters.add(ref, 5, incr)

  @doc """
  Returns the struct `Nebulex.Cache.Stats` with the current stats values for
  the given cache name or counter reference. Normally, the cache name is
  passed so that the counter reference is retrieved and handled internally.

  Returns `nil` if the stats are disabled or if the adapter doesn't support
  this feature.

  ## Example

      iex> Nebulex.Cache.Stats.info(MyCache)
      %Nebulex.Cache.Stats{
        evictions: 0,
        expirations: 0,
        hits: 0,
        misses: 0,
        writes: 0
      }
  """
  @spec info(:counters.counters_ref() | atom | nil) :: t | nil
  def info(nil), do: nil

  def info(name) when is_atom(name) do
    Adapter.with_meta(name, fn _adapter, meta ->
      meta
      |> Map.get(:stat_counter)
      |> info()
    end)
  end

  def info(ref) do
    %__MODULE__{
      hits: :counters.get(ref, 1),
      misses: :counters.get(ref, 2),
      writes: :counters.get(ref, 3),
      evictions: :counters.get(ref, 4),
      expirations: :counters.get(ref, 5)
    }
  end

  if Code.ensure_loaded?(:telemetry) do
    @doc """
    Emits a telemetry event when called with the current stats count.

    The `:measurements` map will include the current count for each stat:

      * `:hits` - Current **hits** count.
      * `:misses` - Current **misses** count.
      * `:writes` - Current **writes** count.
      * `:evictions` - Current **evictions** count.
      * `:expirations` - Current **expirations** count.

    The telemetry `:metadata` map will include the following fields:

      * `:cache` - The cache module, or the name (if an explicit name has been
        given to the cache).

    Additionally, you can add your own metadata fields by given the option
    `:metadata`.

    ## Options

      * `:event_prefix` – The prefix of the telemetry event.
        Defaults to `[:nebulex, :cache]`.

      * `:metadata` – A map with additional metadata fields. Defaults to `%{}`.

    ## Examples

        iex> Nebulex.Cache.Stats.dispatch(MyCache)
        :ok

        iex> Nebulex.Cache.Stats.dispatch(
        ...>   MyCache,
        ...>   event_prefix: [:my_cache],
        ...>   metadata: %{tag: "tag1"}
        ...> )
        :ok
    """
    @spec dispatch(atom, Keyword.t()) :: :ok
    def dispatch(cache_or_name, opts \\ []) do
      if info = __MODULE__.info(cache_or_name) do
        :telemetry.execute(
          Keyword.get(opts, :event_prefix, [:nebulex, :cache]) ++ [:stats],
          Map.from_struct(info),
          opts |> Keyword.get(:metadata, %{}) |> Map.put(:cache, cache_or_name)
        )
      else
        :ok
      end
    end
  end
end
