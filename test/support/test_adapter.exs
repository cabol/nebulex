defmodule Nebulex.TestAdapter do
  @moduledoc """
  Adapter for testing purposes.
  """

  defmodule Entry do
    @moduledoc false

    defstruct value: nil, touched: nil, exp: nil

    alias Nebulex.Time

    @doc false
    def new(value, ttl \\ :infinity, touched \\ Time.now()) do
      %__MODULE__{
        value: value,
        touched: touched,
        exp: exp(ttl)
      }
    end

    @doc false
    def exp(now \\ Time.now(), ttl)

    def exp(_now, :infinity), do: :infinity
    def exp(now, ttl), do: now + ttl
  end

  # Provide Cache Implementation
  @behaviour Nebulex.Adapter
  @behaviour Nebulex.Adapter.Entry
  @behaviour Nebulex.Adapter.Queryable

  # Inherit default transaction implementation
  use Nebulex.Adapter.Transaction

  # Inherit default persistence implementation
  use Nebulex.Adapter.Persistence

  # Inherit default stats implementation
  use Nebulex.Adapter.Stats

  use Nebulex.Cache.Options

  import Nebulex.Adapter, only: [defspan: 2]
  import Nebulex.Helpers

  alias Nebulex.Adapter.Stats
  alias __MODULE__.{Entry, KV}
  alias Nebulex.Time

  ## Nebulex.Adapter

  @impl true
  defmacro __before_compile__(_env), do: :ok

  @impl true
  def init(opts) do
    # Validate options
    opts = validate!(opts)

    # Required options
    telemetry = Keyword.fetch!(opts, :telemetry)
    telemetry_prefix = Keyword.fetch!(opts, :telemetry_prefix)

    # Init stats_counter
    stats_counter = Stats.init(opts)

    # Adapter meta
    metadata = %{
      telemetry: telemetry,
      telemetry_prefix: telemetry_prefix,
      stats_counter: stats_counter,
      started_at: DateTime.utc_now()
    }

    # KV server
    child_spec = Supervisor.child_spec({KV, [adapter_meta: metadata] ++ opts}, id: KV)

    {:ok, child_spec, metadata}
  end

  ## Nebulex.Adapter.Entry

  @impl true
  defspan fetch(adapter_meta, key, _opts) do
    with {:ok, %Entry{value: value}} <- do_fetch(adapter_meta, key) do
      {:ok, value}
    end
  end

  defp do_fetch(_adapter_meta, {:eval, fun}) do
    fun.()
  end

  defp do_fetch(adapter_meta, key) do
    adapter_meta.pid
    |> GenServer.call({:fetch, key})
    |> validate_ttl(key, adapter_meta)
  end

  defp validate_ttl({:ok, %Entry{exp: :infinity} = entry}, _key, _adapter_meta) do
    {:ok, entry}
  end

  defp validate_ttl(
         {:ok, %Entry{exp: exp} = entry},
         key,
         %{
           name: name,
           cache: cache,
           pid: pid
         } = adapter_meta
       )
       when is_integer(exp) do
    if Time.now() >= exp do
      :ok = delete(adapter_meta, key, [])

      wrap_error Nebulex.KeyError, key: key, cache: name || {cache, pid}, reason: :expired
    else
      {:ok, entry}
    end
  end

  defp validate_ttl(:error, key, %{name: name, cache: cache, pid: pid}) do
    wrap_error Nebulex.KeyError, key: key, cache: name || {cache, pid}, reason: :not_found
  end

  @impl true
  defspan get_all(adapter_meta, keys, opts) do
    adapter_meta = %{adapter_meta | telemetry: Map.get(adapter_meta, :in_span?, false)}

    keys
    |> Enum.reduce(%{}, fn key, acc ->
      case fetch(adapter_meta, key, opts) do
        {:ok, val} -> Map.put(acc, key, val)
        {:error, _} -> acc
      end
    end)
    |> wrap_ok()
  end

  @impl true
  defspan put(adapter_meta, key, value, ttl, on_write, _opts) do
    do_put(adapter_meta.pid, key, Entry.new(value, ttl), on_write)
  end

  defp do_put(pid, key, entry, :put) do
    GenServer.call(pid, {:put, key, entry})
  end

  defp do_put(pid, key, entry, :put_new) do
    GenServer.call(pid, {:put_new, key, entry})
  end

  defp do_put(pid, key, entry, :replace) do
    GenServer.call(pid, {:replace, key, entry})
  end

  @impl true
  defspan put_all(adapter_meta, entries, ttl, on_write, _opts) do
    entries = for {key, value} <- entries, into: %{}, do: {key, Entry.new(value, ttl)}

    do_put_all(adapter_meta.pid, entries, on_write)
  end

  defp do_put_all(pid, entries, :put) do
    GenServer.call(pid, {:put_all, entries})
  end

  defp do_put_all(pid, entries, :put_new) do
    GenServer.call(pid, {:put_new_all, entries})
  end

  @impl true
  defspan delete(adapter_meta, key, _opts) do
    GenServer.call(adapter_meta.pid, {:delete, key})
  end

  @impl true
  defspan take(adapter_meta, key, _opts) do
    with {:ok, %Entry{value: value}} <-
           adapter_meta.pid
           |> GenServer.call({:pop, key})
           |> validate_ttl(key, adapter_meta) do
      {:ok, value}
    end
  end

  @impl true
  defspan update_counter(adapter_meta, key, amount, ttl, default, _opts) do
    _ = do_fetch(adapter_meta, key)

    GenServer.call(
      adapter_meta.pid,
      {:update_counter, key, amount, Entry.new(default + amount, ttl)}
    )
  end

  @impl true
  def has_key?(adapter_meta, key, _opts) do
    case fetch(adapter_meta, key, []) do
      {:ok, _} -> {:ok, true}
      {:error, _} -> {:ok, false}
    end
  end

  @impl true
  defspan ttl(adapter_meta, key, _opts) do
    with {:ok, entry} <- do_fetch(adapter_meta, key) do
      {:ok, entry_ttl(entry)}
    end
  end

  @impl true
  defspan expire(adapter_meta, key, ttl, _opts) do
    GenServer.call(adapter_meta.pid, {:expire, key, ttl})
  end

  @impl true
  defspan touch(adapter_meta, key, _opts) do
    GenServer.call(adapter_meta.pid, {:touch, key})
  end

  ## Nebulex.Adapter.Queryable

  @impl true
  defspan execute(adapter_meta, operation, query, opts) do
    GenServer.call(adapter_meta.pid, {:q, operation, query, opts})
  end

  @impl true
  defspan stream(adapter_meta, query, opts) do
    GenServer.call(adapter_meta.pid, {:q, :stream, query, opts})
  end

  ## Nebulex.Adapter.Persistence

  @impl true
  defspan dump(adapter_meta, path, opts) do
    super(adapter_meta, path, opts)
  end

  @impl true
  defspan load(adapter_meta, path, opts) do
    super(adapter_meta, path, opts)
  end

  ## Nebulex.Adapter.Transaction

  @impl true
  defspan transaction(adapter_meta, opts, fun) do
    super(adapter_meta, opts, fun)
  end

  @impl true
  defspan in_transaction?(adapter_meta) do
    super(adapter_meta)
  end

  ## Nebulex.Adapter.Stats

  @impl true
  defspan stats(adapter_meta) do
    with {:ok, %Nebulex.Stats{} = stats} <- super(adapter_meta) do
      {:ok, %{stats | metadata: Map.put(stats.metadata, :started_at, adapter_meta.started_at)}}
    end
  end

  ## Helpers

  defp entry_ttl(%Entry{exp: :infinity}), do: :infinity
  defp entry_ttl(%Entry{exp: exp}), do: exp - Time.now()
