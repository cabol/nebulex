defmodule Nebulex.Cache.PersistenceTest do
  import Nebulex.CacheCase

  deftests "persistence" do
    test "dump and load", %{cache: cache} do
      tmp = System.tmp_dir!()
      path = "#{tmp}/#{cache}"

      try do
        assert cache.size() == 0
        assert cache.dump(path) == :ok
        assert File.exists?(path)
        assert cache.load(path) == :ok
        assert cache.size() == 0

        count = 100
        unexpired = for x <- 1..count, into: %{}, do: {x, x}

        assert cache.put_all(unexpired) == :ok
        assert cache.put_all(%{a: 1, b: 2}, ttl: 10) == :ok
        assert cache.put_all(%{c: 1, d: 2}, ttl: 3_600_000) == :ok
        assert cache.size() == count + 4

        :ok = Process.sleep(1000)

        assert cache.dump(path) == :ok
        assert File.exists?(path)
        assert cache.flush() == count + 4
        assert cache.size() == 0

        assert cache.load(path) == :ok
        assert cache.get_all(1..count) == unexpired
        assert cache.get_all([:a, :b, :c, :d]) == %{c: 1, d: 2}
        assert cache.size() == count + 2
      after
        File.rm_rf!(path)
      end
    end
  end
end
