defmodule Nebulex.Cache.Cluster do
  # The module used by cache adapters for
  # distributed caching functionality.
  @moduledoc false

  @doc """
  Joins the node where the cache `name`'s supervisor process is running to the
  `name`'s node group.
  """
  @spec join(name :: atom) :: :ok
  def join(name) do
    pid = Process.whereis(name) || self()

    if pid in pg_members(name) do
      :ok
    else
      :ok = pg_join(name, pid)
    end
  end

  @doc """
  Makes the node where the cache `name`'s supervisor process is running, leave
  the `name`'s node group.
  """
  @spec leave(name :: atom) :: :ok
  def leave(name) do
    pg_leave(name, Process.whereis(name) || self())
  end

  @doc """
  Returns the list of nodes joined to given `name`'s node group.
  """
  @spec get_nodes(name :: atom) :: [node]
  def get_nodes(name) do
    name
    |> pg_members()
    |> Enum.map(&node(&1))
    |> :lists.usort()
  end

  @doc """
  Selects one node based on the computation of the `key` slot.
  """
  @spec get_node(name :: atom, Nebulex.Cache.key(), keyslot :: module) :: node
  def get_node(name, key, keyslot) do
    nodes = get_nodes(name)
    index = keyslot.hash_slot(key, length(nodes))
    Enum.at(nodes, index)
  end

  ## PG

  if Code.ensure_loaded?(:pg) do
    defp pg_join(name, pid) do
      :ok = :pg.join(__MODULE__, name, pid)
    end

    defp pg_leave(name, pid) do
      :ok = :pg.leave(__MODULE__, name, pid)
    end

    defp pg_members(name) do
      :pg.get_members(__MODULE__, name)
    end
  else
    @compile {:inline, pg2_namespace: 1}

    defp pg_join(name, pid) do
      name
      |> ensure_namespace()
      |> :pg2.join(pid)
    end

    defp pg_leave(name, pid) do
      name
      |> ensure_namespace()
      |> :pg2.leave(pid)
    end

    defp pg_members(name) do
      name
      |> ensure_namespace()
      |> :pg2.get_members()
    end

    defp ensure_namespace(name) do
      namespace = pg2_namespace(name)
      :ok = :pg2.create(namespace)
      namespace
    end

    defp pg2_namespace(name), do: {:nbx, name}
  end
end