end

defmodule Nebulex.TestAdapter.KV do
  @moduledoc false

  use GenServer

  import Nebulex.Helpers, only: [wrap_error: 2]

  alias Nebulex.Telemetry
  alias Nebulex.Telemetry.StatsHandler
  alias Nebulex.TestAdapter.Entry
  alias Nebulex.Time

  ## Internals

  # Internal state
  defstruct map: nil, telemetry_prefix: nil, stats_counter: nil

  ## API

  @spec start_link(keyword) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  ## GenServer callbacks

  @impl true
  def init(opts) do
    state = struct(__MODULE__, Keyword.get(opts, :adapter_meta, %{}))

    {:ok, %{state | map: %{}}, {:continue, :attach_stats_handler}}
  end

  @impl true
  def handle_continue(message, state)

  def handle_continue(:attach_stats_handler, %__MODULE__{stats_counter: nil} = state) do
    {:noreply, state}
  end

  def handle_continue(:attach_stats_handler, %__MODULE__{stats_counter: stats_counter} = state) do
    _ =
      Telemetry.attach_many(
        stats_counter,
        [state.telemetry_prefix ++ [:command, :stop]],
        &StatsHandler.handle_event/4,
        stats_counter
      )

    {:noreply, state}
  end

  @impl true
  def handle_call(request, from, state)

  def handle_call({:fetch, key}, _from, %__MODULE__{map: map} = state) do
    {:reply, Map.fetch(map, key), state}
  end

  def handle_call({:put, key, value}, _from, %__MODULE__{map: map} = state) do
    {:reply, {:ok, true}, %{state | map: Map.put(map, key, value)}}
  end

  def handle_call({:put_new, key, value}, _from, %__MODULE__{map: map} = state) do
    case Map.has_key?(map, key) do
      true ->
        {:reply, {:ok, false}, state}

      false ->
        {:reply, {:ok, true}, %{state | map: Map.put_new(map, key, value)}}
    end
  end

  def handle_call({:replace, key, value}, _from, %__MODULE__{map: map} = state) do
    case Map.has_key?(map, key) do
      true ->
        {:reply, {:ok, true}, %{state | map: Map.replace(map, key, value)}}

      false ->
        {:reply, {:ok, false}, state}
    end
  end

  def handle_call({:put_all, entries}, _from, %__MODULE__{map: map} = state) do
    {:reply, {:ok, true}, %{state | map: Map.merge(map, entries)}}
  end

  def handle_call({:put_new_all, entries}, _from, %__MODULE__{map: map} = state) do
    case Enum.any?(map, fn {k, _} -> Map.has_key?(entries, k) end) do
      true ->
        {:reply, {:ok, false}, state}

      false ->
        {:reply, {:ok, true}, %{state | map: Map.merge(map, entries)}}
    end
  end

  def handle_call({:delete, key}, _from, %__MODULE__{map: map} = state) do
    {:reply, :ok, %{state | map: Map.delete(map, key)}}
  end

  def handle_call({:pop, key}, _from, %__MODULE__{map: map} = state) do
    ref = make_ref()

    case Map.pop(map, key, ref) do
      {^ref, _map} ->
        {:reply, :error, state}

      {value, map} ->
        {:reply, {:ok, value}, %{state | map: map}}
    end
  end

  def handle_call({:update_counter, key, amount, default}, _from, %__MODULE__{map: map} = state) do
    map = Map.update(map, key, default, &%{&1 | value: &1.value + amount})
    counter = Map.fetch!(map, key)

    {:reply, {:ok, counter.value}, %{state | map: map}}
  end

  def handle_call({:expire, key, ttl}, _from, %__MODULE__{map: map} = state) do
    case Map.has_key?(map, key) do
      true ->
        {:reply, {:ok, true}, %{state | map: Map.update!(map, key, &%{&1 | exp: Entry.exp(ttl)})}}

      false ->
        {:reply, {:ok, false}, state}
    end
  end

  def handle_call({:touch, key}, _from, %__MODULE__{map: map} = state) do
    case Map.has_key?(map, key) do
      true ->
        {:reply, {:ok, true}, %{state | map: Map.update!(map, key, &%{&1 | touched: Time.now()})}}

      false ->
        {:reply, {:ok, false}, state}
    end
  end

  def handle_call({:q, :all, nil, opts}, _from, %__MODULE__{map: map} = state) do
    {:reply, {:ok, return(Enum, map, opts)}, state}
  end

  def handle_call({:q, :count_all, nil, _opts}, _from, %__MODULE__{map: map} = state) do
    {:reply, {:ok, map_size(map)}, state}
  end

  def handle_call({:q, :delete_all, nil, _opts}, _from, %__MODULE__{map: map} = state) do
    {:reply, {:ok, map_size(map)}, %{state | map: %{}}}
  end

  def handle_call({:q, :stream, nil, opts}, _from, %__MODULE__{map: map} = state) do
    {:reply, {:ok, return(Stream, map, opts)}, state}
  end

  def handle_call({:q, _op, query, _opts}, _from, %__MODULE__{} = state) do
    error = wrap_error Nebulex.QueryError, message: "invalid query", query: query

    {:reply, error, state}
  end

  ## Private Functions

  defp return(module, map, opts) do
    case Keyword.get(opts, :return, :key) do
      :key ->
        module.map(map, fn {k, _e} -> k end)

      :value ->
        module.map(map, fn {_k, e} -> e.value end)

      {:key, :value} ->
        module.map(map, fn {k, e} -> {k, e.value} end)

      :entry ->
        module.map(map, fn {k, e} ->
          %Nebulex.Entry{key: k, value: e.value, touched: e.touched, exp: e.exp}
        end)
    end
  end
end
