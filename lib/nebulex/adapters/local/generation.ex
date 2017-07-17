defmodule Nebulex.Adapters.Local.Generation do
  @moduledoc """
  Generations Handler. This GenServer acts as garbage collector, everytime
  it runs, a new cache generation is created a the oldest one is deleted.

  The only way to create new generations is through this module (this
  server is the metadata owner) calling `new/2` function. When a Cache
  is created, a generations handler associated to that Cache is started
  as well, therefore, this server MUST NOT be started directly.

  See `Nebulex.Adapters.Local.children/2`.

  ## Options

  * `:gc_interval` - Interval time in seconds to garbage collection to run,
    delete the oldest generation and create a new one. If this option is
    not set, garbage collection is never executed, so new generations
    must be created explicitly, e.g.: `new(cache, [])`.
  """

  use GenServer

  alias ExShards.Local
  alias Nebulex.Adapters.Local.Metadata

  ## API

  @doc false
  @spec start_link(Nebulex.Cache.t, Nebulex.Cache.opts) :: GenServer.on_start
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
  @spec new(Nebulex.Cache.t, Nebulex.Cache.opts) :: [atom]
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
  @spec flush(Nebulex.Cache.t) :: :ok
  def flush(cache) do
    cache
    |> server_name()
    |> GenServer.call(:flush)
  end

  ## GenServer Callbacks

  @doc false
  def init({cache, opts}) do
    :ok = init_metadata(cache, opts)

    ref =
      if gc_interval = opts[:gc_interval] do
        _ = new_gen(cache)
        start_timer(gc_interval)
      end

    {:ok, %{cache: cache, gc_interval: gc_interval, time_ref: ref}}
  end

  @doc false
  def handle_call({:new_generation, opts}, _from, %{cache: cache} = state) do
    gen_list = new_gen(cache)
    state =
      opts
      |> Keyword.get(:reset_timeout, true)
      |> maybe_reset_timeout(state)

    {:reply, gen_list, state}
  end

  @doc false
  def handle_call(:flush, _from, %{cache: cache} = state) do
    {:reply, do_flush(cache), state}
  end

  @doc false
  def handle_info(:timeout, %{cache: cache, gc_interval: time} = state) do
    _ = new_gen(cache)
    ref = start_timer(time)

    {:noreply, %{state | time_ref: ref}}
  end

  ## Private Functions

  defp server_name(cache), do: Module.concat([cache, Generation])

  defp init_metadata(cache, opts) do
    n_gens = Keyword.get(opts, :n_generations, 2)
    _ = Metadata.create(cache, %Metadata{n_generations: n_gens})
    :ok
  end

  defp new_gen(cache) do
    "#{cache}.#{:erlang.phash2(:os.timestamp)}"
    |> String.to_atom()
    |> Local.new(cache.__tab_opts__)
    |> Metadata.new_generation(cache)
    |> maybe_delete_gen()
  end

  defp maybe_delete_gen({generations, nil}),
    do: generations
  defp maybe_delete_gen({generations, dropped_gen}) do
    _ = Local.delete(dropped_gen)
    generations
  end

  defp start_timer(time) do
    {:ok, ref} = :timer.send_after(time * 1000, :timeout)
    ref
  end

  defp maybe_reset_timeout(_, %{gc_interval: nil} = state),
    do: state
  defp maybe_reset_timeout(false, state),
    do: state
  defp maybe_reset_timeout(true, %{gc_interval: time, time_ref: ref} = state) do
    {:ok, :cancel} = :timer.cancel(ref)
    %{state | time_ref: start_timer(time)}
  end

  defp do_flush(cache) do
    _ = Metadata.update(%{cache.__metadata__ | generations: []}, cache)
    Enum.each(cache.__metadata__.generations, &Local.delete/1)
  end
end
