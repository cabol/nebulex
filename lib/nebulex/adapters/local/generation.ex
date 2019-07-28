defmodule Nebulex.Adapters.Local.Generation do
  @moduledoc """
  Generations Handler. This GenServer acts as garbage collector, everytime
  it runs, a new cache generation is created a the oldest one is deleted.

  The only way to create new generations is through this module (this
  server is the metadata owner) calling `new/2` function. When a Cache
  is created, a generations handler associated to that Cache is started
  at the same time, therefore, this server MUST NOT be started directly.

  ## Options

  These options are configured via the built-in local adapter
  (`Nebulex.Adapters.Local`):

  * `:gc_interval` - Interval time in seconds to garbage collection to run,
    delete the oldest generation and create a new one. If this option is
    not set, garbage collection is never executed, so new generations
    must be created explicitly, e.g.: `new(cache, [])`.

  * `:generation_size` - Max size in bytes for a cache generation. If this
    option is set and the configured value is reached, a new generation is
    created so the oldest is deleted and force releasing memory space.
    If it is not set (`nil`), the cleanup check to release memory is not
    performed (the default).

  * `:gc_cleanup_interval` - The number of writes needed to run the cleanup
    check. Once this value is reached and only if `generation_size` option
    is set, the cleanup check is performed. Defaults to `10`, so after 10
    write operations the cleanup check is performed.
  """

  use GenServer

  alias Nebulex.Adapters.Local.Metadata
  alias :shards_local, as: Local

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
  deleted

    * `cache` - Cache Module
    * `opts` - List of options

  ## Options

    * `:reset_timeout` - Indicates if the poll frequency time-out should
      be reset or not (default: true).

  ## Example

      Nebulex.Adapters.Local.Generation.new(MyCache, reset_timeout: :false)
  """
  @spec new(Nebulex.Cache.t(), Nebulex.Cache.opts()) :: [atom]
  def new(cache, opts \\ []) do
    cache
    |> server_name()
    |> GenServer.call({:new_generation, opts})
  end

  @doc """
  Flushes the cache (including all its generations).

    * `cache` - Cache Module

  ## Example

      Nebulex.Adapters.Local.Generation.flush(MyCache)
  """
  @spec flush(Nebulex.Cache.t()) :: :ok
  def flush(cache) do
    cache
    |> server_name()
    |> GenServer.call(:flush)
  end

  @doc """
  Triggers the cleanup process to check whether or not the max generation size
  has been reached. If so, a new generation is pushed in order to release memory
  and keep it within the configured limit.

    * `cache` - Cache Module

  ## Example

      Nebulex.Adapters.Local.Generation.cleanup(MyCache)
  """
  @spec cleanup(Nebulex.Cache.t()) :: :ok
  def cleanup(cache) do
    cache
    |> server_name()
    |> GenServer.cast(:cleanup)
  end

  ## GenServer Callbacks

  @impl true
  def init({cache, opts}) do
    _ = init_metadata(cache, opts)

    {{_, gen_name, gen_index}, ref} =
      if gc_interval = opts[:gc_interval],
        do: {new_gen(cache, 0), start_timer(gc_interval)},
        else: {new_gen(cache, 0), nil}

    init_state = %{
      cache: cache,
      gc_interval: gc_interval,
      time_ref: ref,
      gen_name: gen_name,
      gen_index: gen_index,
      generation_size: Keyword.get(opts, :generation_size),
      gc_cleanup_interval: Keyword.get(opts, :gc_cleanup_interval, 10),
      gc_cleanup_counts: 1
    }

    {:ok, init_state}
  end

  @impl true
  def handle_call({:new_generation, opts}, _from, %{cache: cache, gen_index: gen_index} = state) do
    {generations, gen_name, gen_index} = new_gen(cache, gen_index)

    state =
      opts
      |> Keyword.get(:reset_timeout, true)
      |> maybe_reset_timeout(state)

    {:reply, generations, %{state | gen_name: gen_name, gen_index: gen_index}}
  end

  def handle_call(:flush, _from, %{cache: cache} = state) do
    :ok = Enum.each(cache.__metadata__.generations, &Local.delete_all_objects/1)
    {:reply, :ok, state}
  end

  @impl true
  def handle_cast(
        :cleanup,
        %{
          gen_name: name,
          gen_index: index,
          cache: cache,
          generation_size: max_size,
          gc_cleanup_interval: cleanup_interval,
          gc_cleanup_counts: cleanup_counts
        } = state
      )
      when cleanup_counts >= cleanup_interval do
    if Local.info(name, :memory) * :erlang.system_info(:wordsize) >= max_size do
      {_, name, index} = new_gen(cache, index)
      {:noreply, %{reset_timeout(state) | gc_cleanup_counts: 1, gen_name: name, gen_index: index}}
    else
      {:noreply, %{state | gc_cleanup_counts: 1}}
    end
  end

  def handle_cast(:cleanup, %{gc_cleanup_counts: counts} = state) do
    {:noreply, %{state | gc_cleanup_counts: counts + 1}}
  end

  @impl true
  def handle_info(:timeout, %{cache: cache, gc_interval: time, gen_index: gen_index} = state) do
    {_, gen_name, gen_index} = new_gen(cache, gen_index)
    {:noreply, %{state | gen_name: gen_name, gen_index: gen_index, time_ref: start_timer(time)}}
  end

  ## Private Functions

  defp server_name(cache), do: Module.concat([cache, Generation])

  defp init_metadata(cache, opts) do
    n_gens = Keyword.get(opts, :n_generations, 2)

    cache
    |> Metadata.create(%Metadata{n_generations: n_gens})
    |> init_indexes(cache)
  end

  defp init_indexes(metadata, cache) do
    :ok = Enum.each(0..metadata.n_generations, &String.to_atom("#{cache}.#{&1}"))
    metadata
  end

  defp new_gen(cache, gen_index) do
    gen_name = String.to_existing_atom("#{cache}.#{gen_index}")

    gens =
      gen_name
      |> Local.new(cache.__tab_opts__)
      |> Metadata.new_generation(cache)
      |> maybe_delete_gen()

    {gens, gen_name, incr_gen_index(cache, gen_index)}
  end

  defp maybe_delete_gen({generations, nil}), do: generations

  defp maybe_delete_gen({generations, dropped_gen}) do
    _ = Local.delete(dropped_gen)
    generations
  end

  defp incr_gen_index(cache, gen_index) do
    if gen_index < cache.__metadata__.n_generations, do: gen_index + 1, else: 0
  end

  defp start_timer(time) do
    {:ok, ref} = :timer.send_after(time * 1000, :timeout)
    ref
  end

  defp maybe_reset_timeout(_, %{gc_interval: nil} = state), do: state
  defp maybe_reset_timeout(false, state), do: state
  defp maybe_reset_timeout(true, state), do: reset_timeout(state)

  defp reset_timeout(%{gc_interval: time, time_ref: ref} = state) do
    {:ok, :cancel} = :timer.cancel(ref)
    %{state | time_ref: start_timer(time)}
  end
end
