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

  These options are configured via the built-in local adapter
  (`Nebulex.Adapters.Local`):

    * `:generations` - Max number of Cache generations. Defaults to `2`
      (normally two generations is enough).

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
    :cache,
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

  alias Nebulex.Adapters.Local.Metadata

  ## API

  @doc """
  Starts the garbage collector for the build-in local cache adapter.
  """
  @spec start_link(Nebulex.Cache.t(), Nebulex.Cache.opts()) :: GenServer.on_start()
  def start_link(cache, opts \\ []) do
    GenServer.start_link(__MODULE__, {cache, opts}, name: server_name(cache))
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
  @spec new(Nebulex.Cache.t(), Nebulex.Cache.opts()) :: [atom]
  def new(cache, opts \\ []) do
    do_call(cache, {:new_generation, opts})
  end

  @doc """
  Flushes the cache (including all its generations).

  ## Example

      Nebulex.Adapters.Local.Generation.flush(MyCache)
  """
  @spec flush(Nebulex.Cache.t()) :: integer
  def flush(cache) do
    do_call(cache, :flush)
  end

  @doc """
  Reallocates the block of memory that was previously allocated for the given
  `cache` with the new `size`. In other words, reallocates the max memory size
  for a cache generation.

  ## Example

      Nebulex.Adapters.Local.Generation.realloc(MyCache, 1_000_000)
  """
  @spec realloc(Nebulex.Cache.t(), pos_integer) :: :ok
  def realloc(cache, size) do
    do_call(cache, {:realloc, size})
  end

  @doc """
  Returns the memory info in a tuple `{used_mem, total_mem}`.

  ## Example

      Nebulex.Adapters.Local.Generation.memory_info(MyCache)
  """
  @spec memory_info(Nebulex.Cache.t()) ::
          {used_mem :: non_neg_integer, total_mem :: non_neg_integer}
  def memory_info(cache) do
    do_call(cache, :memory_info)
  end

  @doc """
  Returns the name of the GC server for the given `cache`.

  ## Example

      Nebulex.Adapters.Local.Generation.server_name(MyCache)
  """
  def server_name(cache), do: Module.concat(cache, Generation)

  ## GenServer Callbacks

  @impl true
  def init({cache, opts}) do
    _ = init_metadata(cache, opts)

    # backend options for creating new tables
    backend_opts = Keyword.get(opts, :backend_opts, [])

    # memory check options
    max_size = get_option(opts, :max_size, &(is_integer(&1) and &1 > 0))
    allocated_memory = get_option(opts, :allocated_memory, &(is_integer(&1) and &1 > 0))
    cleanup_min = get_option(opts, :gc_cleanup_min_timeout, &(is_integer(&1) and &1 > 0), 30_000)
    cleanup_max = get_option(opts, :gc_cleanup_max_timeout, &(is_integer(&1) and &1 > 0), 300_000)
    gc_cleanup_ref = if max_size || allocated_memory, do: start_timer(cleanup_max, nil, :cleanup)

    # GC options
    {{gen_name, gen_index, _}, ref} =
      if gc_interval = get_option(opts, :gc_interval, &(is_integer(&1) and &1 > 0)),
        do: {new_gen(cache, 0, backend_opts), start_timer(gc_interval)},
        else: {new_gen(cache, 0, backend_opts), nil}

    init_state = %__MODULE__{
      cache: cache,
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
  def handle_call(
        {:new_generation, opts},
        _from,
        %__MODULE__{cache: cache, gen_index: gen_index, backend_opts: backend_opts} = state
      ) do
    {gen_name, gen_index, metadata} = new_gen(cache, gen_index, backend_opts)

    ref =
      opts
      |> get_option(:reset_timer, &is_boolean/1, true, & &1)
      |> maybe_reset_timer(state)

    state = %{state | gen_name: gen_name, gen_index: gen_index, gc_heartbeat_ref: ref}
    {:reply, metadata.generations, state}
  end

  def handle_call(:flush, _from, %__MODULE__{cache: cache} = state) do
    size = cache.__adapter__.size(cache)

    :ok =
      Enum.each(
        cache.__metadata__.generations,
        &cache.__backend__.delete_all_objects(&1)
      )

    {:reply, size, state}
  end

  def handle_call({:realloc, mem_size}, _from, %__MODULE__{} = state) do
    {:reply, :ok, %{state | allocated_memory: mem_size}}
  end

  def handle_call(
        :memory_info,
        _from,
        %__MODULE__{cache: cache, gen_name: name, allocated_memory: allocated} = state
      ) do
    {:reply, {memory_info(cache, name), allocated}, state}
  end

  @impl true
  def handle_info(
        :heartbeat,
        %__MODULE__{
          cache: cache,
          gc_interval: time_interval,
          gc_heartbeat_ref: ref,
          gen_index: gen_index,
          backend_opts: backend_opts
        } = state
      ) do
    {gen_name, gen_index, _} = new_gen(cache, gen_index, backend_opts)

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

  defp check_size(
         %__MODULE__{
           gen_name: name,
           cache: cache,
           max_size: max_size
         } = state
       )
       when not is_nil(max_size) do
    name
    |> cache.__backend__.info(:size)
    |> maybe_cleanup(max_size, state)
  end

  defp check_size(state), do: state

  defp check_memory(
         %__MODULE__{
           gen_name: name,
           cache: cache,
           allocated_memory: allocated
         } = state
       )
       when not is_nil(allocated) do
    cache
    |> memory_info(name)
    |> maybe_cleanup(allocated, state)
  end

  defp check_memory(state), do: state

  defp maybe_cleanup(
         size,
         max_size,
         %__MODULE__{
           gen_index: index,
           cache: cache,
           backend_opts: backend_opts,
           gc_cleanup_max_timeout: max_timeout,
           gc_cleanup_ref: cleanup_ref,
           gc_interval: gc_interval,
           gc_heartbeat_ref: heartbeat_ref
         } = state
       )
       when size >= max_size do
    {name, index, _} = new_gen(cache, index, backend_opts)

    %{
      state
      | gen_name: name,
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

  defp do_call(cache, message) do
    cache
    |> server_name()
    |> GenServer.call(message)
  end

  defp init_metadata(cache, opts) do
    max_generations = get_option(opts, :generations, &is_integer/1, 2)
    Metadata.create(cache, %Metadata{max_generations: max_generations})
  end

  defp new_gen(cache, gen_index, backend_opts) do
    gen_name = Module.concat(cache, "." <> Integer.to_string(gen_index))

    metadata =
      gen_name
      |> cache.__backend__.new(backend_opts)
      |> Metadata.push_generation(cache)

    gen_index =
      if gen_index < metadata.max_generations,
        do: gen_index + 1,
        else: 0

    {gen_name, gen_index, metadata}
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

  defp memory_info(cache, name) do
    cache.__backend__.info(name, :memory) * :erlang.system_info(:wordsize)
  end

  defp linear_inverse_backoff(size, max_size, min_timeout, max_timeout) do
    round((min_timeout - max_timeout) / max_size * size + max_timeout)
  end
end
