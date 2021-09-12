defmodule Nebulex.MultilevelTest do
  import Nebulex.CacheCase

  deftests do
    describe "c:init/1" do
      test "fails because missing levels config", %{cache: cache} do
        assert {:error, {%ArgumentError{message: msg}, _}} = cache.start_link(name: :missing_levels)

        assert Regex.match?(
                 ~r"expected levels: to be a list with at least one level definition",
                 msg
               )
      end
    end

    describe "entry:" do
      test "put/3", %{cache: cache} do
        assert cache.put(1, 1) == :ok
        assert cache.get(1, level: 1) == 1
        assert cache.get(1, level: 2) == 1
        assert cache.get(1, level: 3) == 1

        assert cache.put(2, 2, level: 2) == :ok
        assert cache.get(2, level: 2) == 2
        refute cache.get(2, level: 1)
        refute cache.get(2, level: 3)

        assert cache.put("foo", nil) == :ok
        refute cache.get("foo")
      end

      test "put_new/3", %{cache: cache} do
        assert cache.put_new(1, 1)
        refute cache.put_new(1, 2)
        assert cache.get(1, level: 1) == 1
        assert cache.get(1, level: 2) == 1
        assert cache.get(1, level: 3) == 1

        assert cache.put_new(2, 2, level: 2)
        assert cache.get(2, level: 2) == 2
        refute cache.get(2, level: 1)
        refute cache.get(2, level: 3)

        assert cache.put_new("foo", nil)
        refute cache.get("foo")
      end

      test "put_all/2", %{cache: cache} do
        assert cache.put_all(
                 for x <- 1..3 do
                   {x, x}
                 end,
                 ttl: 1000
               ) == :ok

        for x <- 1..3, do: assert(cache.get(x) == x)
        :ok = Process.sleep(1100)
        for x <- 1..3, do: refute(cache.get(x))

        assert cache.put_all(%{"apples" => 1, "bananas" => 3}) == :ok
        assert cache.put_all(blueberries: 2, strawberries: 5) == :ok
        assert cache.get("apples") == 1
        assert cache.get("bananas") == 3
        assert cache.get(:blueberries) == 2
        assert cache.get(:strawberries) == 5

        assert cache.put_all([]) == :ok
        assert cache.put_all(%{}) == :ok

        refute cache.put_new_all(%{"apples" => 100})
        assert cache.get("apples") == 1
      end

      test "get_all/2", %{cache: cache} do
        assert cache.put_all(a: 1, c: 3) == :ok
        assert cache.get_all([:a, :b, :c]) == %{a: 1, c: 3}
      end

      test "delete/2", %{cache: cache} do
        assert cache.put(1, 1)
        assert cache.put(2, 2, level: 2)

        assert cache.delete(1) == :ok
        refute cache.get(1, level: 1)
        refute cache.get(1, level: 2)
        refute cache.get(1, level: 3)

        assert cache.delete(2, level: 2) == :ok
        refute cache.get(2, level: 1)
        refute cache.get(2, level: 2)
        refute cache.get(2, level: 3)
      end

      test "take/2", %{cache: cache} do
        assert cache.put(1, 1) == :ok
        assert cache.put(2, 2, level: 2) == :ok
        assert cache.put(3, 3, level: 3) == :ok

        assert cache.take(1) == 1
        assert cache.take(2) == 2
        assert cache.take(3) == 3

        refute cache.get(1, level: 1)
        refute cache.get(1, level: 2)
        refute cache.get(1, level: 3)
        refute cache.get(2, level: 2)
        refute cache.get(3, level: 3)
      end

      test "exists?/1", %{cache: cache} do
        assert cache.put(1, 1) == :ok
        assert cache.put(2, 2, level: 2) == :ok
        assert cache.put(3, 3, level: 3) == :ok

        assert cache.exists?(1)
        assert cache.exists?(2)
        assert cache.exists?(3)
        refute cache.exists?(4)
      end

      test "ttl/1", %{cache: cache} do
        assert cache.put(:a, 1, ttl: 1000) == :ok
        assert cache.ttl(:a) > 0
        assert cache.put(:b, 2) == :ok

        :ok = Process.sleep(10)
        assert cache.ttl(:a) > 0
        assert cache.ttl(:b) == :infinity
        refute cache.ttl(:c)

        :ok = Process.sleep(1100)
        refute cache.ttl(:a)
      end

      test "expire/2", %{cache: cache} do
        assert cache.put(:a, 1) == :ok
        assert cache.ttl(:a) == :infinity

        assert cache.expire(:a, 1000)
        ttl = cache.ttl(:a)
        assert ttl > 0 and ttl <= 1000

        assert cache.get(:a, level: 1) == 1
        assert cache.get(:a, level: 2) == 1
        assert cache.get(:a, level: 3) == 1

        :ok = Process.sleep(1100)
        refute cache.get(:a)
        refute cache.get(:a, level: 1)
        refute cache.get(:a, level: 2)
        refute cache.get(:a, level: 3)
      end

      test "touch/1", %{cache: cache} do
        assert cache.put(:touch, 1, ttl: 1000, level: 2) == :ok

        :ok = Process.sleep(10)
        assert cache.touch(:touch)

        :ok = Process.sleep(200)
        assert cache.touch(:touch)
        assert cache.get(:touch) == 1

        :ok = Process.sleep(1100)
        refute cache.get(:touch)

        refute cache.touch(:non_existent)
      end

      test "get_and_update/3", %{cache: cache} do
        assert cache.put(1, 1, level: 1) == :ok
        assert cache.put(2, 2) == :ok

        assert cache.get_and_update!(1, &{&1, &1 * 2}, level: 1) == {1, 2}
        assert cache.get(1, level: 1) == 2
        refute cache.get(1, level: 3)
        refute cache.get(1, level: 3)

        assert cache.get_and_update!(2, &{&1, &1 * 2}) == {2, 4}
        assert cache.get(2, level: 1) == 4
        assert cache.get(2, level: 2) == 4
        assert cache.get(2, level: 3) == 4

        assert cache.get_and_update!(1, fn _ -> :pop end, level: 1) == {2, nil}
        refute cache.get(1, level: 1)

        assert cache.get_and_update!(2, fn _ -> :pop end) == {4, nil}
        refute cache.get(2, level: 1)
        refute cache.get(2, level: 2)
        refute cache.get(2, level: 3)
      end

      test "update/4", %{cache: cache} do
        assert cache.put(1, 1, level: 1) == :ok
        assert cache.put(2, 2) == :ok

        assert cache.update!(1, 1, &(&1 * 2), level: 1) == 2
        assert cache.get(1, level: 1) == 2
        refute cache.get(1, level: 2)
        refute cache.get(1, level: 3)

        assert cache.update!(2, 1, &(&1 * 2)) == 4
        assert cache.get(2, level: 1) == 4
        assert cache.get(2, level: 2) == 4
        assert cache.get(2, level: 3) == 4
      end

      test "incr/3", %{cache: cache} do
        assert cache.incr(1) == 1
        assert cache.get(1, level: 1) == 1
        assert cache.get(1, level: 2) == 1
        assert cache.get(1, level: 3) == 1

        assert cache.incr(2, 2, level: 2) == 2
        assert cache.get(2, level: 2) == 2
        refute cache.get(2, level: 1)
        refute cache.get(2, level: 3)

        assert cache.incr(3, 3) == 3
        assert cache.get(3, level: 1) == 3
        assert cache.get(3, level: 2) == 3
        assert cache.get(3, level: 3) == 3

        assert cache.incr(4, 5) == 5
        assert cache.incr(4, -5) == 0
        assert cache.get(4, level: 1) == 0
        assert cache.get(4, level: 2) == 0
        assert cache.get(4, level: 3) == 0
      end
    end

    describe "queryable:" do
      test "all/2 and stream/2", %{cache: cache} do
        for x <- 1..30, do: cache.put(x, x, level: 1)
        for x <- 20..60, do: cache.put(x, x, level: 2)
        for x <- 50..100, do: cache.put(x, x, level: 3)

        expected = :lists.usort(for x <- 1..100, do: x)
        assert :lists.usort(cache.all()) == expected

        stream = cache.stream()

        assert stream
               |> Enum.to_list()
               |> :lists.usort() == expected

        del =
          for x <- 20..60 do
            assert cache.delete(x) == :ok
            x
          end

        expected = :lists.usort(expected -- del)
        assert :lists.usort(cache.all()) == expected
      end

      test "delete_all/2", %{cache: cache} do
        for x <- 1..30, do: cache.put(x, x, level: 1)
        for x <- 21..60, do: cache.put(x, x, level: 2)
        for x <- 51..100, do: cache.put(x, x, level: 3)

        assert count = cache.count_all()
        assert cache.delete_all() == count
        assert cache.all() == []
      end

      test "count_all/2", %{cache: cache} do
        assert cache.count_all() == 0
        for x <- 1..10, do: cache.put(x, x, level: 1)
        for x <- 11..20, do: cache.put(x, x, level: 2)
        for x <- 21..30, do: cache.put(x, x, level: 3)
        assert cache.count_all() == 30

        for x <- [1, 11, 21], do: cache.delete(x, level: 1)
        assert cache.count_all() == 29

        assert cache.delete(1, level: 1) == :ok
        assert cache.delete(11, level: 2) == :ok
        assert cache.delete(21, level: 3) == :ok
        assert cache.count_all() == 27
      end
    end
  end
end
