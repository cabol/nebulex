defmodule Nebulex.Cache.Stats do
  @moduledoc false

  use GenServer

  ## API

  @spec start_link(Nebulex.Cache.t) :: GenServer.on_start
  def start_link(cache) do
    name = server_name(cache)
    GenServer.start_link(__MODULE__, {name, cache}, name: name)
  end

  @spec child_spec(Nebulex.Cache.t) :: :supervisor.child_spec()
  def child_spec(cache) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [cache]}
    }
  end

  @spec get_counter(Nebulex.Cache.t, atom) :: integer
  def get_counter(cache, action) when is_atom(action) do
    cache
    |> server_name
    |> :ets.lookup_element(action, 2)
  end

  @spec get_counters(Nebulex.Cache.t) :: Keyword.t
  def get_counters(cache) do
    cache
    |> server_name
    |> :ets.select([{{:"$1", :"$2"}, [], [{{:"$1", :"$2"}}]}])
  end

  @spec incr_counter(Nebulex.Cache.t, atom) :: integer
  def incr_counter(cache, action) when is_atom(action) do
    cache
    |> server_name
    |> :ets.update_counter(action, 1, {action, 0})
  end

  @spec reset_counter(Nebulex.Cache.t, atom) :: boolean
  def reset_counter(cache, action) when is_atom(action) do
    cache
    |> server_name
    |> :ets.update_element(action, {2, 0})
  end

  @spec reset_counters(Nebulex.Cache.t) :: :ok
  def reset_counters(cache) do
    :ets.foldl(fn({counter, _}, acc) ->
      true = reset_counter(cache, counter)
      acc
    end, :ok, server_name(cache))
  end

  ## Post Hook

  @doc false
  def post_hook(nil, {cache, :get, _args}) do
    _ = incr_counter(cache, :get_miss_count)
    nil
  end

  def post_hook(result, {cache, action, _args}) do
    _ = incr_counter(cache, action)
    result
  end

  ## GenServer Callbacks

  @impl true
  def init({name, cache}) do
    ^name =
      :ets.new(name, [
        :named_table,
        :public,
        read_concurrency: true,
        write_concurrency: true
      ])

    {:ok, %{name: name, cache: cache}}
  end

  ## Private Functions

  defp server_name(cache), do: Module.concat([cache, Stats])
end
