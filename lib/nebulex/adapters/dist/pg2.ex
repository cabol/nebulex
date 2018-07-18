defmodule Nebulex.Adapters.Dist.PG2 do
  # The module invoked by cache modules for
  # distributed caching related functionality.
  @moduledoc false

  @doc """
  Joins the node where `cache`'s supervisor process is running to the
  `cache`'s node group.
  """
  @spec join(Nebulex.Cache.t()) :: :ok
  def join(cache) do
    namespace = ensure_namespace(cache)
    pid = Process.whereis(cache)

    if pid in :pg2.get_members(namespace) do
      :ok
    else
      :ok = :pg2.join(namespace, pid)
    end
  end

  @doc """
  Makes the node where `cache`'s supervisor process is running, leave the
  `cache`'s node group.
  """
  @spec leave(Nebulex.Cache.t()) :: :ok
  def leave(cache) do
    cache
    |> ensure_namespace()
    |> :pg2.leave(Process.whereis(cache))
  end

  @doc """
  Returns the list of nodes joined to given `cache`'s node group.
  """
  @spec get_nodes(Nebulex.Cache.t()) :: [node]
  def get_nodes(cache) do
    cache
    |> ensure_namespace()
    |> :pg2.get_members()
    |> Enum.map(&node(&1))
    |> :lists.usort
  end

  ## Private Functions

  defp ensure_namespace(cache) do
    namespace = namespace(cache)
    :ok = :pg2.create(namespace)
    namespace
  end

  defp namespace(cache), do: {:nebulex, cache}
end
