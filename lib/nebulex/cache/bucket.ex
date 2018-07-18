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

  @doc """
  Implementation for `Nebulex.Cache.reduce/3`.
  """
  def reduce(cache, acc, fun, opts) do
    cache.__adapter__.reduce(cache, acc, fun, opts)
  end

  @doc """
  Implementation for `Nebulex.Cache.to_map/1`.
  """
  def to_map(cache, opts) do
    cache.__adapter__.to_map(cache, opts)
  end
end
