defmodule Nebulex.Cache.ObjectTest do
  import Nebulex.SharedTestCase

  deftests do
    alias Nebulex.Object
    alias Nebulex.TestCache.Partitioned

    ## Objects

    test "delete" do
      for x <- 1..3, do: @cache.set(x, x * 2)

      assert 2 == @cache.get(1)
      %Object{value: 4, key: 2, version: v2} = @cache.get(2, return: :object)

      assert 1 == @cache.delete(1)
      refute @cache.delete(1, return: :value)
      refute @cache.get(1)

      2 = @cache.delete(2, version: v2)
      refute @cache.get(2)

      assert :non_existent == @cache.delete(:non_existent)

      assert :a ==
               :a
               |> @cache.set(1, return: :key)
               |> @cache.delete()

      refute @cache.get(:a)

      assert_raise Nebulex.VersionConflictError, fn ->
        @cache.delete(3, version: -1)
      end

      assert 1 == @cache.set(:a, 1)
      assert 1 == @cache.get(:a)
      assert :a == @cache.delete(:a, version: -1, on_conflict: :override)
      refute @cache.get(:a)

      assert 1 == @cache.set(:b, 1)
      assert 1 == @cache.get(:b)
      assert :b == @cache.delete(:b, version: -1, on_conflict: :nothing)
      assert 1 == @cache.get(:b)

      assert :x == @cache.delete(:x, version: -1, on_conflict: :override)
      refute @cache.get(:x)
    end

    test "get" do
      for x <- 1..2, do: @cache.set(x, x)

      assert 1 == @cache.get(1)
      assert 2 == @cache.get(2)
      refute @cache.get(3)
      refute @cache.get(3, return: :object)

      %Object{value: 1, key: 1, version: v1} = @cache.get(1, return: :object)
      %Object{value: 2, key: 2, version: _} = @cache.get(2, return: :object)
      refute @cache.get(3, return: :object)

      assert 1 == @cache.get(1, version: v1)

      assert_raise Nebulex.VersionConflictError, fn ->
        @cache.get(1, version: -1)
      end

      assert 1 == @cache.set(:a, 1)
      assert 1 == @cache.get(:a, version: -1, on_conflict: :nothing)
      assert 1 == @cache.get(:a, version: -1, on_conflict: :override)
    end

    test "get!" do
      for x <- 1..2, do: @cache.set(x, x)

      assert 1 == @cache.get!(1)
      assert 2 == @cache.get!(2)

      assert_raise KeyError, fn ->
        @cache.get!(3)
      end
    end

    test "set" do
      for x <- 1..4, do: @cache.set(x, x)

      assert 1 == @cache.get(1)
      assert 2 == @cache.get(2)

      for x <- 3..4, do: @cache.set(x, x * x)
      assert 9 == @cache.get(3)
      assert 16 == @cache.get(4)

      refute @cache.set("foo", nil)
      refute @cache.get("foo")

      %Object{value: 11, key: 1, version: v1} = @cache.set(1, 11, return: :object)
      %Object{value: 12, key: 1, version: v2} = @cache.set(1, 12, return: :object, version: v1)
      assert v1 != v2

      assert 12 == @cache.set(1, 13, version: -1, on_conflict: :nothing)
      assert 13 == @cache.set(1, 13, version: -1, on_conflict: :override)

      assert_raise Nebulex.VersionConflictError, fn ->
        @cache.set(1, 13, return: :object, version: -1)
      end

      assert_raise Nebulex.VersionConflictError, fn ->
        @cache.set(:a, 1, version: -1)
      end

      assert_raise ArgumentError, fn ->
        @cache.set(:a, 1, version: -1, on_conflict: :invalid) == 1
      end
    end

    test "add" do
      assert {:ok, "bar"} == @cache.add("foo", "bar")
      assert "bar" == @cache.get("foo")
      assert {:ok, nil} == @cache.add(:mykey, nil)
      {:ok, %Object{value: 1}} = @cache.add(1, 1, return: :object)
      :error = @cache.add("foo", "bar")
    end

    test "add!" do
      assert "world" == @cache.add!("hello", "world")

      message = ~r"key \"hello\" already exists in cache"

      assert_raise Nebulex.KeyAlreadyExistsError, message, fn ->
        @cache.add!("hello", "world world")
      end
    end

    test "replace" do
      assert :error == @cache.replace("foo", "bar")
      assert "bar" == @cache.set("foo", "bar")
      assert {:ok, "bar bar"} == @cache.replace("foo", "bar bar")
      assert {:ok, nil} == @cache.replace("foo", nil)
      assert {:ok, "bar bar bar"} == @cache.replace("foo", "bar bar bar")
    end

    test "replace!" do
      assert_raise KeyError, fn ->
        @cache.replace!("foo", "bar")
      end

      assert "bar" == @cache.set("foo", "bar")
      assert "bar bar" == @cache.replace!("foo", "bar bar")
      refute @cache.replace!("foo", nil)
      assert "bar bar bar" == @cache.replace!("foo", "bar bar bar")

      %Object{version: v1} = @cache.replace!("foo", "bar", return: :object)
      %Object{version: v2} = @cache.replace!("foo", "bar2", version: v1, return: :object)
      assert v1 != v2
    end

    test "replace but only ttl or version" do
      %Object{value: "bar", version: v1} = @cache.set("foo", "bar", return: :object)
      refute @cache.get!("foo", return: :object).expire_at

      refute @cache.replace!("foo", nil, ttl: 5)
      %Object{value: "bar", version: v2} = @cache.get!("foo", return: :object)
      assert v1 == v2

      %Object{value: "bar2"} =
        object =
        "foo"
        |> @cache.replace!("bar2", ttl: 5, return: :key)
        |> @cache.get!(return: :object)

      assert 5 == Object.remaining_ttl(object)

      %Object{value: "bar3", version: v3} =
        object =
        "foo"
        |> @cache.replace!("bar3", return: :key)
        |> @cache.get!(return: :object)

      assert :infinity == Object.remaining_ttl(object.expire_at)
      assert v2 != v3
    end

    test "add_or_replace!" do
      refute @cache.add_or_replace!("foo", nil)
      assert "bar" == @cache.add_or_replace!("foo", "bar")
      assert "bar bar" == @cache.add_or_replace!("foo", "bar bar")
      assert "bar bar bar" == @cache.add_or_replace!("foo", "bar bar bar")
    end

    test "set key terms" do
      refute @cache.get({:mykey, 1, "hello"})
      assert "world" == @cache.set({:mykey, 1, "hello"}, "world")
      assert "world" == @cache.get({:mykey, 1, "hello"})

      refute @cache.get(%{a: 1, b: 2})
      assert "value" == @cache.set(%{a: 1, b: 2}, "value")
      assert "value" == @cache.get(%{a: 1, b: 2})
    end

    test "get_many" do
      assert :ok == @cache.set_many(a: 1, c: 3)

      map = @cache.get_many([:a, :b, :c], version: -1)
      assert %{a: 1, c: 3} == map
      refute map[:b]

      map = @cache.get_many([:a, :b, :c], return: :object)
      %{a: %Object{value: 1}, c: %Object{value: 3}} = map
      refute map[:b]

      assert 0 == map_size(@cache.get_many([]))
      assert :ok == @cache.flush()
    end

    test "set_many" do
      entries = [{0, nil} | for(x <- 1..3, do: {x, x})]
      assert :ok == @cache.set_many(entries, ttl: 2)

      refute @cache.get(0)
      for x <- 1..3, do: assert(x == @cache.get(x))
      :ok = Process.sleep(3000)
      for x <- 1..3, do: refute(@cache.get(x))

      assert :ok == @cache.set_many(%{"apples" => 1, "bananas" => 3})
      assert :ok == @cache.set_many(blueberries: 2, strawberries: 5)
      assert 1 == @cache.get("apples")
      assert 3 == @cache.get("bananas")
      assert 2 == @cache.get(:blueberries)
      assert 5 == @cache.get(:strawberries)

      :ok =
        @cache.set_many([
          %Object{key: :a, value: 1},
          %Object{key: :b, value: 2, expire_at: Object.expire_at(5)}
        ])

      %Object{value: 1, expire_at: nil} = @cache.get!(:a, return: :object)
      %Object{value: 2} = obj = @cache.get!(:b, return: :object)
      assert 5 == Object.remaining_ttl(obj)

      assert :ok == @cache.set_many([])
      assert :ok == @cache.set_many(%{})
      assert :ok == @cache.flush()
    end

    test "take" do
      for x <- 1..2, do: @cache.set(x, x)

      assert 1 == @cache.take(1)
      assert 2 == @cache.take(2)
      refute @cache.take(3)
      refute @cache.take(nil)

      for x <- 1..3, do: refute(@cache.get(x))

      %Object{value: "bar", key: "foo"} =
        "foo"
        |> @cache.set("bar", return: :key)
        |> @cache.take(return: :object)

      assert "world" ==
               "hello"
               |> @cache.set("world", return: :key)
               |> @cache.take(version: -1, on_conflict: :nothing, return: :key)
               |> @cache.get()

      assert "world" == @cache.take("hello", version: -1, on_conflict: :override)
      refute @cache.get("hello")

      assert_raise Nebulex.VersionConflictError, fn ->
        :b
        |> @cache.set("hello", return: :key)
        |> @cache.take(version: -1)
      end
    end

    test "take!" do
      assert 1 == @cache.set(1, 1)
      assert 1 == @cache.take!(1)

      assert_raise KeyError, fn ->
        @cache.take!(1)
      end

      assert_raise KeyError, fn ->
        @cache.take!(nil)
      end
    end

    test "has_key?" do
      for x <- 1..2, do: @cache.set(x, x)

      assert @cache.has_key?(1)
      assert @cache.has_key?(2)
      refute @cache.has_key?(3)
    end

    test "has_key? expired key" do
      assert "bar" == @cache.set("foo", "bar", ttl: 1)
      assert @cache.has_key?("foo")

      :timer.sleep(2100)
      refute @cache.has_key?("foo")
    end

    test "object_info ttl" do
      assert 1 == @cache.set(:a, 1, ttl: 3)
      assert 2 == @cache.set(:b, 2)

      assert 3 == @cache.object_info(:a, :ttl)
      :ok = Process.sleep(500)
      assert 1 < @cache.object_info(:a, :ttl)
      assert :infinity == @cache.object_info(:b, :ttl)
      refute @cache.object_info(:c, :ttl)
    end

    test "object_info version" do
      %Object{version: vsn} = @cache.set(:a, 1, return: :object)
      assert vsn == @cache.object_info(:a, :version)
      refute @cache.object_info(:b, :version)
    end

    test "object_info error" do
      assert 1 == @cache.set(:a, 1, ttl: 3)

      assert_raise ArgumentError, fn ->
        @cache.object_info(:a, :invalid)
      end
    end

    test "expire" do
      assert 1 == @cache.set(:a, 1, ttl: 3)
      assert 3 == @cache.object_info(:a, :ttl)

      exp = @cache.expire(:a, 5)
      assert 5 == @cache.object_info(:a, :ttl)
      assert 5 == Object.remaining_ttl(exp)

      assert :infinity == @cache.expire(:a, :infinity)
      assert :infinity == @cache.object_info(:a, :ttl)

      refute @cache.expire(:b, 5)
    end

    test "size" do
      for x <- 1..100, do: @cache.set(x, x)
      assert 100 == @cache.size

      for x <- 1..50, do: @cache.delete(x)
      assert 50 == @cache.size

      for x <- 51..60, do: assert(@cache.get(x) == x)
      assert 50 == @cache.size()
    end

    test "flush" do
      Enum.each(1..2, fn _ ->
        for x <- 1..100, do: @cache.set(x, x)

        assert @cache.flush() == :ok
        :ok = Process.sleep(500)

        for x <- 1..100, do: refute(@cache.get(x))
      end)
    end

    test "update" do
      for x <- 1..2, do: @cache.set(x, x)

      fun = &Integer.to_string/1

      assert "1" == @cache.update(1, 1, fun)
      assert "2" == @cache.update(2, 1, fun)
      assert 1 == @cache.update(3, 1, fun)
      refute @cache.update(4, nil, fun)
      refute @cache.get(4)

      %Object{key: 11, value: 1, expire_at: _, version: _} =
        @cache.update(11, 1, fun, return: :object)

      assert 1 == @cache.update(3, 3, fun, version: -1, on_conflict: :nothing)

      assert "1" == @cache.update(3, 3, fun, version: -1, on_conflict: :override)

      assert_raise Nebulex.VersionConflictError, fn ->
        :a
        |> @cache.set(1, return: :key)
        |> @cache.update(0, fun, version: -1)
      end
    end

    test "update_counter" do
      assert 1 == @cache.update_counter(:counter)
      assert 2 == @cache.update_counter(:counter)
      assert 4 == @cache.update_counter(:counter, 2)
      assert 7 == @cache.update_counter(:counter, 3)
      assert 7 == @cache.update_counter(:counter, 0)

      assert 7 == :counter |> @cache.get() |> to_int()

      assert 6 == @cache.update_counter(:counter, -1)
      assert 5 == @cache.update_counter(:counter, -1)
      assert 3 == @cache.update_counter(:counter, -2)
      assert 0 == @cache.update_counter(:counter, -3)

      %Object{value: v, expire_at: nil} = @cache.get(:counter, return: :object)
      assert 0 == to_int(v)

      assert_raise ArgumentError, fn ->
        @cache.update_counter(:counter, "foo")
      end
    end

    test "update_counter and then ttl" do
      assert 1 == @cache.update_counter(:counter, 1)
      assert :infinity == @cache.object_info(:counter, :ttl)

      assert 1 == :counter |> @cache.expire(1) |> Object.remaining_ttl()
      :ok = Process.sleep(1010)
      refute @cache.get(:counter)
    end

    test "key expiration with ttl" do
      assert 11 ==
               1
               |> @cache.set(11, ttl: 2, return: :key)
               |> @cache.get!()

      :ok = Process.sleep(500)
      assert 11 == @cache.get(1)
      :ok = Process.sleep(1510)
      refute @cache.get(1)

      ops = [
        set: ["foo", "bar", [ttl: 2]],
        set_many: [[{"foo", "bar"}], [ttl: 2]]
      ]

      for {action, args} <- ops do
        assert apply(@cache, action, args)
        :ok = Process.sleep(900)
        assert "bar" == @cache.get("foo")
        :ok = Process.sleep(1200)
        refute @cache.get("foo")

        assert apply(@cache, action, args)
        :ok = Process.sleep(900)
        assert "bar" == @cache.get("foo")
        :ok = Process.sleep(1200)
        refute @cache.get("foo")
      end
    end

    test "object ttl" do
      obj =
        1
        |> @cache.set(11, ttl: 3, return: :key)
        |> @cache.get!(return: :object)

      for x <- 3..0 do
        assert x == Object.remaining_ttl(obj)
        :timer.sleep(1000)
      end

      ttl =
        1
        |> @cache.set(11, ttl: 3, return: :object)
        |> Object.remaining_ttl()

      assert ttl > 1

      assert :infinity == Object.remaining_ttl(nil)
    end

    test "get_and_update an existing object with ttl" do
      assert 2 ==
               1
               |> @cache.set(1, ttl: 2, return: :object)
               |> Object.remaining_ttl()

      :ok = Process.sleep(500)

      assert {1, 2} == @cache.get_and_update(1, &Partitioned.get_and_update_fun/1)
      refute @cache.get(1, return: :object).expire_at

      :ok = Process.sleep(2000)
      assert 2 == @cache.get(1)
    end

    test "update an existing object with ttl" do
      assert 2 ==
               1
               |> @cache.set(1, ttl: 2, return: :object)
               |> Object.remaining_ttl()

      :ok = Process.sleep(500)

      assert "1" == @cache.update(1, 10, &Integer.to_string/1)
      refute @cache.get(1, return: :object).expire_at

      :ok = Process.sleep(2000)
      assert "1" == @cache.get(1)
    end

    test "fail on Nebulex.VersionConflictError" do
      assert 1 == @cache.set(1, 1)

      message = ~r"could not perform cache action because versions mismatch."

      assert_raise Nebulex.VersionConflictError, message, fn ->
        @cache.set(1, 2, version: -1)
      end
    end

    ## Helpers

    defp to_int(data) when is_integer(data), do: data
    defp to_int(data) when is_binary(data), do: String.to_integer(data)
  end
end
