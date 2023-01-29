defmodule Nebulex.Adapters.LocalEtsTest do
  use ExUnit.Case, async: true

  # Inherit tests
  use Nebulex.LocalTest
  use Nebulex.CacheTest

  import Nebulex.CacheCase, only: [setup_with_dynamic_cache: 3]

  alias Nebulex.Adapter
  alias Nebulex.TestCache.Cache

  setup_with_dynamic_cache Cache, :local_with_ets, purge_chunk_size: 10

  describe "ets" do
    test "backend", %{name: name} do
      Adapter.with_meta(name, fn meta ->
        assert meta.backend == :ets
      end)
    end
  end
end
