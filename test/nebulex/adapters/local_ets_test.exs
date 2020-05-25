defmodule Nebulex.Adapters.LocalEtsTest do
  use ExUnit.Case, async: true
  use Nebulex.LocalTest
  use Nebulex.CacheTest

  import Nebulex.TestCase

  alias Nebulex.Adapter
  alias Nebulex.TestCache.Cache

  setup_with_dynamic_cache(Cache, :local_with_ets)

  describe "ets" do
    test "backend", %{name: name} do
      Adapter.with_meta(name, fn _, meta ->
        assert meta.backend == :ets
      end)
    end
  end
end
