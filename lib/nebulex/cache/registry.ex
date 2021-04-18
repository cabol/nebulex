defmodule Nebulex.Cache.Registry do
  @moduledoc false

  use GenServer

  ## API

  @spec start_link(Keyword.t()) :: GenServer.on_start()
  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @spec register(pid, term) :: :ok
  def register(pid, value) when is_pid(pid) do
    GenServer.call(__MODULE__, {:register, pid, value})
  end

  @spec lookup(atom | pid) :: term
  def lookup(name) when is_atom(name) do
    name
    |> GenServer.whereis()
    |> Kernel.||(raise Nebulex.RegistryLookupError, name: name)
    |> lookup()
  end

  def lookup(pid) when is_pid(pid) do
    {_ref, value} = :persistent_term.get({__MODULE__, pid})
    value
  end

  ## GenServer Callbacks

  @impl true
  def init(:ok) do
    {:ok, :ok}
  end

  @impl true
  def handle_call({:register, pid, value}, _from, state) do
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
