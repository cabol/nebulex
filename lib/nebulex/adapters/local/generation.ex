defmodule Nebulex.Adapters.Local.Generation do
  @moduledoc """
  Generations Handler. This GenServer acts as garbage collector, everytime
  it runs, a new cache generation is created a the oldest one is deleted.

  The only way to create new generations is through this module (this
  server is the metadata owner) calling `new/2` function. When a Cache
  is created, a generations handler associated to that Cache is started
  at the same time, therefore, this server MUST NOT be started directly.

  ## Options

  * `:gc_interval` - Interval time in seconds to garbage collection to run,
    delete the oldest generation and create a new one. If this option is
    not set, garbage collection is never executed, so new generations
    must be created explicitly, e.g.: `new(cache, [])`.
  """

  use GenServer

  alias Nebulex.Adapters.Local.Metadata
  alias :shards_local, as: Local

  ## API

  @doc false
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

      new_generation(MyCache, reset_timeout: :false)
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

      flush(MyCache)
  """
  @spec flush(Nebulex.Cache.t()) :: :ok
  def flush(cache) do
    cache
    |> server_name()
    |> GenServer.call(:flush)
  end

  ## GenServer Callbacks

  @impl true
  def init({cache, opts}) do
    _ = init_metadata(cache, opts)

    {{_, gen_index}, ref} =
      if gc_interval = opts[:gc_interval],
        do: {new_gen(cache, 0), start_timer(gc_interval)},
        else: {new_gen(cache, 0), nil}

    {:ok, %{cache: cache, gc_interval: gc_interval, time_ref: ref, gen_index: gen_index}}
  end

  @impl true
  def handle_call({:new_generation, opts}, _from, %{cache: cache, gen_index: gen_index} = state) do
    {generations, gen_index} = new_gen(cache, gen_index)

    state =
      opts
      |> Keyword.get(:reset_timeout, true)
      |> maybe_reset_timeout(state)

    {:reply, generations, %{state | gen_index: gen_index}}
  end

  def handle_call(:flush, _from, %{cache: cache} = state) do
    {:reply, do_flush(cache), %{state | gen_index: 0}}
  end

  @impl true
  def handle_info(:timeout, %{cache: cache, gc_interval: time, gen_index: gen_index} = state) do
    {_, gen_index} = new_gen(cache, gen_index)
    {:noreply, %{state | gen_index: gen_index, time_ref: start_timer(time)}}
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
    gens =
      "#{cache}.#{gen_index}"
      |> String.to_existing_atom()
      |> Local.new(cache.__tab_opts__)
      |> Metadata.new_generation(cache)
      |> maybe_delete_gen()

    {gens, incr_gen_index(cache, gen_index)}
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

  defp maybe_reset_timeout(true, %{gc_interval: time, time_ref: ref} = state) do
    {:ok, :cancel} = :timer.cancel(ref)
    %{state | time_ref: start_timer(time)}
  end

  defp do_flush(cache) do
    :ok = Enum.each(cache.__metadata__.generations, &Local.delete/1)
    _ = Metadata.update(%{cache.__metadata__ | generations: []}, cache)
    :ok
  end
end
