defmodule Nebulex.Adapter.Storage do
  @moduledoc """
  Specifies the adapter cache storage API.

  This behaviour specifies all read/write functions applied to all
  cache entries.
  """

  @doc """
  Returns the total number of cached entries.

  See `c:Nebulex.Cache.size/0`.
  """
  @callback size(Nebulex.Adapter.adapter_meta()) :: integer

  @doc """
  Flushes the cache and returns the number of evicted keys.

  See `c:Nebulex.Cache.flush/0`.
  """
  @callback flush(Nebulex.Adapter.adapter_meta()) :: integer
end
