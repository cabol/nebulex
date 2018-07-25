defmodule Nebulex.Cache.Bucket do
  @moduledoc false

  @doc """
  Implementation for `Nebulex.Cache.size/0`.
  """
  def size(cache) do
    cache.__adapter__.size(cache)
  end

  @doc """
  Implementation for `Nebulex.Cache.flush/0`.
  """
  def flush(cache) do
    cache.__adapter__.flush(cache)
  end

  @doc """
  Implementation for `Nebulex.Cache.keys/0`.
  """
  def keys(cache) do
    cache.__adapter__.keys(cache)
  end
end
