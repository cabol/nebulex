defmodule Nebulex.Cache.List do
  @moduledoc false

  @doc false
  def __api__ do
    [
      lpush: 4,
      rpush: 4,
      lpop: 3,
      rpop: 3,
      lrange: 5
    ]
  end

  @doc """
  Implementation for `Nebulex.Cache.lpush/3`.
  """
  def lpush(_cache, _key, [], _opts), do: 0

  def lpush(cache, key, values, opts) when is_list(values) do
    cache.__adapter__.lpush(cache, key, values, opts)
  end

  @doc """
  Implementation for `Nebulex.Cache.rpush/3`.
  """
  def rpush(_cache, _key, [], _opts), do: 0

  def rpush(cache, key, values, opts) when is_list(values) do
    cache.__adapter__.rpush(cache, key, values, opts)
  end

  @doc """
  Implementation for `Nebulex.Cache.lpop/2`.
  """
  def lpop(cache, key, opts) do
    cache.__adapter__.lpop(cache, key, opts)
  end

  @doc """
  Implementation for `Nebulex.Cache.rpop/2`.
  """
  def rpop(cache, key, opts) do
    cache.__adapter__.rpop(cache, key, opts)
  end

  @doc """
  Implementation for `Nebulex.Cache.lrange/4`.
  """
  def lrange(cache, key, offset, limit, opts) when offset >= 1 and limit >= 0 do
    cache.__adapter__.lrange(cache, key, offset, limit, opts)
  end

  def lrange(_cache, _key, offset, limit, _opts) do
    raise ArgumentError,
          "the offset must be >= 1 and limit >= 0, " <>
            "got: offset: #{inspect(offset)}, limit: #{inspect(limit)}"
  end
end
