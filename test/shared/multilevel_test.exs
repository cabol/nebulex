defmodule Nebulex.MultilevelTest do
  import Nebulex.SharedTestCase

  deftests "multilevel" do
    @levels @cache.__levels__()
    @l1 :lists.nth(1, @levels)
    @l2 :lists.nth(2, @levels)
    @l3 :lists.nth(3, @levels)

    for level <- @levels do
      :ok = Application.put_env(:nebulex, level, gc_interval: 3_600_000, partitions: 2)
    end

    test "partitions for L3 with shards backend" do
      assert @l3
             |> Module.concat("0")
             |> :shards_state.get()
             |> :shards_state.n_shards() == 2
    end

    test "fail on __before_compile__ because missing levels config" do
      msg = "expected levels: to be a list and have at least one level"

      assert_raise ArgumentError, msg, fn ->
        defmodule MissingLevelsConfig do
          use Nebulex.Cache,
            otp_app: :nebulex,
            adapter: Nebulex.Adapters.Multilevel
        end
      end
    end

    test "fail on __before_compile__ because empty level list" do
      :ok =
        Application.put_env(
          :nebulex,
          String.to_atom("#{__MODULE__}.EmptyLevelList"),
          levels: []
        )

      msg = "expected levels: to be a list and have at least one level"

      assert_raise ArgumentError, msg, fn ->
        defmodule EmptyLevelList do
          use Nebulex.Cache,
            otp_app: :nebulex,
            adapter: Nebulex.Adapters.Multilevel
        end
      end
    end

    test "__before_compile__" do
      defmodule MyMultilevel do
        use Nebulex.Cache,
          otp_app: :nebulex,
          adapter: Nebulex.Adapters.Multilevel,
          levels: [L1]
      end
    end

    test "put" do
      assert @cache.put(1, 1) == :ok
      assert @l1.get(1) == 1
      assert @l2.get(1) == 1
      assert @l3.get(1) == 1

      assert @cache.put(2, 2, level: 2) == :ok
      assert @l2.get(2) == 2
      refute @l1.get(2)
      refute @l3.get(2)

      assert @cache.put("foo", nil) == :ok
      refute @cache.get("foo")
    end

    test "put_new" do
      assert @cache.put_new(1, 1)
      refute @cache.put_new(1, 2)
      assert @l1.get(1) == 1
      assert @l2.get(1) == 1
      assert @l3.get(1) == 1

      assert @cache.put_new(2, 2, level: 2)
      assert @l2.get(2) == 2
      refute @l1.get(2)
      refute @l3.get(2)

      assert @cache.put_new("foo", nil)
      refute @cache.get("foo")
    end

    test "put_all" do
      assert @cache.put_all(
               for x <- 1..3 do
                 {x, x}
               end,
               ttl: 1000
             ) == :ok

      for x <- 1..3, do: assert(@cache.get(x) == x)
      :ok = Process.sleep(1100)
      for x <- 1..3, do: refute(@cache.get(x))

      assert @cache.put_all(%{"apples" => 1, "bananas" => 3}) == :ok
      assert @cache.put_all(blueberries: 2, strawberries: 5) == :ok
      assert @cache.get("apples") == 1
      assert @cache.get("bananas") == 3
      assert @cache.get(:blueberries) == 2
      assert @cache.get(:strawberries) == 5

      assert @cache.put_all([]) == :ok
      assert @cache.put_all(%{}) == :ok

      refute @cache.put_new_all(%{"apples" => 100})
      assert @cache.get("apples") == 1
    end

    test "get_all" do
      assert @cache.put_all(a: 1, c: 3) == :ok
      assert @cache.get_all([:a, :b, :c], version: -1) == %{a: 1, c: 3}
    end

    test "delete" do
      assert @cache.put(1, 1)
      assert @cache.put(2, 2, level: 2)

      assert @cache.delete(1) == :ok
      refute @l1.get(1)
      refute @l2.get(1)
      refute @l3.get(1)

      assert @cache.delete(2, level: 2) == :ok
      refute @l1.get(2)
      refute @l2.get(2)
      refute @l3.get(2)
    end

    test "take" do
      assert @cache.put(1, 1) == :ok
      assert @cache.put(2, 2, level: 2) == :ok
      assert @cache.put(3, 3, level: 3) == :ok

      assert @cache.take(1) == 1
      assert @cache.take(2) == 2
      assert @cache.take(3) == 3

      refute @l1.get(1)
      refute @l2.get(1)
      refute @l3.get(1)
      refute @l2.get(2)
      refute @l3.get(3)
    end

    test "has_key?" do
      assert @cache.put(1, 1) == :ok
      assert @cache.put(2, 2, level: 2) == :ok
      assert @cache.put(3, 3, level: 3) == :ok

      assert @cache.has_key?(1)
      assert @cache.has_key?(2)
      assert @cache.has_key?(3)
      refute @cache.has_key?(4)
    end

    test "ttl" do
      assert @cache.put(:a, 1, ttl: 1000) == :ok
      assert @cache.ttl(:a) > 0
      assert @cache.put(:b, 2) == :ok

      :ok = Process.sleep(10)
      assert @cache.ttl(:a) > 0
      assert @cache.ttl(:b) == :infinity
      refute @cache.ttl(:c)

      :ok = Process.sleep(1100)
      refute @cache.ttl(:a)
    end

    test "expire" do
      assert @cache.put(:a, 1, ttl: 1000) == :ok
      assert @cache.ttl(:a) > 0

      assert @cache.expire(:a, 5000)
      assert @l1.ttl(:a) > 1000
      assert @l2.ttl(:a) > 1000
      assert @l3.ttl(:a) > 1000

      assert @l2.put(:b, 2) == :ok
      assert @cache.expire(:b, 2000)
      assert @cache.ttl(:b) > 1000
      refute @l1.expire(:b, 2000)
      refute @l3.expire(:b, 2000)
      assert @cache.ttl(:b) > 0
    end

    test "touch" do
      assert @l2.put(:touch, 1, ttl: 1000) == :ok

      :ok = Process.sleep(10)
      assert @cache.touch(:touch)

      :ok = Process.sleep(200)
      assert @cache.touch(:touch)
      assert @cache.get(:touch) == 1

      :ok = Process.sleep(1100)
      refute @cache.get(:touch)

      refute @cache.touch(:non_existent)
    end

    test "size" do
      for x <- 1..10, do: @l1.put(x, x)
      for x <- 11..20, do: @l2.put(x, x)
      for x <- 21..30, do: @l3.put(x, x)
      assert @cache.size() == 30

      for x <- [1, 11, 21], do: @cache.delete(x, level: 1)
      assert @cache.size() == 29

      assert @l1.delete(1) == :ok
      assert @l2.delete(11) == :ok
      assert @l3.delete(21) == :ok
      assert @cache.size() == 27
    end

    test "flush" do
      for x <- 1..10, do: @l1.put(x, x)
      for x <- 11..20, do: @l2.put(x, x)
      for x <- 21..30, do: @l3.put(x, x)

      assert count = @cache.size()
      assert @cache.flush() == count
      :ok = Process.sleep(500)

      for x <- 1..30, do: refute(@cache.get(x))
    end

    test "all and stream" do
      for x <- 1..30, do: @l1.put(x, x)
      for x <- 20..60, do: @l2.put(x, x)
      for x <- 50..100, do: @l3.put(x, x)

      expected = :lists.usort(for x <- 1..100, do: x)
      assert :lists.usort(@cache.all()) == expected

      stream = @cache.stream()

      assert stream
             |> Enum.to_list()
             |> :lists.usort() == expected

      del =
        for x <- 20..60 do
          assert @cache.delete(x) == :ok
          x
        end

      expected = :lists.usort(expected -- del)
      assert :lists.usort(@cache.all()) == expected
    end

    test "get_and_update" do
      assert @cache.put(1, 1, level: 1) == :ok
      assert @cache.put(2, 2) == :ok

      assert @cache.get_and_update(1, &{&1, &1 * 2}, level: 1) == {1, 2}
      assert @l1.get(1) == 2
      refute @l2.get(1)
      refute @l3.get(1)

      assert @cache.get_and_update(2, &{&1, &1 * 2}) == {2, 4}
      assert @l1.get(2) == 4
      assert @l2.get(2) == 4
      assert @l3.get(2) == 4

      assert @cache.get_and_update(1, fn _ -> :pop end, level: 1) == {2, nil}
      refute @l1.get(1)

      assert @cache.get_and_update(2, fn _ -> :pop end) == {4, nil}
      refute @l1.get(2)
      refute @l2.get(2)
      refute @l3.get(2)
    end

    test "update" do
      assert @cache.put(1, 1, level: 1) == :ok
      assert @cache.put(2, 2) == :ok

      assert @cache.update(1, 1, &(&1 * 2), level: 1) == 2
      assert @l1.get(1) == 2
      refute @l2.get(1)
      refute @l3.get(1)

      assert @cache.update(2, 1, &(&1 * 2)) == 4
      assert @l1.get(2) == 4
      assert @l2.get(2) == 4
      assert @l3.get(2) == 4
    end

    test "incr" do
      assert @cache.incr(1) == 1
      assert @l1.get(1) == 1
      assert @l2.get(1) == 1
      assert @l3.get(1) == 1

      assert @cache.incr(2, 2, level: 2) == 2
      assert @l2.get(2) == 2
      refute @l1.get(2)
      refute @l3.get(2)

      assert @cache.incr(3, 3) == 3
      assert @l1.get(3) == 3
      assert @l2.get(3) == 3
      assert @l3.get(3) == 3

      assert @cache.incr(4, 5) == 5
      assert @cache.incr(4, -5) == 0
      assert @l1.get(4) == 0
      assert @l2.get(4) == 0
      assert @l3.get(4) == 0
    end

    test "get with fallback" do
      assert_for_all_levels(nil, 1)
      assert @cache.get(1, fallback: fn key -> key * 2 end) == 2
      assert_for_all_levels(2, 1)
      refute @cache.get("foo", fallback: {@cache, :fallback})
    end

    ## Helpers

    defp assert_for_all_levels(expected, key) do
      Enum.each(@levels, fn cache ->
        case @cache.__model__ do
          :inclusive -> ^expected = cache.get(key)
          :exclusive -> nil = cache.get(key)
        end
      end)
    end
  end
end
