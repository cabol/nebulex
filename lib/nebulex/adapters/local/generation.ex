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
      the max allocated memory is reached. Defaults to `30_000`.

    * `:gc_cleanup_max_timeout` - The max timeout in milliseconds for triggering
      the next cleanup and memory check. This is the timeout used when the cache
      starts or the consumed memory is `0`. Defaults to `300_000`.
  """

  # State
  defstruct [
    :name,
    :backend,
    :backend_opts,
    :gc_interval,
    :gc_heartbeat_ref,
    :gen_name,
    :gen_index,
    :max_size,
    :allocated_memory,
    :gc_cleanup_min_timeout,
    :gc_cleanup_max_timeout,
    :gc_cleanup_ref
  ]

  use GenServer

  import Nebulex.Helpers

  alias Nebulex.Adapters.Local

  @compile {:inline, server_name: 1}

  ## API

  @doc """
  Starts the garbage collector for the build-in local cache adapter.
  """
  @spec start_link(Nebulex.Cache.opts()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, {name, opts}, name: server_name(name))
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
  @spec new(atom, Nebulex.Cache.opts()) :: [atom]
  def new(name, opts \\ []) do
    do_call(name, {:new_generation, opts})
  end

  @doc """
  Flushes the cache (including all its generations).

  ## Example

      Nebulex.Adapters.Local.Generation.flush(MyCache)
  """
  @spec flush(atom) :: integer
  def flush(name) do
    do_call(name, :flush)
  end

  @doc """
  Reallocates the block of memory that was previously allocated for the given
  `cache` with the new `size`. In other words, reallocates the max memory size
  for a cache generation.

  ## Example

      Nebulex.Adapters.Local.Generation.realloc(MyCache, 1_000_000)
  """
  @spec realloc(atom, pos_integer) :: :ok
  def realloc(name, size) do
    do_call(name, {:realloc, size})
  end

  @doc """
  Returns the memory info in a tuple `{used_mem, total_mem}`.

  ## Example

      Nebulex.Adapters.Local.Generation.memory_info(MyCache)
  """
  @spec memory_info(atom) :: {used_mem :: non_neg_integer, total_mem :: non_neg_integer}
  def memory_info(name) do
    do_call(name, :memory_info)
  end

  @doc """
  Returns the name of the GC server for the given cache `name`.

  ## Example

      Nebulex.Adapters.Local.Generation.server_name(MyCache)
  """
  @spec server_name(atom) :: atom
  def server_name(name), do: normalize_module_name([name, Generation])

  @doc """
  Returns the list of the generations in the form `[newer, older]`.

  ## Example

      Nebulex.Adapters.Local.Generation.list(MyCache)
  """
  @spec list(atom) :: [atom]
  def list(name) do
    [
      :persistent_term.get({__MODULE__, name, :newer})
      | if(older = :persistent_term.get({__MODULE__, name, :older}, nil), do: [older], else: [])
    ]
  end

  @doc """
  Returns the newer generation.

  ## Example

      Nebulex.Adapters.Local.Generation.newer(MyCache)
  """
  @spec newer(atom) :: atom
  def newer(name) do
    :persistent_term.get({__MODULE__, name, :newer})
  end

  ## GenServer Callbacks

  @impl true
  def init({name, opts}) do
    _ = Process.flag(:trap_exit, true)

    # backend for creating new tables
    backend = Keyword.fetch!(opts, :backend)
    backend_opts = Keyword.get(opts, :backend_opts, [])

    # memory check options
    max_size = get_option(opts, :max_size, &(is_integer(&1) and &1 > 0))
    allocated_memory = get_option(opts, :allocated_memory, &(is_integer(&1) and &1 > 0))
    cleanup_min = get_option(opts, :gc_cleanup_min_timeout, &(is_integer(&1) and &1 > 0), 30_000)
    cleanup_max = get_option(opts, :gc_cleanup_max_timeout, &(is_integer(&1) and &1 > 0), 300_000)
    gc_cleanup_ref = if max_size || allocated_memory, do: start_timer(cleanup_max, nil, :cleanup)

    # GC options
    {{gen_name, gen_index}, ref} =
      if gc_interval = get_option(opts, :gc_interval, &(is_integer(&1) and &1 > 0)),
        do: {new_gen(name, 0, backend, backend_opts), start_timer(gc_interval)},
        else: {new_gen(name, 0, backend, backend_opts), nil}

    init_state = %__MODULE__{
      name: name,
      backend: backend,
      backend_opts: backend_opts,
      gc_interval: gc_interval,
      gen_name: gen_name,
      gen_index: gen_index,
      gc_heartbeat_ref: ref,
      max_size: max_size,
      allocated_memory: allocated_memory,
      gc_cleanup_min_timeout: cleanup_min,
      gc_cleanup_max_timeout: cleanup_max,
      gc_cleanup_ref: gc_cleanup_ref
    }

    {:ok, init_state}
  end

  @impl true
  def terminate(_reason, %__MODULE__{name: name} = state) do
    # cleanup
    true = :persistent_term.erase({__MODULE__, name, :older})
    true = :persistent_term.erase({__MODULE__, name, :newer})
    state
  end

  @impl true
  def handle_call(
        {:new_generation, opts},
        _from,
        %__MODULE__{
          name: name,
          gen_index: gen_index,
          backend: backend,
          backend_opts: backend_opts
        } = state
      ) do
    {gen_name, gen_index} = new_gen(name, gen_index, backend, backend_opts)

    ref =
      opts
      |> get_option(:reset_timer, &is_boolean/1, true, & &1)
      |> maybe_reset_timer(state)

    state = %{state | gen_name: gen_name, gen_index: gen_index, gc_heartbeat_ref: ref}
    {:reply, :ok, state}
  end

  def handle_call(:flush, _from, %__MODULE__{name: name, backend: backend} = state) do
    size = Local.size(%{name: name, backend: backend})

    :ok =
      name
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
        %__MODULE__{backend: backend, gen_name: name, allocated_memory: allocated} = state
      ) do
    {:reply, {memory_info(backend, name), allocated}, state}
  end

  @impl true
  def handle_info(
        :heartbeat,
        %__MODULE__{
          name: name,
          gc_interval: time_interval,
          gc_heartbeat_ref: ref,
          gen_index: gen_index,
          backend: backend,
          backend_opts: backend_opts
        } = state
      ) do
    {gen_name, gen_index} = new_gen(name, gen_index, backend, backend_opts)

    state = %{
      state
      | gen_name: gen_name,
        gen_index: gen_index,
        gc_heartbeat_ref: start_timer(time_interval, ref)
    }

    {:noreply, state}
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
           gen_name: gen_name,
           max_size: max_size,
           backend: backend
         } = state
       )
       when not is_nil(max_size) do
    gen_name
    |> backend.info(:size)
    |> maybe_cleanup(max_size, state)
  end

  defp check_size(state), do: state

  defp check_memory(
         %__MODULE__{
           gen_name: gen_name,
           backend: backend,
           allocated_memory: allocated
         } = state
       )
       when not is_nil(allocated) do
    backend
    |> memory_info(gen_name)
    |> maybe_cleanup(allocated, state)
  end

  defp check_memory(state), do: state

  defp maybe_cleanup(
         size,
         max_size,
         %__MODULE__{
           name: name,
           backend: backend,
           backend_opts: backend_opts,
           gen_index: index,
           gc_cleanup_max_timeout: max_timeout,
           gc_cleanup_ref: cleanup_ref,
           gc_interval: gc_interval,
           gc_heartbeat_ref: heartbeat_ref
         } = state
       )
       when size >= max_size do
    {gen_name, index} = new_gen(name, index, backend, backend_opts)

    %{
      state
      | gen_name: gen_name,
        gen_index: index,
        gc_cleanup_ref: start_timer(max_timeout, cleanup_ref, :cleanup),
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

  defp do_call(name, message) do
    name
    |> server_name()
    |> GenServer.call(message)
  end

  defp new_gen(name, gen_index, backend, backend_opts) do
    # get current generations
    older = :persistent_term.get({__MODULE__, name, :older}, nil)
    newer = :persistent_term.get({__MODULE__, name, :newer}, nil)

    # create new generation
    gen_name = normalize_module_name([name, Generation, gen_index])
    ^gen_name = backend.new(gen_name, backend_opts)

    # update generations
    :ok = :persistent_term.put({__MODULE__, name, :older}, newer)
    :ok = :persistent_term.put({__MODULE__, name, :newer}, gen_name)

    # maybe delete older generation
    _ = if not is_nil(older), do: backend.delete(older)

    # increment the generation index
    gen_index = if gen_index < 2, do: gen_index + 1, else: 0

    {gen_name, gen_index}
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

  defp memory_info(backend, name) do
    backend.info(name, :memory) * :erlang.system_info(:wordsize)
  end

  defp linear_inverse_backoff(size, max_size, min_timeout, max_timeout) do
    round((min_timeout - max_timeout) / max_size * size + max_timeout)
  end
end
