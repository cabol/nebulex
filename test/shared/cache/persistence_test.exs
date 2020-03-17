defmodule Nebulex.Cache.PersistenceTest do
  import Nebulex.SharedTestCase

  deftests do
    @path "tmp_#{@cache}"

    test "dump and load" do
      try do
        assert 0 == @cache.size()
        assert :ok == @cache.dump(@path)
        assert File.exists?(@path)
        assert :ok == @cache.load(@path)
        assert 0 == @cache.size()

        count = 100
        unexpired = for x <- 1..count, into: %{}, do: {x, x}

        assert :ok == @cache.put_all(unexpired)
        assert :ok == @cache.put_all(%{a: 1, b: 2}, ttl: 10)
        assert :ok == @cache.put_all(%{c: 1, d: 2}, ttl: 3_600_000)
        assert @cache.size() == count + 4

        :ok = Process.sleep(1000)
        assert :ok == @cache.dump(@path)
        assert File.exists?(@path)
        assert @cache.flush() == count + 4
        assert @cache.size() == 0

        assert {:error, :enoent} == @cache.load("wrong_file")
        assert :ok == @cache.load(@path)
        assert unexpired == @cache.get_all(1..count)
        assert %{c: 1, d: 2} == @cache.get_all([:a, :b, :c, :d])
        assert @cache.size() == count + 2
      after
        File.rm_rf!(@path)
      end
    end
  end
end
