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

  @doc false
  def with_dynamic_cache(name, cache, callback) do
    default_dynamic_cache = cache.get_dynamic_cache()
    _ = cache.put_dynamic_cache(name)

    try do
      callback.()
    after
      cache.put_dynamic_cache(default_dynamic_cache)
    end
  end
end
