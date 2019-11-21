defmodule Nebulex.Cache.Persistence do
  @moduledoc false

  @doc """
  Implementation for `c:Nebulex.Cache.dump/2`.
  """
  def dump(cache, path, opts) do
    cache.__adapter__.dump(cache, path, opts)
  end

  @doc """
  Implementation for `c:Nebulex.Cache.load/2`.
  """
  def load(cache, path, opts) do
    cache.__adapter__.load(cache, path, opts)
  end
end
