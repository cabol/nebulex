defmodule Nebulex.Cache.QueryableExpirationTest do
  import Nebulex.CacheCase

  deftests do
    import Nebulex.CacheCase

    describe "expired entries are not matched and returned" do
      test "on: get_all! or stream!", %{cache: cache} do
        :ok = cache.put_all!(exp1: 1, exp2: 2)
        :ok = cache.put(:exp3, 3, ttl: 1000)

        keys = [:exp1, :exp2, :exp3]

        assert cache.get_all!(select: :key) |> :lists.usort() == keys
        assert cache.stream!(select: :key) |> Enum.to_list() |> :lists.usort() == keys

        wait_until fn ->
          assert cache.get_all!(select: :key) |> :lists.usort() == [:exp1, :exp2]

          assert stream = cache.stream!(select: :key)
          assert stream |> Enum.to_list() |> :lists.usort() == [:exp1, :exp2]
        end
      end

      test "on: get_all! or stream! [in: keys]", %{cache: cache} do
        :ok = cache.put_all!(exp_a: 1, exp_b: 2)
        :ok = cache.put(:exp_c, 3, ttl: 1000)

        keys = [:exp_a, :exp_b, :exp_c]

        assert cache.get_all!(in: keys, select: :key) |> :lists.usort() == keys
        assert cache.stream!(in: keys, select: :key) |> Enum.to_list() |> :lists.usort() == keys

        wait_until fn ->
          assert cache.get_all!(in: keys, select: :key) |> :lists.usort() == [:exp_a, :exp_b]

          assert stream = cache.stream!(in: keys, select: :key)
          assert stream |> Enum.to_list() |> :lists.usort() == [:exp_a, :exp_b]
        end
      end

      test "on: delete_all! [in: keys]", %{cache: cache} do
        :ok = cache.put_all!(del_exp_a: 1, del_exp_b: 2)
        :ok = cache.put(:del_exp_c, 3, ttl: 1000)

        assert cache.count_all!() == 3
        assert cache.delete_all!(in: [:del_exp_a]) == 1
        assert cache.count_all!() == 2

        wait_until fn ->
          assert cache.get_all!(select: :key) |> :lists.usort() == [:del_exp_b]
        end
      end
    end
  end
end
