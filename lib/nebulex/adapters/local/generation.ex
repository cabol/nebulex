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

    * `:gc_interval` - If it is set, an integer > 0 is expected defining the
      interval time in milliseconds to garbage collection to run, delete the
      oldest generation and create a new one. If this option is not set,
      garbage collection is never executed, so new generations must be
      created explicitly, e.g.: `MyCache.new_generation(opts)`.

    * `:max_size` - If it is set, an integer > 0 is expected defining the
      max number of cached entries (cache limit). If it is not set (`nil`),
      the check to release memory is not performed (the default).

    * `:allocated_memory` - If it is set, an integer > 0 is expected defining
      the max size in bytes allocated for a cache generation. When this option
      is set and the configured value is reached, a new cache generation is
      created so the oldest is deleted and force releasing memory space.
      If it is not set (`nil`), the cleanup check to release memory is
      not performed (the default).

    * `:gc_cleanup_min_timeout` - An integer > 0 defining the min timeout in
      milliseconds for triggering the next cleanup and memory check. This will
      be the timeout to use when either the max size or max allocated memory
      is reached. Defaults to `10_000` (10 seconds).

    * `:gc_cleanup_max_timeout` - An integer > 0 defining the max timeout in
      milliseconds for triggering the next cleanup and memory check. This is
      the timeout used when the cache starts and there are few entries or the
      consumed memory is near to `0`. Defaults to `600_000` (10 minutes).

  """

  # State
  defstruct [
    :cache,
    :telemetry_prefix,
    :meta_tab,
    :backend,
    :backend_opts,
    :stats_counter,
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
  alias Nebulex.Adapter.Stats
  alias Nebulex.Adapters.Local
  alias Nebulex.Adapters.Local.{Backend, Metadata}

  @type t :: %__MODULE__{}
  @type server_ref :: pid | atom | :ets.tid()
  @type opts :: Nebulex.Cache.opts()

  ## API

  @doc """
  Starts the garbage collector for the build-in local cache adapter.
  """
  @spec start_link(opts) :: GenServer.on_start()
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

      Nebulex.Adapters.Local.Generation.new(MyCache)

      Nebulex.Adapters.Local.Generation.new(MyCache, reset_timer: false)
  """
  @spec new(server_ref, opts) :: [atom]
  def new(server_ref, opts \\ []) do
    reset_timer? = get_option(opts, :reset_timer, "boolean", &is_boolean/1, true)
    do_call(server_ref, {:new_generation, reset_timer?})
  end

  @doc """
  Removes or flushes all entries from the cache (including all its generations).

  ## Example

      Nebulex.Adapters.Local.Generation.delete_all(MyCache)
  """
  @spec delete_all(server_ref) :: integer
  def delete_all(server_ref) do
    do_call(server_ref, :delete_all)
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
  Resets the timer for pushing new cache generations.

  ## Example

      Nebulex.Adapters.Local.Generation.reset_timer(MyCache)
  """
  def reset_timer(server_ref) do
    server_ref
    |> server()
    |> GenServer.cast(:reset_timer)
  end

  @doc """
  Returns the list of the generations in the form `[newer, older]`.

  ## Example

      Nebulex.Adapters.Local.Generation.list(MyCache)
  """
  @spec list(server_ref) :: [:ets.tid()]
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
  @spec newer(server_ref) :: :ets.tid()
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

  @doc """
  A convenience function for retrieving the state.
  """
  @spec get_state(server_ref) :: t
  def get_state(server_ref) do
    server_ref
    |> server()
    |> GenServer.call(:get_state)
  end

  defp do_call(tab, message) do
    tab
    |> server()
    |> GenServer.call(message)
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
    # Initial state
    state = struct(__MODULE__, parse_opts(opts))

    # Init cleanup timer
    cleanup_ref =
      if state.max_size || state.allocated_memory,
        do: start_timer(state.gc_cleanup_max_timeout, nil, :cleanup)

    # Timer ref
    {:ok, ref} =
      if state.gc_interval,
        do: {new_gen(state), start_timer(state.gc_interval)},
        else: {new_gen(state), nil}

    {:ok, %{state | gc_cleanup_ref: cleanup_ref, gc_heartbeat_ref: ref}}
  end

  defp parse_opts(opts) do
    # Get adapter metadata
    adapter_meta = Keyword.fetch!(opts, :adapter_meta)

    # Add the GC PID to the meta table
    meta_tab = Map.fetch!(adapter_meta, :meta_tab)
    :ok = Metadata.put(meta_tab, :gc_pid, self())

    # Common validators
    pos_integer = &(is_integer(&1) and &1 > 0)
    pos_integer_or_nil = &((is_integer(&1) and &1 > 0) or is_nil(&1))

    Map.merge(adapter_meta, %{
      backend_opts: Keyword.get(opts, :backend_opts, []),
      gc_interval: get_option(opts, :gc_interval, "an integer > 0", pos_integer_or_nil),
      max_size: get_option(opts, :max_size, "an integer > 0", pos_integer_or_nil),
      allocated_memory: get_option(opts, :allocated_memory, "an integer > 0", pos_integer_or_nil),
      gc_cleanup_min_timeout:
        get_option(opts, :gc_cleanup_min_timeout, "an integer > 0", pos_integer, 10_000),
      gc_cleanup_max_timeout:
        get_option(opts, :gc_cleanup_max_timeout, "an integer > 0", pos_integer, 600_000)
    })
  end

  @impl true
  def handle_call(:delete_all, _from, %__MODULE__{} = state) do
    size =
      state
      |> Map.from_struct()
      |> Local.execute(:count_all, nil, [])

    :ok = new_gen(state)

    :ok =
      state.meta_tab
      |> list()
      |> Enum.each(&state.backend.delete_all_objects(&1))

    {:reply, size, %{state | gc_heartbeat_ref: maybe_reset_timer(true, state)}}
  end

  def handle_call({:new_generation, reset_timer?}, _from, state) do
    :ok = new_gen(state)
    {:reply, :ok, %{state | gc_heartbeat_ref: maybe_reset_timer(reset_timer?, state)}}
  end

  def handle_call(
        :memory_info,
        _from,
        %__MODULE__{backend: backend, meta_tab: meta_tab, allocated_memory: allocated} = state
      ) do
    {:reply, {memory_info(backend, meta_tab), allocated}, state}
  end

  def handle_call({:realloc, mem_size}, _from, state) do
    {:reply, :ok, %{state | allocated_memory: mem_size}}
  end

  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_cast(:reset_timer, state) do
    {:noreply, %{state | gc_heartbeat_ref: maybe_reset_timer(true, state)}}
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

  defp new_gen(%__MODULE__{
         meta_tab: meta_tab,
         backend: backend,
         backend_opts: backend_opts,
         stats_counter: stats_counter
       }) do
    # Create new generation
    gen_tab = Backend.new(backend, meta_tab, backend_opts)

    # Update generation list
    case list(meta_tab) do
      [newer, older] ->
        # Since the older generation is deleted, update evictions count
        :ok = Stats.incr(stats_counter, :evictions, backend.info(older, :size))

        # Process the older generation:
        # - Delete previously stored deprecated generation
        # - Flush the older generation
        # - Deprecate it (mark it for deletion)
        :ok = process_older_gen(meta_tab, backend, older)

        # Update generations
        Metadata.put(meta_tab, :generations, [gen_tab, newer])

      [newer] ->
        # Update generations
        Metadata.put(meta_tab, :generations, [gen_tab, newer])

      [] ->
        # update generations
        Metadata.put(meta_tab, :generations, [gen_tab])
    end
  end

  # The older generation cannot be removed immediately because there may be
  # ongoing operations using it, then it may cause race-condition errors.
  # Hence, the idea is to keep it alive till a new generation is pushed, but
  # flushing its data before so that we release memory space. By the time a new
  # generation is pushed, then it is safe to delete it completely.
  defp process_older_gen(meta_tab, backend, older) do
    if deprecated = Metadata.get(meta_tab, :deprecated) do
      # Delete deprecated generation if it does exist
      _ = Backend.delete(backend, meta_tab, deprecated)
    end

    # Flush older generation to release space so it can be marked for deletion
    true = backend.delete_all_objects(older)

    # Keep alive older generation reference into the metadata
    Metadata.put(meta_tab, :deprecated, older)
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
