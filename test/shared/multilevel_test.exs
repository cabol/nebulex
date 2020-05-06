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
      assert 2 ==
               @l3
               |> Module.concat("0")
               |> :shards_state.get()
               |> :shards_state.n_shards()
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
      assert :ok == @cache.put(1, 1)
      assert 1 == @l1.get(1)
      assert 1 == @l2.get(1)
      assert 1 == @l3.get(1)

      assert :ok == @cache.put(2, 2, level: 2)
      assert 2 == @l2.get(2)
      refute @l1.get(2)
      refute @l3.get(2)

      assert :ok == @cache.put("foo", nil)
      refute @cache.get("foo")
    end

    test "put_new" do
      assert @cache.put_new(1, 1)
      refute @cache.put_new(1, 2)
      assert 1 == @l1.get(1)
      assert 1 == @l2.get(1)
      assert 1 == @l3.get(1)

      assert @cache.put_new(2, 2, level: 2)
      assert 2 == @l2.get(2)
      refute @l1.get(2)
      refute @l3.get(2)

      assert @cache.put_new("foo", nil)
      refute @cache.get("foo")
    end

    test "put_all" do
      assert :ok ==
               @cache.put_all(
                 for x <- 1..3 do
                   {x, x}
                 end,
                 ttl: 1000
               )

      for x <- 1..3, do: assert(x == @cache.get(x))
      :ok = Process.sleep(1100)
      for x <- 1..3, do: refute(@cache.get(x))

      assert :ok == @cache.put_all(%{"apples" => 1, "bananas" => 3})
      assert :ok == @cache.put_all(blueberries: 2, strawberries: 5)
      assert 1 == @cache.get("apples")
      assert 3 == @cache.get("bananas")
      assert 2 == @cache.get(:blueberries)
      assert 5 == @cache.get(:strawberries)

      assert :ok == @cache.put_all([])
      assert :ok == @cache.put_all(%{})

      refute @cache.put_new_all(%{"apples" => 100})
      assert 1 == @cache.get("apples")
    end

    test "get_all" do
      assert :ok == @cache.put_all(a: 1, c: 3)

      map = @cache.get_all([:a, :b, :c], version: -1)
      assert %{a: 1, c: 3} == map
      refute map[:b]
    end

    test "delete" do
      assert @cache.put(1, 1)
      assert @cache.put(2, 2, level: 2)

      assert :ok == @cache.delete(1)
      refute @l1.get(1)
      refute @l2.get(1)
      refute @l3.get(1)

      assert :ok == @cache.delete(2, level: 2)
      refute @l1.get(2)
      refute @l2.get(2)
      refute @l3.get(2)
    end

    test "take" do
      assert :ok == @cache.put(1, 1)
      assert :ok == @cache.put(2, 2, level: 2)
      assert :ok == @cache.put(3, 3, level: 3)

      assert 1 == @cache.take(1)
      assert 2 == @cache.take(2)
      assert 3 == @cache.take(3)

      refute @l1.get(1)
      refute @l2.get(1)
      refute @l3.get(1)
      refute @l2.get(2)
      refute @l3.get(3)
    end

    test "has_key?" do
      assert :ok == @cache.put(1, 1)
      assert :ok == @cache.put(2, 2, level: 2)
      assert :ok == @cache.put(3, 3, level: 3)

      assert @cache.has_key?(1)
      assert @cache.has_key?(2)
      assert @cache.has_key?(3)
      refute @cache.has_key?(4)
    end

    test "ttl" do
      assert :ok == @cache.put(:a, 1, ttl: 1000)
      assert @cache.ttl(:a) > 0
      assert :ok == @cache.put(:b, 2)

      :ok = Process.sleep(10)
      assert @cache.ttl(:a) > 0
      assert :infinity == @cache.ttl(:b)
      refute @cache.ttl(:c)

      :ok = Process.sleep(1100)
      refute @cache.ttl(:a)
    end

    test "expire" do
      assert :ok == @cache.put(:a, 1, ttl: 1000)
      assert @cache.ttl(:a) > 0

      assert @cache.expire(:a, 5000)
      assert @l1.ttl(:a) > 1000
      assert @l2.ttl(:a) > 1000
      assert @l3.ttl(:a) > 1000

      assert :ok == @l2.put(:b, 2)
      assert @cache.expire(:b, 2000)
      assert @cache.ttl(:b) > 1000
      refute @l1.expire(:b, 2000)
      refute @l3.expire(:b, 2000)
      assert @cache.ttl(:b) > 0
    end

    test "touch" do
      assert :ok == @l2.put(:touch, 1, ttl: 1000)

      :ok = Process.sleep(10)
      assert @cache.touch(:touch)

      :ok = Process.sleep(200)
      assert @cache.touch(:touch)
      assert 1 == @cache.get(:touch)

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
      assert 29 == @cache.size()

      assert :ok == @l1.delete(1)
      assert :ok == @l2.delete(11)
      assert :ok == @l3.delete(21)
      assert 27 == @cache.size()
    end

    test "flush" do
      for x <- 1..10, do: @l1.put(x, x)
      for x <- 11..20, do: @l2.put(x, x)
      for x <- 21..30, do: @l3.put(x, x)

      assert count = @cache.size()
      assert count == @cache.flush()
      :ok = Process.sleep(500)

      for x <- 1..30, do: refute(@cache.get(x))
    end

    test "all and stream" do
      for x <- 1..30, do: @l1.put(x, x)
      for x <- 20..60, do: @l2.put(x, x)
      for x <- 50..100, do: @l3.put(x, x)

      expected = :lists.usort(for x <- 1..100, do: x)
      assert expected == :lists.usort(@cache.all())

      stream = @cache.stream()

      assert expected ==
               stream
               |> Enum.to_list()
               |> :lists.usort()

      del =
        for x <- 20..60 do
          assert :ok == @cache.delete(x)
          x
        end

      expected = :lists.usort(expected -- del)
      assert expected == :lists.usort(@cache.all())
    end

    test "get_and_update" do
      assert :ok == @cache.put(1, 1, level: 1)
      assert :ok == @cache.put(2, 2)

      assert {1, 2} == @cache.get_and_update(1, &{&1, &1 * 2}, level: 1)
      assert 2 == @l1.get(1)
      refute @l2.get(1)
      refute @l3.get(1)

      assert {2, 4} == @cache.get_and_update(2, &{&1, &1 * 2})
      assert 4 == @l1.get(2)
      assert 4 == @l2.get(2)
      assert 4 == @l3.get(2)

      assert {2, nil} == @cache.get_and_update(1, fn _ -> :pop end, level: 1)
      refute @l1.get(1)

      assert {4, nil} == @cache.get_and_update(2, fn _ -> :pop end)
      refute @l1.get(2)
      refute @l2.get(2)
      refute @l3.get(2)
    end

    test "update" do
      assert :ok == @cache.put(1, 1, level: 1)
      assert :ok == @cache.put(2, 2)

      assert 2 == @cache.update(1, 1, &(&1 * 2), level: 1)
      assert 2 == @l1.get(1)
      refute @l2.get(1)
      refute @l3.get(1)

      assert 4 == @cache.update(2, 1, &(&1 * 2))
      assert 4 == @l1.get(2)
      assert 4 == @l2.get(2)
      assert 4 == @l3.get(2)
    end

    test "incr" do
      assert 1 == @cache.incr(1)
      assert 1 == @l1.get(1)
      assert 1 == @l2.get(1)
      assert 1 == @l3.get(1)

      assert 2 == @cache.incr(2, 2, level: 2)
      assert 2 == @l2.get(2)
      refute @l1.get(2)
      refute @l3.get(2)

      assert 3 == @cache.incr(3, 3)
      assert 3 == @l1.get(3)
      assert 3 == @l2.get(3)
      assert 3 == @l3.get(3)

      assert 5 == @cache.incr(4, 5)
      assert 0 == @cache.incr(4, -5)
      assert 0 == @l1.get(4)
      assert 0 == @l2.get(4)
      assert 0 == @l3.get(4)
    end

    test "get with fallback" do
      assert_for_all_levels(nil, 1)
      assert 2 == @cache.get(1, fallback: fn key -> key * 2 end)
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
