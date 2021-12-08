defmodule Nebulex.Adapters.PartitionedErrorTest do
  use ExUnit.Case, async: false
  use Nebulex.Cache.EntryErrorTest
  use Nebulex.Cache.EntryExpirationErrorTest

  import Nebulex.CacheCase

  alias Nebulex.TestCache.Partitioned

  setup_with_dynamic_cache(Partitioned, :partitioned_error_cache)
end
