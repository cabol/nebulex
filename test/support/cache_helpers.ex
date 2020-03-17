defmodule Nebulex.CacheHelpers do
  @moduledoc false

  ## API

  @doc false
  def cache_put(cache, lst, fun \\ & &1, opts \\ []) do
    for key <- lst do
      value = fun.(key)
      :ok = cache.put(key, value, opts)
      value
    end
  end
end
