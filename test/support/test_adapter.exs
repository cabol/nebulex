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
  @behaviour Nebulex.Adapter.KV
  @behaviour Nebulex.Adapter.Queryable

  # Inherit default transaction implementation
  use Nebulex.Adapter.Transaction

  # Inherit default info implementation
  use Nebulex.Adapters.Common.Info

  import Nebulex.Utils

  alias Nebulex.Adapters.Common.Info.Stats
  alias __MODULE__.{Entry, KV}
  alias Nebulex.Time

  ## Nebulex.Adapter

  @impl true
  defmacro __before_compile__(_env), do: :ok

  @impl true
  def init(opts) do
    # Required options
    telemetry = Keyword.fetch!(opts, :telemetry)
    telemetry_prefix = Keyword.fetch!(opts, :telemetry_prefix)

    # Init stats_counter
    stats_counter =
      if Keyword.get(opts, :stats, true) == true do
        Stats.init(telemetry_prefix)
      end

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

  ## Nebulex.Adapter.KV

  @impl true
  def fetch(adapter_meta, key, _opts) do
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
         adapter_meta
       )
       when is_integer(exp) do
    if Time.now() >= exp do
      :ok = delete(adapter_meta, key, [])

      wrap_error Nebulex.KeyError, key: key, reason: :expired
    else
      {:ok, entry}
    end
  end

  defp validate_ttl(:error, key, adapter_meta) do
    cache = adapter_meta[:name] || adapter_meta[:cache]

    wrap_error Nebulex.KeyError, cache: cache, key: key, reason: :not_found
  end

  @impl true
  def put(adapter_meta, key, value, on_write, ttl, keep_ttl?, _opts) do
    do_put(adapter_meta.pid, key, on_write, Entry.new(value, ttl), keep_ttl?)
  end

  defp do_put(pid, key, :put, entry, keep_ttl?) do
    GenServer.call(pid, {:put, key, entry, keep_ttl?})
  end

  defp do_put(pid, key, :put_new, entry, keep_ttl?) do
    GenServer.call(pid, {:put_new, key, entry, keep_ttl?})
  end

  defp do_put(pid, key, :replace, entry, keep_ttl?) do
    GenServer.call(pid, {:replace, key, entry, keep_ttl?})
  end

  @impl true
  def put_all(adapter_meta, entries, on_write, ttl, _opts) do
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
  def delete(adapter_meta, key, _opts) do
    GenServer.call(adapter_meta.pid, {:delete, key})
  end

  @impl true
  def take(adapter_meta, key, _opts) do
    with {:ok, %Entry{value: value}} <-
           adapter_meta.pid
           |> GenServer.call({:pop, key})
           |> validate_ttl(key, adapter_meta) do
      {:ok, value}
    end
  end

  @impl true
  def update_counter(adapter_meta, key, amount, default, ttl, _opts) do
    _ = do_fetch(adapter_meta, key)

    GenServer.call(
      adapter_meta.pid,
      {:update_counter, key, amount, Entry.new(default + amount, ttl)}
    )
  end

  @impl true
  def has_key?(adapter_meta, key, _opts) do
    case fetch(%{adapter_meta | telemetry: false}, key, []) do
      {:ok, _} -> {:ok, true}
      {:error, _} -> {:ok, false}
    end
  end

  @impl true
  def ttl(adapter_meta, key, _opts) do
    with {:ok, entry} <- do_fetch(adapter_meta, key) do
      {:ok, entry_ttl(entry)}
    end
  end

  @impl true
  def expire(adapter_meta, key, ttl, _opts) do
    GenServer.call(adapter_meta.pid, {:expire, key, ttl})
  end

  @impl true
  def touch(adapter_meta, key, _opts) do
    GenServer.call(adapter_meta.pid, {:touch, key})
  end

  ## Nebulex.Adapter.Queryable

  @impl true
  def execute(adapter_meta, query_meta, opts)

  def execute(_adapter_meta, %{op: :get_all, query: {:in, []}}, _opts) do
    {:ok, []}
  end

  def execute(_adapter_meta, %{op: op, query: {:in, []}}, _opts)
      when op in [:count_all, :delete_all] do
    {:ok, 0}
  end

  def execute(%{pid: pid}, query_meta, _opts) do
    with :ok <- assert_query(query_meta.query) do
      GenServer.call(pid, {:q, query_meta})
    end
  end

  @impl true
  def stream(%{pid: pid}, query_meta, opts) do
    now = Time.now()
    max_entries = Keyword.fetch!(opts, :max_entries)

    with :ok <- assert_query(query_meta.query) do
      GenServer.call(pid, {:q, query_meta, max_entries, now})
    end
  end

  defp assert_query({:q, nil}) do
    :ok
  end

  defp assert_query({:in, keys}) when is_list(keys) do
    :ok
  end

  defp assert_query({:q, q}) do
    raise Nebulex.QueryError, query: q
  end

  ## Nebulex.Adapter.Info

  @impl true
  def info(adapter_meta, spec, opts) do
    cond do
      spec == :all ->
        with {:ok, info} <- GenServer.call(adapter_meta.pid, {:info, [:memory]}),
             {:ok, base_info} <- super(adapter_meta, :all, opts) do
          {:ok, Map.merge(base_info, info)}
        end

      spec == :memory ->
        GenServer.call(adapter_meta.pid, {:info, spec})

      is_list(spec) and Enum.member?(spec, :memory) ->
        with {:ok, info} <- GenServer.call(adapter_meta.pid, {:info, [:memory]}),
             spec = Enum.reject(spec, &(&1 == :memory)),
             {:ok, base_info} <- super(adapter_meta, spec, opts) do
          {:ok, Map.merge(base_info, info)}
        end

      true ->
        super(adapter_meta, spec, opts)
    end
  end

  ## Helpers

  defp entry_ttl(%Entry{exp: :infinity}), do: :infinity
  defp entry_ttl(%Entry{exp: exp}), do: exp - Time.now()
