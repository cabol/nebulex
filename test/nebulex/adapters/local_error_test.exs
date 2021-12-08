defmodule Nebulex.Adapters.LocalErrorTest do
  use ExUnit.Case, async: false
  use Nebulex.Cache.EntryErrorTest
  use Nebulex.Cache.EntryExpirationErrorTest

  import Nebulex.CacheCase

  alias Nebulex.TestCache.Cache

  setup_with_dynamic_cache(Cache, :local_error_cache)
end
