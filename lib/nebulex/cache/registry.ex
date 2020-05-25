defmodule Nebulex.Cache.Registry do
  @moduledoc false

  use GenServer

  ## API

  @spec start_link(Keyword.t()) :: GenServer.on_start()
  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @spec associate(pid, term) :: :ok
  def associate(pid, value) when is_pid(pid) do
    GenServer.call(__MODULE__, {:associate, pid, value})
  end

  @spec lookup(atom | pid) :: term
  def lookup(name) when is_atom(name) do
    name
    |> GenServer.whereis()
    |> Kernel.||(
      raise "could not lookup Nebulex cache #{inspect(name)} because it was " <>
              "not started or it does not exist"
    )
    |> lookup()
  end

  def lookup(pid) when is_pid(pid) do
    {__MODULE__, pid}
    |> :persistent_term.get({nil, nil})
    |> elem(1)
  end

  ## GenServer Callbacks

  @impl true
  def init(:ok) do
    {:ok, :ok}
  end

  @impl true
  def handle_call({:associate, pid, value}, _from, state) do
    ref = Process.monitor(pid)
    :ok = :persistent_term.put({__MODULE__, pid}, {ref, value})
    {:reply, :ok, state}
  end

  @impl true
  def handle_info({:DOWN, ref, _type, pid, _reason}, state) do
    {^ref, _} = :persistent_term.get({__MODULE__, pid})
    _ = :persistent_term.erase({__MODULE__, pid})
    {:noreply, state}
  end
end
