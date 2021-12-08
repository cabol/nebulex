defmodule Nebulex.MultilevelTest do
  import Nebulex.CacheCase

  deftests do
    import Mock

    describe "c:init/1" do
      test "fails because missing levels config", %{cache: cache} do
        assert {:error, {%ArgumentError{message: msg}, _}} = cache.start_link(name: :missing_levels)

        assert Regex.match?(
                 ~r"expected levels: to be a list with at least one level definition",
                 msg
               )
      end
    end

    describe "put/3" do
      test "ok", %{cache: cache} do
        assert cache.put(1, 1) == :ok
        assert cache.get!(1, nil, level: 1) == 1
        assert cache.get!(1, nil, level: 2) == 1
        assert cache.get!(1, nil, level: 3) == 1

        assert cache.put(2, 2, level: 2) == :ok
        assert cache.get!(2, nil, level: 2) == 2
        refute cache.get!(2, nil, level: 1)
        refute cache.get!(2, nil, level: 3)

        assert cache.put("foo", nil) == :ok
        refute cache.get!("foo")
      end

      test_with_mock "raises an error", %{cache: cache}, cache.__adapter__(), [:passthrough],
        put: fn _, _, _, _, _, _ -> {:error, %RuntimeError{message: "error"}} end do
        assert_raise RuntimeError, ~r"error", fn ->
          cache.put!("hello", "world")
        end
      end
    end

    describe "put_new/3" do
      test "ok", %{cache: cache} do
        assert cache.put_new!(1, 1)
        refute cache.put_new!(1, 2)
        assert cache.get!(1, nil, level: 1) == 1
        assert cache.get!(1, nil, level: 2) == 1
        assert cache.get!(1, nil, level: 3) == 1

        assert cache.put_new!(2, 2, level: 2)
        assert cache.get!(2, nil, level: 2) == 2
        refute cache.get!(2, nil, level: 1)
        refute cache.get!(2, nil, level: 3)

        assert cache.put_new!("foo", nil)
        refute cache.get!("foo")
      end

      test_with_mock "raises an error", %{cache: cache}, cache.__adapter__(), [:passthrough],
        put: fn _, _, _, _, _, _ -> {:error, %Nebulex.Error{reason: :error}} end do
        assert_raise Nebulex.Error, ~r"Nebulex error:\n\n:error", fn ->
          cache.put_new!("hello", "world")
        end
      end
    end

    describe "put_all/2" do
      test "ok", %{cache: cache} do
        assert cache.put_all(
                 for x <- 1..3 do
                   {x, x}
                 end,
                 ttl: 1000
               ) == :ok

        for x <- 1..3, do: assert(cache.get!(x) == x)
        :ok = Process.sleep(1100)
        for x <- 1..3, do: refute(cache.get!(x))

        assert cache.put_all(%{"apples" => 1, "bananas" => 3}) == :ok
        assert cache.put_all(blueberries: 2, strawberries: 5) == :ok
        assert cache.get!("apples") == 1
        assert cache.get!("bananas") == 3
        assert cache.get!(:blueberries) == 2
        assert cache.get!(:strawberries) == 5

        assert cache.put_all([]) == :ok
        assert cache.put_all(%{}) == :ok

        refute cache.put_new_all!(%{"apples" => 100})
        assert cache.get!("apples") == 1
      end

      test_with_mock "raises an error", %{cache: cache}, cache.__adapter__(), [:passthrough],
        put_all: fn _, _, _, _, _ -> {:error, %Nebulex.Error{reason: :error}} end do
        assert_raise Nebulex.Error, ~r"Nebulex error:\n\n:error", fn ->
          cache.put_all!(other: 1)
        end
      end
    end

    describe "get_all/2" do
      test "ok", %{cache: cache} do
        assert cache.put_all(a: 1, c: 3) == :ok
        assert cache.get_all!([:a, :b, :c]) == %{a: 1, c: 3}
      end

      test_with_mock "raises an error", %{cache: cache}, cache.__adapter__(), [:passthrough],
        get_all: fn _, _, _ -> {:error, %Nebulex.Error{reason: :error}} end do
        assert_raise Nebulex.Error, ~r"Nebulex error:\n\n:error", fn ->
          cache.get_all!([:foo])
        end
      end
    end

    describe "delete/2" do
      test "ok", %{cache: cache} do
        assert cache.put(1, 1) == :ok
        assert cache.put(2, 2, level: 2) == :ok

        assert cache.delete(1) == :ok
        refute cache.get!(1, nil, level: 1)
        refute cache.get!(1, nil, level: 2)
        refute cache.get!(1, nil, level: 3)

        assert cache.delete(2, level: 2) == :ok
        refute cache.get!(2, nil, level: 1)
        refute cache.get!(2, nil, level: 2)
        refute cache.get!(2, nil, level: 3)
      end

      test_with_mock "raises an error", %{cache: cache}, cache.__adapter__(), [:passthrough],
        delete: fn _, _, _ -> {:error, %Nebulex.Error{reason: :error}} end do
        assert_raise Nebulex.Error, ~r"Nebulex error:\n\n:error", fn ->
          cache.delete!("raise")
        end
      end
    end

    describe "take/2" do
      test "ok", %{cache: cache} do
        assert cache.put(1, 1) == :ok
        assert cache.put(2, 2, level: 2) == :ok
        assert cache.put(3, 3, level: 3) == :ok

        assert cache.take!(1) == 1
        assert cache.take!(2) == 2
        assert cache.take!(3) == 3

        refute cache.get!(1, nil, level: 1)
        refute cache.get!(1, nil, level: 2)
        refute cache.get!(1, nil, level: 3)
        refute cache.get!(2, nil, level: 2)
        refute cache.get!(3, nil, level: 3)
      end

      test_with_mock "raises an error", %{cache: cache}, cache.__adapter__(), [:passthrough],
        take: fn _, _, _ -> {:error, %Nebulex.Error{reason: :error}} end do
        assert_raise Nebulex.Error, ~r"Nebulex error:\n\n:error", fn ->
          cache.take!("raise")
        end
      end
    end

    describe "exists?/1" do
      test "ok", %{cache: cache} do
        assert cache.put(1, 1) == :ok
        assert cache.put(2, 2, level: 2) == :ok
        assert cache.put(3, 3, level: 3) == :ok

        assert cache.exists?(1) == {:ok, true}
        assert cache.exists?(2) == {:ok, true}
        assert cache.exists?(3) == {:ok, true}
        assert cache.exists?(4) == {:ok, false}
      end

      test_with_mock "returns an error", %{cache: cache}, cache.__adapter__(), [:passthrough],
        exists?: fn _, _ -> {:error, %Nebulex.Error{reason: :error}} end do
        assert cache.exists?("error") ==
                 {:error, %Nebulex.Error{module: Nebulex.Error, reason: :error}}
      end
    end

    describe "ttl/1" do
      test "ok", %{cache: cache} do
        assert cache.put(:a, 1, ttl: 1000) == :ok
        assert cache.ttl!(:a) > 0
        assert cache.put(:b, 2) == :ok

        :ok = Process.sleep(10)
        assert cache.ttl!(:a) > 0
        assert cache.ttl!(:b) == :infinity

        assert_raise Nebulex.KeyError, fn ->
          cache.ttl!(:c)
        end

        :ok = Process.sleep(1100)

        assert_raise Nebulex.KeyError, fn ->
          cache.ttl!(:a)
        end
      end

      test "raises Nebulex.KeyError if key does not exist", %{cache: cache, name: name} do
        msg = ~r"key :non_existent not found in cache: #{inspect(name)}"

        assert_raise Nebulex.KeyError, msg, fn ->
          cache.ttl!(:non_existent)
        end
      end
    end

    describe "expire/2" do
      test "ok", %{cache: cache} do
        assert cache.put(:a, 1) == :ok
        assert cache.ttl!(:a) == :infinity

        assert cache.expire!(:a, 1000)
        ttl = cache.ttl!(:a)
        assert ttl > 0 and ttl <= 1000

        assert cache.get!(:a, nil, level: 1) == 1
        assert cache.get!(:a, nil, level: 2) == 1
        assert cache.get!(:a, nil, level: 3) == 1

        :ok = Process.sleep(1100)
        refute cache.get!(:a)
        refute cache.get!(:a, nil, level: 1)
        refute cache.get!(:a, nil, level: 2)
        refute cache.get!(:a, nil, level: 3)
      end

      test "raises when ttl is invalid", %{cache: cache} do
        assert_raise ArgumentError, ~r"expected ttl to be a valid timeout", fn ->
          cache.expire!(:a, "hello")
        end
      end

      test_with_mock "raises an error", %{cache: cache}, cache.__adapter__(), [:passthrough],
        expire: fn _, _, _ -> {:error, %Nebulex.Error{reason: :error}} end do
        assert_raise Nebulex.Error, ~r"Nebulex error:\n\n:error", fn ->
          cache.expire!(:raise, 100)
        end
      end
    end

    describe "touch/1" do
      test "ok", %{cache: cache} do
        assert cache.put(:touch, 1, ttl: 1000, level: 2) == :ok

        :ok = Process.sleep(10)
        assert cache.touch!(:touch)

        :ok = Process.sleep(200)
        assert cache.touch!(:touch)
        assert cache.get!(:touch) == 1

        :ok = Process.sleep(1100)
        refute cache.get!(:touch)

        refute cache.touch!(:non_existent)
      end

      test_with_mock "raises an error", %{cache: cache}, cache.__adapter__(), [:passthrough],
        touch: fn _, _ -> {:error, %Nebulex.Error{reason: :error}} end do
        assert_raise Nebulex.Error, ~r"Nebulex error:\n\n:error", fn ->
          cache.touch!(:raise)
        end
      end
    end

    describe "get_and_update/3" do
      test "ok", %{cache: cache} do
        assert cache.put(1, 1, level: 1) == :ok
        assert cache.put(2, 2) == :ok

        assert cache.get_and_update!(1, &{&1, &1 * 2}, level: 1) == {1, 2}
        assert cache.get!(1, nil, level: 1) == 2
        refute cache.get!(1, nil, level: 3)
        refute cache.get!(1, nil, level: 3)

        assert cache.get_and_update!(2, &{&1, &1 * 2}) == {2, 4}
        assert cache.get!(2, nil, level: 1) == 4
        assert cache.get!(2, nil, level: 2) == 4
        assert cache.get!(2, nil, level: 3) == 4

        assert cache.get_and_update!(1, fn _ -> :pop end, level: 1) == {2, nil}
        refute cache.get!(1, nil, level: 1)

        assert cache.get_and_update!(2, fn _ -> :pop end) == {4, nil}
        refute cache.get!(2, nil, level: 1)
        refute cache.get!(2, nil, level: 2)
        refute cache.get!(2, nil, level: 3)
      end
    end

    describe "update/4" do
      test "ok", %{cache: cache} do
        assert cache.put(1, 1, level: 1) == :ok
        assert cache.put(2, 2) == :ok

        assert cache.update!(1, 1, &(&1 * 2), level: 1) == 2
        assert cache.get!(1, nil, level: 1) == 2
        refute cache.get!(1, nil, level: 2)
        refute cache.get!(1, nil, level: 3)

        assert cache.update!(2, 1, &(&1 * 2)) == 4
        assert cache.get!(2, nil, level: 1) == 4
        assert cache.get!(2, nil, level: 2) == 4
        assert cache.get!(2, nil, level: 3) == 4
      end

      test_with_mock "raises because put error",
                     %{cache: cache},
                     cache.__adapter__(),
                     [:passthrough],
                     put: fn _, _, _, _, _, _ -> {:error, %Nebulex.Error{reason: :error}} end do
        assert_raise Nebulex.Error, ~r"Nebulex error:\n\n:error", fn ->
          cache.update!("error", 1, &String.to_integer/1)
        end
      end
    end

    describe "incr/3" do
      test "ok", %{cache: cache} do
        assert cache.incr!(1) == 1
        assert cache.get!(1, nil, level: 1) == 1
        assert cache.get!(1, nil, level: 2) == 1
        assert cache.get!(1, nil, level: 3) == 1

        assert cache.incr!(2, 2, level: 2) == 2
        assert cache.get!(2, nil, level: 2) == 2
        refute cache.get!(2, nil, level: 1)
        refute cache.get!(2, nil, level: 3)

        assert cache.incr!(3, 3) == 3
        assert cache.get!(3, nil, level: 1) == 3
        assert cache.get!(3, nil, level: 2) == 3
        assert cache.get!(3, nil, level: 3) == 3

        assert cache.incr!(4, 5) == 5
        assert cache.incr!(4, -5) == 0
        assert cache.get!(4, nil, level: 1) == 0
        assert cache.get!(4, nil, level: 2) == 0
        assert cache.get!(4, nil, level: 3) == 0
      end

      test_with_mock "raises an error", %{cache: cache}, cache.__adapter__(), [:passthrough],
        update_counter: fn _, _, _, _, _, _ -> {:error, %Nebulex.Error{reason: :error}} end do
        assert_raise Nebulex.Error, ~r"Nebulex error:\n\n:error", fn ->
          cache.incr!(:raise)
        end
      end
    end

    # describe "queryable:" do
    #   test "all/2 and stream/2", %{cache: cache} do
    #     for x <- 1..30, do: cache.put(x, x, level: 1)
    #     for x <- 20..60, do: cache.put(x, x, level: 2)
    #     for x <- 50..100, do: cache.put(x, x, level: 3)

    #     expected = :lists.usort(for x <- 1..100, do: x)
    #     assert :lists.usort(cache.all()) == expected

    #     stream = cache.stream()

    #     assert stream
    #            |> Enum.to_list()
    #            |> :lists.usort() == expected

    #     del =
    #       for x <- 20..60 do
    #         assert cache.delete(x) == :ok
    #         x
    #       end

    #     expected = :lists.usort(expected -- del)
    #     assert :lists.usort(cache.all()) == expected
    #   end

    #   test "delete_all/2", %{cache: cache} do
    #     for x <- 1..30, do: cache.put(x, x, level: 1)
    #     for x <- 21..60, do: cache.put(x, x, level: 2)
    #     for x <- 51..100, do: cache.put(x, x, level: 3)

    #     assert count = cache.count_all()
    #     assert cache.delete_all() == count
    #     assert cache.all() == []
    #   end

    #   test "count_all/2", %{cache: cache} do
    #     assert cache.count_all() == 0
    #     for x <- 1..10, do: cache.put(x, x, level: 1)
    #     for x <- 11..20, do: cache.put(x, x, level: 2)
    #     for x <- 21..30, do: cache.put(x, x, level: 3)
    #     assert cache.count_all() == 30

    #     for x <- [1, 11, 21], do: cache.delete(x, level: 1)
    #     assert cache.count_all() == 29

    #     assert cache.delete(1, level: 1) == :ok
    #     assert cache.delete(11, level: 2) == :ok
    #     assert cache.delete(21, level: 3) == :ok
    #     assert cache.count_all() == 27
    #   end
    # end
  end
end
