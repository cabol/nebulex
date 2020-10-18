defmodule Nebulex.Cache.EntryTest do
  import Nebulex.CacheCase

  deftests "cache" do
    test "delete", %{cache: cache} do
      for x <- 1..3, do: cache.put(x, x * 2)

      assert cache.get(1) == 2
      assert cache.delete(1) == :ok
      refute cache.get(1)

      assert cache.get(2) == 4
      assert cache.get(3) == 6

      assert cache.delete(:non_existent) == :ok
      refute cache.get(:non_existent)
    end

    test "get", %{cache: cache} do
      for x <- 1..2, do: cache.put(x, x)

      assert cache.get(1) == 1
      assert cache.get(2) == 2
      refute cache.get(3)
    end

    test "get!", %{cache: cache} do
      for x <- 1..2, do: cache.put(x, x)

      assert cache.get!(1) == 1
      assert cache.get!(2) == 2

      assert_raise KeyError, fn ->
        cache.get!(3)
      end
    end

    test "get_all", %{cache: cache} do
      assert cache.put_all(a: 1, c: 3)
      assert cache.get_all([:a, :b, :c]) == %{a: 1, c: 3}
      assert map_size(cache.get_all([])) == 0
      assert cache.flush() == 2
    end

    test "put", %{cache: cache} do
      for x <- 1..4, do: assert(:ok == cache.put(x, x))

      assert cache.get(1) == 1
      assert cache.get(2) == 2

      for x <- 3..4, do: assert(:ok = cache.put(x, x * x))
      assert cache.get(3) == 9
      assert cache.get(4) == 16

      assert cache.put("foo", nil) == :ok
      refute cache.get("foo")
    end

    test "put_new", %{cache: cache} do
      assert cache.put_new("foo", "bar")
      assert cache.get("foo") == "bar"

      refute cache.put_new("foo", "bar bar")
      assert cache.get("foo") == "bar"

      assert cache.put_new(:mykey, nil)
      refute cache.get(:mykey)
    end

    test "put_new!", %{cache: cache} do
      assert cache.put_new!("hello", "world")

      message = ~r"key \"hello\" already exists in cache"

      assert_raise Nebulex.KeyAlreadyExistsError, message, fn ->
        cache.put_new!("hello", "world world")
      end
    end

    test "replace", %{cache: cache} do
      refute cache.replace("foo", "bar")

      assert cache.put("foo", "bar") == :ok
      assert cache.get("foo") == "bar"

      assert cache.replace("foo", "bar bar")
      assert cache.get("foo") == "bar bar"

      assert cache.replace(:mykey, nil)
      refute cache.get(:mykey)
    end

    test "replace!", %{cache: cache} do
      assert_raise KeyError, fn ->
        cache.replace!("foo", "bar")
      end

      assert cache.put("foo", "bar") == :ok
      assert cache.replace!("foo", "bar bar")
      assert cache.get("foo") == "bar bar"
    end

    test "put key terms", %{cache: cache} do
      refute cache.get({:mykey, 1, "hello"})
      assert cache.put({:mykey, 1, "hello"}, "world") == :ok
      assert cache.get({:mykey, 1, "hello"}) == "world"

      refute cache.get(%{a: 1, b: 2})
      assert cache.put(%{a: 1, b: 2}, "value") == :ok
      assert cache.get(%{a: 1, b: 2}) == "value"
    end

    test "put with invalid options", %{cache: cache} do
      for action <- [:put, :put_new, :replace] do
        assert_raise ArgumentError, ~r"expected ttl: to be a valid timeout", fn ->
          apply(cache, action, ["hello", "world", [ttl: "1"]])
        end
      end
    end

    test "put_all", %{cache: cache} do
      assert cache.put_all(%{"apples" => 1, "bananas" => 3})
      assert cache.put_all(blueberries: 2, strawberries: 5)
      assert cache.get("apples") == 1
      assert cache.get("bananas") == 3
      assert cache.get(:blueberries) == 2
      assert cache.get(:strawberries) == 5

      assert cache.put_all([])
      assert cache.put_all(%{})
      assert count = cache.size()
      assert cache.flush() == count
    end

    test "put_all keys using different data types", %{cache: cache} do
      entries =
        Enum.reduce(1..100, %{}, fn elem, acc ->
          sample = %{
            elem => elem,
            :"atom#{elem}" => elem,
            "#{elem}" => elem,
            {:tuple, elem} => elem,
            <<100, elem>> => elem
          }

          Map.merge(acc, sample)
        end)

      assert cache.put_all(entries) == :ok
      for {k, v} <- entries, do: assert(cache.get(k) == v)
    end

    test "put_new_all", %{cache: cache} do
      assert cache.put_new_all(%{"apples" => 1, "bananas" => 3})
      assert cache.get("apples") == 1
      assert cache.get("bananas") == 3

      refute cache.put_new_all(%{"apples" => 3, "oranges" => 1})
      assert cache.get("apples") == 1
      assert cache.get("bananas") == 3
      refute cache.get("oranges")
    end

    test "put_all with invalid options", %{cache: cache} do
      assert_raise ArgumentError, ~r"expected ttl: to be a valid timeout", fn ->
        cache.put_all(%{"apples" => 1, "bananas" => 3}, ttl: "1")
      end
    end

    test "take", %{cache: cache} do
      for x <- 1..2, do: cache.put(x, x)

      assert cache.take(1) == 1
      assert cache.take(2) == 2
      refute cache.take(3)
      refute cache.take(nil)

      for x <- 1..3, do: refute(cache.get(x))
    end

    test "take!", %{cache: cache} do
      assert cache.put(1, 1) == :ok
      assert cache.take!(1) == 1

      assert_raise KeyError, fn ->
        cache.take!(1)
      end

      assert_raise KeyError, fn ->
        cache.take!(nil)
      end
    end

    test "has_key?", %{cache: cache} do
      for x <- 1..2, do: cache.put(x, x)

      assert cache.has_key?(1)
      assert cache.has_key?(2)
      refute cache.has_key?(3)
    end

    test "size", %{cache: cache} do
      for x <- 1..100, do: cache.put(x, x)
      assert cache.size() == 100

      for x <- 1..50, do: cache.delete(x)
      assert cache.size() == 50

      for x <- 51..60, do: assert(cache.get(x) == x)
      assert cache.size() == 50
    end

    test "flush", %{cache: cache} do
      Enum.each(1..2, fn _ ->
        for x <- 1..100, do: cache.put(x, x)

        assert cache.flush() == 100
        :ok = Process.sleep(500)

        for x <- 1..100, do: refute(cache.get(x))
      end)
    end

    test "update", %{cache: cache} do
      for x <- 1..2, do: cache.put(x, x)

      fun = &Integer.to_string/1

      assert cache.update(1, 1, fun) == "1"
      assert cache.update(2, 1, fun) == "2"
      assert cache.update(3, 1, fun) == 1
      refute cache.update(4, nil, fun)
      refute cache.get(4)
    end

    test "incr", %{cache: cache} do
      assert cache.incr(:counter) == 1
      assert cache.incr(:counter) == 2
      assert cache.incr(:counter, 2) == 4
      assert cache.incr(:counter, 3) == 7
      assert cache.incr(:counter, 0) == 7

      assert :counter |> cache.get() |> to_int() == 7

      assert cache.incr(:counter, -1) == 6
      assert cache.incr(:counter, -1) == 5
      assert cache.incr(:counter, -2) == 3
      assert cache.incr(:counter, -3) == 0

      assert_raise ArgumentError, fn ->
        cache.incr(:counter, "foo")
      end
    end

    ## Helpers

    defp to_int(data) when is_integer(data), do: data
    defp to_int(data) when is_binary(data), do: String.to_integer(data)
  end
end
