defmodule Nebulex.Cache.KVExpirationErrorTest do
  import Nebulex.CacheCase

  deftests do
    describe "expire!/2" do
      test "raises an error", %{cache: cache} do
        assert_raise Nebulex.Error, fn ->
          cache.expire!(:raise, 100)
        end
      end
    end

    describe "touch!/1" do
      test "raises an error", %{cache: cache} do
        assert_raise Nebulex.Error, fn ->
          cache.touch!(:raise)
        end
      end
    end
  end
end
