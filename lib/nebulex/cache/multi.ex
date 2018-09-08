defmodule Nebulex.Cache.Multi do
  @moduledoc false

  alias Nebulex.Object

  @doc """
  Implementation for `Nebulex.Cache.mget/2`.
  """
  def mget(_cache, [], _opts), do: %{}

  def mget(cache, keys, opts) do
    objects_map = cache.__adapter__.mget(cache, keys, opts)

    case opts[:return] do
      :object ->
        objects_map

      _ ->
        Enum.reduce(objects_map, %{}, fn {key, obj}, acc ->
          Map.put(acc, key, Nebulex.Cache.Object.return(obj, opts))
        end)
    end
  end

  @doc """
  Implementation for `Nebulex.Cache.mset/2`.
  """
  def mset(_cache, [], _opts), do: :ok
  def mset(_cache, entries, _opts) when map_size(entries) == 0, do: :ok

  def mset(cache, entries, opts) do
    objects =
      for {key, value} <- entries, value != nil do
        %Object{key: key, value: value}
      end

    cache.__adapter__.mset(cache, objects, opts)
  end
end
