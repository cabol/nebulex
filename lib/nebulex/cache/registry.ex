defmodule Nebulex.Cache.Registry do
  @moduledoc false

  use GenServer

  ## API

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @spec register(pid(), atom(), any()) :: :ok
  def register(pid, name, value) when is_pid(pid) and is_atom(name) do
    GenServer.call(__MODULE__, {:register, pid, name, value})
  end

  @spec lookup(atom() | pid()) :: any()
  def lookup(name_or_pid)

  def lookup(name) when is_atom(name) do
    if pid = GenServer.whereis(name) do
      lookup(pid)
    else
      raise Nebulex.CacheNotFoundError, cache: name
    end
  end

  def lookup(pid) when is_pid(pid) do
    case :persistent_term.get({__MODULE__, pid}, nil) do
      {_ref, _name, value} -> value
      nil -> raise Nebulex.CacheNotFoundError, cache: pid
    end
  end

  @spec all_running() :: [atom() | pid()]
  def all_running do
    for {{__MODULE__, pid}, {_ref, name, _value}} <- :persistent_term.get() do
      name || pid
    end
  end

  ## GenServer Callbacks

  @impl true
  def init(:ok) do
    {:ok, nil}
  end

  @impl true
  def handle_call({:register, pid, name, value}, _from, state) do
    # Monitor the process so that when it is down it can be removed
    ref = Process.monitor(pid)

    # Store the process data
    :ok = :persistent_term.put({__MODULE__, pid}, {ref, name, value})

    # Reply with success
    {:reply, :ok, state}
  end

  @impl true
  def handle_info({:DOWN, ref, _type, pid, _reason}, state) do
    # Check the process reference
    {^ref, _, _} = :persistent_term.get({__MODULE__, pid})

    # Remove the process data
    _ = :persistent_term.erase({__MODULE__, pid})

    # Move on
    {:noreply, state}
  end
end
