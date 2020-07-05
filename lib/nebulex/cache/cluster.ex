defmodule Nebulex.Cache.Cluster do
  # The module used by cache adapters for
  # distributed caching functionality.
  # TODO: Use pg when depending on Erlang/OTP 23+, since the pg2 module is
  #       deprecated as of OTP 23 and scheduled for removal in OTP 24.
  #       Nebulex v2 will support both.
  @moduledoc false

  @doc """
  Joins the node where the cache `name`'s supervisor process is running to the
  `name`'s node group.
  """
  @spec join(name :: atom) :: :ok
  def join(name) do
    namespace = ensure_namespace(name)
    pid = Process.whereis(name) || self()

    if pid in :pg2.get_members(namespace) do
      :ok
    else
      :ok = :pg2.join(namespace, pid)
    end
  end

  @doc """
  Makes the node where the cache `name`'s supervisor process is running, leave
  the `name`'s node group.
  """
  @spec leave(name :: atom) :: :ok
  def leave(name) do
    name
    |> ensure_namespace()
    |> :pg2.leave(Process.whereis(name) || self())
  end

  @doc """
  Returns the list of nodes joined to given `name`'s node group.
  """
  @spec get_nodes(name :: atom) :: [node]
  def get_nodes(name) do
    name
    |> ensure_namespace()
    |> :pg2.get_members()
    |> Enum.map(&node(&1))
    |> :lists.usort()
  end

  @doc """
  Selects only one node based on the `keyslot` computation of the `key`.
  """
  @spec get_node(name :: atom, Nebulex.Cache.key(), module) :: node
  def get_node(name, key, module) do
    nodes = get_nodes(name)
    index = module.keyslot(key, length(nodes))
    Enum.at(nodes, index)
  end

  ## Private Functions

  defp ensure_namespace(name) do
    namespace = namespace(name)
    :ok = :pg2.create(namespace)
    namespace
  end

  defp namespace(name), do: {:nebulex, name}
end
