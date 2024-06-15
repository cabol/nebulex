defmodule Nebulex.Cache.QueryableExpirationTest do
  import Nebulex.CacheCase

  deftests do
    import Nebulex.CacheCase

    describe "expired entries are not matched and returned" do
      test "on: get_all! or stream!", %{cache: cache} do
        :ok = cache.put_all!(a: 1, b: 2)
        :ok = cache.put(:c, 3, ttl: 1000)

        keys = [:a, :b, :c]

        assert cache.get_all!(select: :key) |> :lists.usort() == keys
        assert cache.stream!(select: :key) |> Enum.to_list() |> :lists.usort() == keys

        wait_until(fn ->
          assert cache.get_all!(select: :key) |> :lists.usort() == [:a, :b]

          assert stream = cache.stream!(select: :key)
          assert stream |> Enum.to_list() |> :lists.usort() == [:a, :b]
        end)
      end

      test "on: get_all! or stream! [in: keys]", %{cache: cache} do
        :ok = cache.put_all!(a: 1, b: 2)
        :ok = cache.put(:c, 3, ttl: 1000)

        keys = [:a, :b, :c]

        assert cache.get_all!(in: keys, select: :key) |> :lists.usort() == keys
        assert cache.stream!(in: keys, select: :key) |> Enum.to_list() |> :lists.usort() == keys

        wait_until(fn ->
          assert cache.get_all!(in: keys, select: :key) |> :lists.usort() == [:a, :b]

          assert stream = cache.stream!(in: keys, select: :key)
          assert stream |> Enum.to_list() |> :lists.usort() == [:a, :b]
        end)
      end

      test "on: delete_all! [in: keys]", %{cache: cache} do
        :ok = cache.put_all!(a: 1, b: 2)
        :ok = cache.put(:c, 3, ttl: 1000)

        assert cache.count_all!() == 3
        assert cache.delete_all!(in: [:a]) == 1
        assert cache.count_all!() == 2

        wait_until(fn ->
          assert cache.get_all!(select: :key) |> :lists.usort() == [:b]
        end)
      end
    end
  end
end
