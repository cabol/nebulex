defmodule Nebulex.Cache.PersistenceTest do
  import Nebulex.CacheCase

  deftests "persistence" do
    import Nebulex.CacheCase, only: [t_sleep: 1]

    test "dump and load", %{cache: cache} = attrs do
      tmp = System.tmp_dir!()
      path = "#{tmp}/#{attrs[:name] || cache}"

      try do
        assert cache.count_all!() == 0
        assert cache.dump(path) == :ok
        assert File.exists?(path)
        assert cache.load(path) == :ok
        assert cache.count_all!() == 0

        count = 100
        unexpired = for x <- 1..count, into: %{}, do: {x, x}

        assert cache.put_all(unexpired) == :ok
        assert cache.put_all(%{a: 1, b: 2}, ttl: 10) == :ok
        assert cache.put_all(%{c: 1, d: 2}, ttl: :timer.hours(1)) == :ok
        assert cache.count_all!() == count + 4

        _ = t_sleep(1100)

        assert cache.dump(path) == :ok
        assert File.exists?(path)
        assert cache.delete_all!() == count + 4
        assert cache.count_all!() == 0

        assert cache.load(path) == :ok
        assert cache.get_all!(in: Enum.to_list(1..count)) |> Map.new() == unexpired
        assert cache.get_all!(in: [:a, :b, :c, :d]) |> Map.new() == %{c: 1, d: 2}
        assert cache.count_all!() == count + 2
      after
        File.rm_rf!(path)
      end
    end
  end
end
