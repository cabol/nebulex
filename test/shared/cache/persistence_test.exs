defmodule Nebulex.Cache.PersistenceTest do
  import Nebulex.SharedTestCase

  deftests do
    import Nebulex.FileHelpers

    test "dump and load" do
      in_tmp(fn _ ->
        :ok = File.mkdir_p!("caches")

        assert 0 == @cache.size()
        assert :ok == @cache.dump("caches/test_cache")
        assert :ok == @cache.load("caches/test_cache")
        assert 0 == @cache.size()

        count = 33
        map = for x <- 1..count, into: %{}, do: {x, x}

        assert :ok == @cache.set_many(map)
        assert count == @cache.size()

        assert :ok == @cache.dump("caches/test_cache")
        assert :ok == @cache.flush()
        assert 0 == @cache.size()

        assert {:error, :enoent} == @cache.load("caches/wrong_file")
        assert :ok == @cache.load("caches/test_cache")
        assert map == @cache.get_many(1..count)
        assert count == @cache.size()
      end)
    end
  end
end
