defmodule Nebulex.Adapters.CacheTest do
  use ExUnit.Case, async: true

  # Cache API test cases
  use Nebulex.CacheTestCase

  import Nebulex.CacheCase, only: [setup_with_dynamic_cache: 2]

  setup_with_dynamic_cache Nebulex.TestCache.Cache, :test_cache_local
end
