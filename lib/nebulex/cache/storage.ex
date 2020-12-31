defmodule Nebulex.Cache.Storage do
  @moduledoc false

  alias Nebulex.Adapter

  @doc """
  Implementation for `c:Nebulex.Cache.size/0`.
  """
  def size(name) do
    Adapter.with_meta(name, & &1.size(&2))
  end

  @doc """
  Implementation for `c:Nebulex.Cache.flush/0`.
  """
  def flush(name) do
    Adapter.with_meta(name, & &1.flush(&2))
  end
end
