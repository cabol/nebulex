defmodule Nebulex.Cache.EntryTest do
  import Nebulex.CacheCase

  deftests do
    describe "put/3" do
      test "puts the given entry into the cache", %{cache: cache} do
        for x <- 1..4, do: assert(cache.put(x, x) == :ok)

        assert cache.get(1) == 1
        assert cache.get(2) == 2

        for x <- 3..4, do: assert(cache.put(x, x * x) == :ok)
        assert cache.get(3) == 9
        assert cache.get(4) == 16
      end

      test "nil value has not any effect", %{cache: cache} do
        assert cache.put("foo", nil) == :ok
        refute cache.get("foo")
      end

      test "raises when invalid option is given", %{cache: cache} do
        assert_raise ArgumentError, ~r"expected ttl: to be a valid timeout", fn ->
          cache.put("hello", "world", ttl: "1")
        end
      end
    end

    describe "put_new/3" do
      test "puts the given entry into the cache if the key does not exist", %{cache: cache} do
        assert cache.put_new("foo", "bar")
        assert cache.get("foo") == "bar"
      end

      test "do nothing if key does exist already", %{cache: cache} do
        :ok = cache.put("foo", "bar")

        refute cache.put_new("foo", "bar bar")
        assert cache.get("foo") == "bar"
      end

      test "nil value has not any effect", %{cache: cache} do
        assert cache.put_new(:mykey, nil)
        refute cache.get(:mykey)
      end

      test "raises when invalid option is given", %{cache: cache} do
        assert_raise ArgumentError, ~r"expected ttl: to be a valid timeout", fn ->
          cache.put_new("hello", "world", ttl: "1")
        end
      end
    end

    describe "put_new!/3" do
      test "puts the given entry into the cache if the key does not exist", %{cache: cache} do
        assert cache.put_new!("hello", "world")
        assert cache.get("hello") == "world"
      end

      test "raises when the key does exist in cache", %{cache: cache} do
        :ok = cache.put("hello", "world")

        message = ~r"key \"hello\" already exists in cache"

        assert_raise Nebulex.KeyAlreadyExistsError, message, fn ->
          cache.put_new!("hello", "world world")
        end
      end
    end

    describe "replace/3" do
      test "replaces the cached entry with a new value", %{cache: cache} do
        refute cache.replace("foo", "bar")

        assert cache.put("foo", "bar") == :ok
        assert cache.get("foo") == "bar"

        assert cache.replace("foo", "bar bar")
        assert cache.get("foo") == "bar bar"
      end

      test "nil value has not any effect", %{cache: cache} do
        :ok = cache.put("hello", "world")

        assert cache.replace("hello", nil)
        assert cache.get("hello") == "world"
      end

      test "raises when invalid option is given", %{cache: cache} do
        assert_raise ArgumentError, ~r"expected ttl: to be a valid timeout", fn ->
          cache.replace("hello", "world", ttl: "1")
        end
      end
    end

    describe "replace!/3" do
      test "replaces the cached entry with a new value", %{cache: cache} do
        :ok = cache.put("foo", "bar")

        assert cache.replace!("foo", "bar bar")
        assert cache.get("foo") == "bar bar"
      end

      test "raises when the key does not exist in cache", %{cache: cache} do
        assert_raise KeyError, fn ->
          cache.replace!("foo", "bar")
        end
      end
    end

    describe "put_all/2" do
      test "puts the given entries at once", %{cache: cache} do
        assert cache.put_all(%{"apples" => 1, "bananas" => 3})
        assert cache.put_all(blueberries: 2, strawberries: 5)
        assert cache.get("apples") == 1
        assert cache.get("bananas") == 3
        assert cache.get(:blueberries) == 2
        assert cache.get(:strawberries) == 5
      end

      test "empty list or map has not any effect", %{cache: cache} do
        assert cache.put_all([])
        assert cache.put_all(%{})
        assert count = cache.count_all()
        assert cache.delete_all() == count
      end

      test "puts the given entries using different data types at once", %{cache: cache} do
        entries =
          Enum.reduce(1..100, %{}, fn elem, acc ->
            sample = %{
              elem => elem,
              :"atom#{elem}" => elem,
              "#{elem}" => elem,
              {:tuple, elem} => elem,
              <<100, elem>> => elem,
              [elem] => elem
            }

            Map.merge(acc, sample)
          end)

        assert cache.put_all(entries) == :ok
        for {k, v} <- entries, do: assert(cache.get(k) == v)
      end

      test "raises when invalid option is given", %{cache: cache} do
        assert_raise ArgumentError, ~r"expected ttl: to be a valid timeout", fn ->
          cache.put_all(%{"apples" => 1, "bananas" => 3}, ttl: "1")
        end
      end
    end

    describe "put_new_all/2" do
      test "puts the given entries only if none of the keys does exist already", %{cache: cache} do
        assert cache.put_new_all(%{"apples" => 1, "bananas" => 3})
        assert cache.get("apples") == 1
        assert cache.get("bananas") == 3

        refute cache.put_new_all(%{"apples" => 3, "oranges" => 1})
        assert cache.get("apples") == 1
        assert cache.get("bananas") == 3
        refute cache.get("oranges")
      end

      test "raises when invalid option is given", %{cache: cache} do
        assert_raise ArgumentError, ~r"expected ttl: to be a valid timeout", fn ->
          cache.put_all(%{"apples" => 1, "bananas" => 3}, ttl: "1")
        end
      end
    end

    describe "get/2" do
      test "retrieves a cached entry", %{cache: cache} do
        for x <- 1..5 do
          :ok = cache.put(x, x)
          assert cache.get(x) == x
        end
      end

      test "returns nil if key does not exist in cache", %{cache: cache} do
        refute cache.get("non-existent")
      end
    end

    describe "get!/2" do
      test "retrieves a cached entry", %{cache: cache} do
        for x <- 1..5 do
          :ok = cache.put(x, x)
          assert cache.get!(x) == x
        end
      end

      test "raises when the key does not exist in cache", %{cache: cache} do
        assert_raise KeyError, fn ->
          cache.get!("non-existent")
        end
      end
    end

    describe "get_all/2" do
      test "returns a map with the given keys", %{cache: cache} do
        assert cache.put_all(a: 1, c: 3)
        assert cache.get_all([:a, :b, :c]) == %{a: 1, c: 3}
        assert cache.delete_all() == 2
      end

      test "returns an empty map when none of the given keys is in cache", %{cache: cache} do
        assert map_size(cache.get_all(["foo", "bar", 1, :a])) == 0
      end

      test "returns an empty map when the given key list is empty", %{cache: cache} do
        assert map_size(cache.get_all([])) == 0
      end
    end

    describe "delete/2" do
      test "deletes the given key", %{cache: cache} do
        for x <- 1..3, do: cache.put(x, x * 2)

        assert cache.get(1) == 2
        assert cache.delete(1) == :ok
        refute cache.get(1)

        assert cache.get(2) == 4
        assert cache.get(3) == 6

        assert cache.delete(:non_existent) == :ok
        refute cache.get(:non_existent)
      end
    end

    describe "take/2" do
      test "returns the given key and removes it from cache", %{cache: cache} do
        for x <- 1..5 do
          :ok = cache.put(x, x)
          assert cache.take(x) == x
          refute cache.take(x)
        end
      end

      test "returns nil if the key does not exist in cache", %{cache: cache} do
        refute cache.take(:non_existent)
        refute cache.take(nil)
      end
    end

    describe "take!/2" do
      test "returns the given key and removes it from cache", %{cache: cache} do
        assert cache.put(1, 1) == :ok
        assert cache.take!(1) == 1
      end

      test "raises when the key does not exist in cache", %{cache: cache} do
        assert_raise KeyError, fn ->
          cache.take!(:non_existent)
        end

        assert_raise KeyError, fn ->
          cache.take!(nil)
        end
      end
    end

    describe "has_key?/1" do
      test "returns true if key does exist in cache", %{cache: cache} do
        for x <- 1..5 do
          :ok = cache.put(x, x)
          assert cache.has_key?(x)
        end
      end

      test "returns false if key does not exist in cache", %{cache: cache} do
        refute cache.has_key?(:non_existent)
        refute cache.has_key?(nil)
      end
    end

    describe "update/4" do
      test "updates an entry under a key applying a function on the value", %{cache: cache} do
        :ok = cache.put("foo", "123")
        :ok = cache.put("bar", "foo")

        assert cache.update("foo", 1, &String.to_integer/1) == 123
        assert cache.update("bar", "init", &String.to_atom/1) == :foo
      end

      test "creates the entry with the default value if key does not exist", %{cache: cache} do
        assert cache.update("foo", "123", &Integer.to_string/1) == "123"
      end

      test "has not any effect if the given value is nil", %{cache: cache} do
        refute cache.update("bar", nil, &Integer.to_string/1)
        refute cache.get("bar")
      end
    end

    describe "incr/3" do
      test "increments a counter by the given amount", %{cache: cache} do
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
      end

      test "increments a counter by the given amount with default", %{cache: cache} do
        assert cache.incr(:counter1, 1, default: 10) == 11
        assert cache.incr(:counter2, 2, default: 10) == 12
        assert cache.incr(:counter3, -2, default: 10) == 8
      end

      test "increments a counter by the given amount ignoring the default", %{cache: cache} do
        assert cache.incr(:counter) == 1
        assert cache.incr(:counter, 1, default: 10) == 2
        assert cache.incr(:counter, -1, default: 100) == 1
      end

      test "raises when amount is invalid", %{cache: cache} do
        assert_raise ArgumentError, ~r"expected amount to be an integer", fn ->
          cache.incr(:counter, "foo")
        end
      end

      test "raises when default is invalid", %{cache: cache} do
        assert_raise ArgumentError, ~r"expected default: to be an integer", fn ->
          cache.incr(:counter, 1, default: :invalid)
        end
      end
    end

    describe "decr/3" do
      test "decrements a counter by the given amount", %{cache: cache} do
        assert cache.decr(:counter) == -1
        assert cache.decr(:counter) == -2
        assert cache.decr(:counter, 2) == -4
        assert cache.decr(:counter, 3) == -7
        assert cache.decr(:counter, 0) == -7

        assert :counter |> cache.get() |> to_int() == -7

        assert cache.decr(:counter, -1) == -6
        assert cache.decr(:counter, -1) == -5
        assert cache.decr(:counter, -2) == -3
        assert cache.decr(:counter, -3) == 0
      end

      test "decrements a counter by the given amount with default", %{cache: cache} do
        assert cache.decr(:counter1, 1, default: 10) == 9
        assert cache.decr(:counter2, 2, default: 10) == 8
        assert cache.decr(:counter3, -2, default: 10) == 12
      end

      test "decrements a counter by the given amount ignoring the default", %{cache: cache} do
        assert cache.decr(:counter) == -1
        assert cache.decr(:counter, 1, default: 10) == -2
        assert cache.decr(:counter, -1, default: 100) == -1
      end

      test "raises when amount is invalid", %{cache: cache} do
        assert_raise ArgumentError, ~r"expected amount to be an integer", fn ->
          cache.decr(:counter, "foo")
        end
      end

      test "raises when default is invalid", %{cache: cache} do
        assert_raise ArgumentError, ~r"expected default: to be an integer", fn ->
          cache.decr(:counter, 1, default: :invalid)
        end
      end
    end

    ## Helpers

    defp to_int(data) when is_integer(data), do: data
    defp to_int(data) when is_binary(data), do: String.to_integer(data)
  end
end