end

defmodule Nebulex.TestAdapter.KV do
  @moduledoc false

  use GenServer

  import Nebulex.Utils, only: [wrap_error: 2]

  alias Nebulex.TestAdapter.Entry
  alias Nebulex.Time

  ## Internals

  # Internal state
  defstruct map: nil, adapter_meta: nil

  ## API

  @spec start_link(keyword) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  ## GenServer callbacks

  @impl true
  def init(opts) do
    {:ok, %__MODULE__{map: %{}, adapter_meta: Keyword.fetch!(opts, :adapter_meta)}}
  end

  @impl true
  def handle_call(request, from, state)

  def handle_call({:fetch, key}, _from, %__MODULE__{map: map} = state) do
    {:reply, Map.fetch(map, key), state}
  end

  def handle_call({:put, key, value, false}, _from, %__MODULE__{map: map} = state) do
    {:reply, {:ok, true}, %{state | map: Map.put(map, key, value)}}
  end

  def handle_call({:put, key, entry, true}, _from, %__MODULE__{map: map} = state) do
    {:reply, {:ok, true},
     %{
       state
       | map: Map.update(map, key, entry, &%{&1 | value: entry.value, touched: entry.touched})
     }}
  end

  def handle_call({:put_new, key, value, _keep_ttl?}, _from, %__MODULE__{map: map} = state) do
    case Map.has_key?(map, key) do
      true ->
        {:reply, {:ok, false}, state}

      false ->
        {:reply, {:ok, true}, %{state | map: Map.put_new(map, key, value)}}
    end
  end

  def handle_call({:replace, key, entry, keep_ttl?}, _from, %__MODULE__{map: map} = state) do
    case {Map.has_key?(map, key), keep_ttl?} do
      {true, false} ->
        {:reply, {:ok, true}, %{state | map: Map.replace!(map, key, entry)}}

      {true, true} ->
        {:reply, {:ok, true},
         %{state | map: Map.update!(map, key, &%{&1 | value: entry.value, touched: entry.touched})}}

      {false, _} ->
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

  def handle_call(
        {:update_counter, key, amount, default},
        _from,
        %__MODULE__{map: map} = state
      ) do
    case Map.fetch(map, key) do
      {:ok, %{value: value}} when not is_integer(value) ->
        error = wrap_error Nebulex.Error, reason: :badarith, cache: nil

        {:reply, error, map}

      _other ->
        map = Map.update(map, key, default, &%{&1 | value: &1.value + amount})
        counter = Map.fetch!(map, key)

        {:reply, {:ok, counter.value}, %{state | map: map}}
    end
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

  def handle_call(
        {:q, %{op: :get_all, query: {:q, nil}, select: select}},
        _from,
        %__MODULE__{map: map} = state
      ) do
    map =
      map
      |> filter_unexpired()
      |> return(Enum, select)

    {:reply, {:ok, map}, state}
  end

  def handle_call(
        {:q, %{op: :get_all, query: {:in, keys}, select: select}},
        _from,
        %__MODULE__{map: map} = state
      ) do
    map =
      map
      |> Map.take(keys)
      |> filter_unexpired()
      |> return(Enum, select)

    {:reply, {:ok, map}, state}
  end

  def handle_call(
        {:q, %{op: :count_all, query: {:q, nil}}},
        _from,
        %__MODULE__{map: map} = state
      ) do
    {:reply, {:ok, map_size(map)}, state}
  end

  def handle_call(
        {:q, %{op: :count_all, query: {:in, keys}}},
        _from,
        %__MODULE__{map: map} = state
      ) do
    count = map |> Map.take(keys) |> map_size()

    {:reply, {:ok, count}, state}
  end

  def handle_call(
        {:q, %{op: :delete_all, query: {:q, nil}}},
        _from,
        %__MODULE__{map: map} = state
      ) do
    {:reply, {:ok, map_size(map)}, %{state | map: %{}}}
  end

  def handle_call(
        {:q, %{op: :delete_all, query: {:in, keys}}},
        _from,
        %__MODULE__{map: map} = state
      ) do
    total_count = map_size(map)
    map = Map.drop(map, keys)

    {:reply, {:ok, total_count - map_size(map)}, %{state | map: map}}
  end

  def handle_call(
        {:q, %{op: :stream, query: {:q, nil}, select: select}, max_entries, now},
        _from,
        %__MODULE__{map: map} = state
      ) do
    {:reply, {:ok, stream_unexpired(map, max_entries, select, now)}, state}
  end

  def handle_call(
        {:q, %{op: :stream, query: {:in, keys}, select: select}, max_entries, now},
        _from,
        %__MODULE__{map: map} = state
      ) do
    stream =
      map
      |> Stream.chunk_every(max_entries)
      |> Task.async_stream(fn chunk ->
        Enum.filter(chunk, fn {k, %Entry{exp: exp}} ->
          Enum.member?(keys, k) and exp > now
        end)
      end)
      |> Stream.flat_map(fn {:ok, results} -> results end)
      |> return(Stream, select)

    {:reply, {:ok, stream}, state}
  end

  def handle_call({:info, :memory}, _from, %__MODULE__{map: map} = state) do
    {:reply, {:ok, memory(map)}, state}
  end

  def handle_call({:info, [_ | _]}, _from, %__MODULE__{map: map} = state) do
    {:reply, {:ok, %{memory: memory(map)}}, state}
  end

  ## Private Functions

  defp stream_unexpired(map, max_entries, select, now) do
    map
    |> Stream.chunk_every(max_entries)
    |> Task.async_stream(fn chunk ->
      Enum.filter(chunk, fn {_, %Entry{exp: exp}} -> exp > now end)
    end)
    |> Stream.flat_map(fn {:ok, results} -> results end)
    |> return(Stream, select)
  end

  defp filter_unexpired(enum) do
    now = Time.now()

    for {k, %Entry{exp: exp} = e} <- enum, exp > now, into: %{} do
      {k, e}
    end
  end

  defp return(map, module, select) do
    case select do
      :key ->
        module.map(map, fn {k, _e} -> k end)

      :value ->
        module.map(map, fn {_k, e} -> e.value end)

      {:key, :value} ->
        module.map(map, fn {k, e} -> {k, e.value} end)
    end
  end

  defp memory(map) when map_size(map) == 0 do
    %{
      # Fixed
      total: 1_000_000,
      # Empty
      used: 0
    }
  end

  defp memory(map) do
    %{
      # Fixed
      total: 1_000_000,
      # Fake size
      used: map |> :erlang.term_to_binary() |> byte_size()
    }
  end
end
