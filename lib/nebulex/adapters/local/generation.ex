defmodule Nebulex.Adapters.Local.Generation do
  @moduledoc """
  Generational garbage collection process.

  The generational garbage collector manage the heap as several sub-heaps,
  known as generations, based on age of the objects. An object is allocated
  in the youngest generation, sometimes called the nursery, and is promoted
  to an older generation if its lifetime exceeds the threshold of its current
  generation (defined by option `:gc_interval`). Everytime the GC runs
  (triggered by `:gc_interval` timeout), a new cache generation is created
  and the oldest one is deleted.

  The only way to create new generations is through this module (this server
  is the metadata owner) calling `new/2` function. When a Cache is created,
  a generational garbage collector is attached to it automatically,
  therefore, this server MUST NOT be started directly.

  ## Options

  These options are configured through the `Nebulex.Adapters.Local` adapter:

    * `:gc_interval` - Interval time in milliseconds to garbage collection
      to run, delete the oldest generation and create a new one. If this
      option is not set, garbage collection is never executed, so new
      generations must be created explicitly, e.g.: `new(cache, [])`.

    * `:max_size` - Max number of cached entries (cache limit). If it is not
      set (`nil`), the check to release memory is not performed (the default).

    * `:allocated_memory` - Max size in bytes allocated for a cache generation.
      If this option is set and the configured value is reached, a new cache
      generation is created so the oldest is deleted and force releasing memory
      space. If it is not set (`nil`), the cleanup check to release memory is
      not performed (the default).

    * `:gc_cleanup_min_timeout` - The min timeout in milliseconds for triggering
      the next cleanup and memory check. This will be the timeout to use when
      either the max size or max allocated memory is reached.
      Defaults to `10_000` (10 seconds).

    * `:gc_cleanup_max_timeout` - The max timeout in milliseconds for triggering
      the next cleanup and memory check. This is the timeout used when the cache
      starts and there are few entries or the consumed memory is near to `0`.
      Defaults to `600_000` (10 minutes).
  """

  # State
  defstruct [
    :meta_tab,
    :backend,
    :backend_opts,
    :gc_interval,
    :gc_heartbeat_ref,
    :max_size,
    :allocated_memory,
    :gc_cleanup_min_timeout,
    :gc_cleanup_max_timeout,
    :gc_cleanup_ref
  ]

  use GenServer

  import Nebulex.Helpers

  alias Nebulex.Adapter
  alias Nebulex.Adapters.Local
  alias Nebulex.Adapters.Local.{Backend, Metadata}

  @type t :: :ets.tid()
  @type server_ref :: pid | atom | :ets.tid()

  @compile {:inline, server: 1, list: 1, newer: 1}

  ## API

  @doc """
  Starts the garbage collector for the build-in local cache adapter.
  """
  @spec start_link(Nebulex.Cache.opts()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc """
  Creates a new cache generation. Once the max number of generations
  is reached, when a new generation is created, the oldest one is
  deleted.

  ## Options

    * `:reset_timer` - Indicates if the poll frequency time-out should
      be reset or not (default: true).

  ## Example

      Nebulex.Adapters.Local.Generation.new(MyCache, reset_timer: :false)
  """
  @spec new(server_ref, Nebulex.Cache.opts()) :: [atom]
  def new(server_ref, opts \\ []) do
    do_call(server_ref, {:new_generation, opts})
  end

  @doc """
  Flushes the cache (including all its generations).

  ## Example

      Nebulex.Adapters.Local.Generation.flush(MyCache)
  """
  @spec flush(server_ref) :: integer
  def flush(server_ref) do
    do_call(server_ref, :flush)
  end

  @doc """
  Reallocates the block of memory that was previously allocated for the given
  `server_ref` with the new `size`. In other words, reallocates the max memory
  size for a cache generation.

  ## Example

      Nebulex.Adapters.Local.Generation.realloc(MyCache, 1_000_000)
  """
  @spec realloc(server_ref, pos_integer) :: :ok
  def realloc(server_ref, size) do
    do_call(server_ref, {:realloc, size})
  end

  @doc """
  Returns the memory info in a tuple form `{used_mem, total_mem}`.

  ## Example

      Nebulex.Adapters.Local.Generation.memory_info(MyCache)
  """
  @spec memory_info(server_ref) :: {used_mem :: non_neg_integer, total_mem :: non_neg_integer}
  def memory_info(server_ref) do
    do_call(server_ref, :memory_info)
  end

  @doc """
  Returns the list of the generations in the form `[newer, older]`.

  ## Example

      Nebulex.Adapters.Local.Generation.list(MyCache)
  """
  @spec list(server_ref) :: [t]
  def list(server_ref) do
    server_ref
    |> get_meta_tab()
    |> Metadata.get(:generations, [])
  end

  @doc """
  Returns the newer generation.

  ## Example

      Nebulex.Adapters.Local.Generation.newer(MyCache)
  """
  @spec newer(server_ref) :: t
  def newer(server_ref) do
    server_ref
    |> get_meta_tab()
    |> Metadata.get(:generations, [])
    |> hd()
  end

  @doc """
  Returns the PID of the GC server for the given `server_ref`.

  ## Example

      Nebulex.Adapters.Local.Generation.server(MyCache)
  """
  @spec server(server_ref) :: pid
  def server(server_ref) do
    server_ref
    |> get_meta_tab()
    |> Metadata.fetch!(:gc_pid)
  end

  defp get_meta_tab(server_ref) when is_atom(server_ref) or is_pid(server_ref) do
    Adapter.with_meta(server_ref, fn _, %{meta_tab: meta_tab} ->
      meta_tab
    end)
  end

  defp get_meta_tab(server_ref), do: server_ref

  ## GenServer Callbacks

  @impl true
  def init(opts) do
    # add the GC PID to the meta table
    meta_tab = Keyword.fetch!(opts, :meta_tab)
    :ok = Metadata.put(meta_tab, :gc_pid, self())

    # backend for creating new tables
    backend = Keyword.fetch!(opts, :backend)
    backend_opts = Keyword.get(opts, :backend_opts, [])

    # memory check options
    max_size = get_option(opts, :max_size, &(is_integer(&1) and &1 > 0))
    allocated_memory = get_option(opts, :allocated_memory, &(is_integer(&1) and &1 > 0))
    cleanup_min = get_option(opts, :gc_cleanup_min_timeout, &(is_integer(&1) and &1 > 0), 10_000)
    cleanup_max = get_option(opts, :gc_cleanup_max_timeout, &(is_integer(&1) and &1 > 0), 600_000)
    gc_cleanup_ref = if max_size || allocated_memory, do: start_timer(cleanup_max, nil, :cleanup)

    # GC options
    gc_interval = get_option(opts, :gc_interval, &(is_integer(&1) and &1 > 0))

    init_state = %__MODULE__{
      meta_tab: meta_tab,
      backend: backend,
      backend_opts: backend_opts,
      gc_interval: gc_interval,
      max_size: max_size,
      allocated_memory: allocated_memory,
      gc_cleanup_min_timeout: cleanup_min,
      gc_cleanup_max_timeout: cleanup_max,
      gc_cleanup_ref: gc_cleanup_ref
    }

    # Timer ref
    {:ok, ref} =
      if gc_interval,
        do: {new_gen(init_state), start_timer(gc_interval)},
        else: {new_gen(init_state), nil}

    {:ok, %{init_state | gc_heartbeat_ref: ref}}
  end

  @impl true
  def handle_call({:new_generation, opts}, _from, %__MODULE__{} = state) do
    :ok = new_gen(state)

    ref =
      opts
      |> get_option(:reset_timer, &is_boolean/1, true, & &1)
      |> maybe_reset_timer(state)

    state = %{state | gc_heartbeat_ref: ref}
    {:reply, :ok, state}
  end

  def handle_call(:flush, _from, %__MODULE__{meta_tab: meta_tab, backend: backend} = state) do
    size = Local.size(%{meta_tab: meta_tab, backend: backend})

    :ok =
      meta_tab
      |> list()
      |> Enum.each(&backend.delete_all_objects(&1))

    {:reply, size, state}
  end

  def handle_call({:realloc, mem_size}, _from, %__MODULE__{} = state) do
    {:reply, :ok, %{state | allocated_memory: mem_size}}
  end

  def handle_call(
        :memory_info,
        _from,
        %__MODULE__{backend: backend, meta_tab: meta_tab, allocated_memory: allocated} = state
      ) do
    {:reply, {memory_info(backend, meta_tab), allocated}, state}
  end

  @impl true
  def handle_info(:heartbeat, %__MODULE__{gc_interval: time, gc_heartbeat_ref: ref} = state) do
    :ok = new_gen(state)
    {:noreply, %{state | gc_heartbeat_ref: start_timer(time, ref)}}
  end

  def handle_info(:cleanup, state) do
    state =
      state
      |> check_size()
      |> check_memory()

    {:noreply, state}
  end

  def handle_info(_message, state) do
    {:noreply, state}
  end

  defp check_size(
         %__MODULE__{
           meta_tab: meta_tab,
           max_size: max_size,
           backend: backend
         } = state
       )
       when not is_nil(max_size) do
    meta_tab
    |> newer()
    |> backend.info(:size)
    |> maybe_cleanup(max_size, state)
  end

  defp check_size(state), do: state

  defp check_memory(
         %__MODULE__{
           meta_tab: meta_tab,
           backend: backend,
           allocated_memory: allocated
         } = state
       )
       when not is_nil(allocated) do
    backend
    |> memory_info(meta_tab)
    |> maybe_cleanup(allocated, state)
  end

  defp check_memory(state), do: state

  defp maybe_cleanup(
         size,
         max_size,
         %__MODULE__{
           gc_cleanup_max_timeout: max_timeout,
           gc_cleanup_ref: cleanup_ref,
           gc_interval: gc_interval,
           gc_heartbeat_ref: heartbeat_ref
         } = state
       )
       when size >= max_size do
    :ok = new_gen(state)

    %{
      state
      | gc_cleanup_ref: start_timer(max_timeout, cleanup_ref, :cleanup),
        gc_heartbeat_ref: start_timer(gc_interval, heartbeat_ref)
    }
  end

  defp maybe_cleanup(
         size,
         max_size,
         %__MODULE__{
           gc_cleanup_min_timeout: min_timeout,
           gc_cleanup_max_timeout: max_timeout,
           gc_cleanup_ref: cleanup_ref
         } = state
       ) do
    cleanup_ref =
      size
      |> linear_inverse_backoff(max_size, min_timeout, max_timeout)
      |> start_timer(cleanup_ref, :cleanup)

    %{state | gc_cleanup_ref: cleanup_ref}
  end

  ## Private Functions

  defp do_call(tab, message) do
    tab
    |> server()
    |> GenServer.call(message)
  end

  defp new_gen(%__MODULE__{meta_tab: meta_tab, backend: backend, backend_opts: backend_opts}) do
    # create new generation
    gen_tab = Backend.new(backend, meta_tab, backend_opts)

    # update generation list
    case list(meta_tab) do
      [newer, older] ->
        _ = Backend.delete(backend, meta_tab, older)
        Metadata.put(meta_tab, :generations, [gen_tab, newer])

      [newer] ->
        Metadata.put(meta_tab, :generations, [gen_tab, newer])

      [] ->
        Metadata.put(meta_tab, :generations, [gen_tab])
    end
  end

  defp start_timer(time, ref \\ nil, event \\ :heartbeat) do
    _ = if ref, do: Process.cancel_timer(ref)
    Process.send_after(self(), event, time)
  end

  defp maybe_reset_timer(_, %__MODULE__{gc_interval: nil} = state) do
    state.gc_heartbeat_ref
  end

  defp maybe_reset_timer(false, state) do
    state.gc_heartbeat_ref
  end

  defp maybe_reset_timer(true, %__MODULE__{} = state) do
    start_timer(state.gc_interval, state.gc_heartbeat_ref)
  end

  defp memory_info(backend, meta_tab) do
    meta_tab
    |> newer()
    |> backend.info(:memory)
    |> Kernel.*(:erlang.system_info(:wordsize))
  end

  defp linear_inverse_backoff(size, max_size, min_timeout, max_timeout) do
    round((min_timeout - max_timeout) / max_size * size + max_timeout)
  end
end
