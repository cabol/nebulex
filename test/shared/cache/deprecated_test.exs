defmodule Nebulex.Cache.DeprecatedTest do
  import Nebulex.CacheCase

  deftests do
    describe "size/0" do
      test "returns the current number of entries in cache", %{cache: cache} do
        for x <- 1..100, do: cache.put(x, x)
        assert cache.size() == 100

        for x <- 1..50, do: cache.delete(x)
        assert cache.size() == 50

        for x <- 51..60, do: assert(cache.get(x) == x)
        assert cache.size() == 50
      end
    end

    describe "flush/0" do
      test "evicts all entries from cache", %{cache: cache} do
        Enum.each(1..2, fn _ ->
          for x <- 1..100, do: cache.put(x, x)

          assert cache.flush() == 100
          :ok = Process.sleep(500)

          for x <- 1..100, do: refute(cache.get(x))
        end)
      end
    end
  end
end
