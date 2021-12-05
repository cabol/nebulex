defmodule Nebulex.Cache.EntryTest do
  import Nebulex.CacheCase

  deftests do
    import Mock

    describe "put/3" do
      test "puts the given entry into the cache", %{cache: cache} do
        for x <- 1..4, do: assert(cache.put(x, x) == :ok)

        assert cache.fetch!(1) == 1
        assert cache.fetch!(2) == 2

        for x <- 3..4, do: assert(cache.put(x, x * x) == :ok)
        assert cache.fetch!(3) == 9
        assert cache.fetch!(4) == 16
      end

      test "puts a nil value", %{cache: cache} do
        assert cache.put("foo", nil) == :ok
        assert cache.fetch("foo") == {:ok, nil}
      end

      test "raises when invalid option is given", %{cache: cache} do
        assert_raise ArgumentError, ~r"expected ttl: to be a valid timeout", fn ->
          cache.put("hello", "world", ttl: "1")
        end
      end

      test_with_mock "returns an error", %{cache: cache}, cache.__adapter__(), [:passthrough],
        put: fn _, _, _, _, _, _ -> {:error, %Nebulex.Error{reason: :error}} end do
        assert cache.put("hello", "world") ==
                 {:error, %Nebulex.Error{module: Nebulex.Error, reason: :error}}
      end
    end

    describe "put!/3" do
      test "puts the given entry into the cache", %{cache: cache} do
        for x <- 1..4, do: assert(cache.put!(x, x) == :ok)

        assert cache.fetch!(1) == 1
        assert cache.fetch!(2) == 2

        for x <- 3..4, do: assert(cache.put!(x, x * x) == :ok)
        assert cache.fetch!(3) == 9
        assert cache.fetch!(4) == 16
      end

      test_with_mock "raises an error", %{cache: cache}, cache.__adapter__(), [:passthrough],
        put: fn _, _, _, _, _, _ -> {:error, %RuntimeError{message: "error"}} end do
        assert_raise RuntimeError, ~r"error", fn ->
          cache.put!("hello", "world")
        end
      end
    end

    describe "put_new/3" do
      test "puts the given entry into the cache if the key does not exist", %{cache: cache} do
        assert cache.put_new("foo", "bar") == {:ok, true}
        assert cache.fetch!("foo") == "bar"
      end

      test "do nothing if key does exist already", %{cache: cache} do
        :ok = cache.put("foo", "bar")

        assert cache.put_new("foo", "bar bar") == {:ok, false}
        assert cache.fetch!("foo") == "bar"
      end

      test "puts a new nil value", %{cache: cache} do
        assert cache.put_new(:mykey, nil) == {:ok, true}
        assert cache.fetch(:mykey) == {:ok, nil}
      end

      test "raises when invalid option is given", %{cache: cache} do
        assert_raise ArgumentError, ~r"expected ttl: to be a valid timeout", fn ->
          cache.put_new("hello", "world", ttl: "1")
        end
      end

      test_with_mock "returns an error", %{cache: cache}, cache.__adapter__(), [:passthrough],
        put: fn _, _, _, _, _, _ -> {:error, %Nebulex.Error{reason: :error}} end do
        assert cache.put_new("hello", "world") ==
                 {:error, %Nebulex.Error{module: Nebulex.Error, reason: :error}}
      end
    end

    describe "put_new!/3" do
      test "puts the given entry into the cache if the key does not exist", %{cache: cache} do
        assert cache.put_new!("hello", "world") == true
        assert cache.fetch!("hello") == "world"
      end

      test "raises false if the key does exist already", %{cache: cache} do
        assert cache.put_new!("hello", "world") == true
        assert cache.put_new!("hello", "world") == false
      end

      test_with_mock "raises an error", %{cache: cache}, cache.__adapter__(), [:passthrough],
        put: fn _, _, _, _, _, _ -> {:error, %Nebulex.Error{reason: :error}} end do
        assert_raise Nebulex.Error, ~r"Nebulex error:\n\n:error", fn ->
          cache.put_new!("hello", "world")
        end
      end
    end

    describe "replace/3" do
      test "replaces the cached entry with a new value", %{cache: cache} do
        assert cache.replace("foo", "bar") == {:ok, false}

        assert cache.put("foo", "bar") == :ok
        assert cache.fetch!("foo") == "bar"

        assert cache.replace("foo", "bar bar") == {:ok, true}
        assert cache.fetch!("foo") == "bar bar"
      end

      test "existing value with nil", %{cache: cache} do
        :ok = cache.put("hello", "world")

        assert cache.replace("hello", nil) == {:ok, true}
        assert cache.fetch("hello") == {:ok, nil}
      end

      test "raises when invalid option is given", %{cache: cache} do
        assert_raise ArgumentError, ~r"expected ttl: to be a valid timeout", fn ->
          cache.replace("hello", "world", ttl: "1")
        end
      end

      test_with_mock "returns an error", %{cache: cache}, cache.__adapter__(), [:passthrough],
        put: fn _, _, _, _, _, _ -> {:error, %Nebulex.Error{reason: :error}} end do
        assert cache.replace("hello", "world") ==
                 {:error, %Nebulex.Error{module: Nebulex.Error, reason: :error}}
      end
    end

    describe "replace!/3" do
      test "replaces the cached entry with a new value", %{cache: cache} do
        assert cache.put("foo", "bar") == :ok
        assert cache.replace!("foo", "bar bar") == true
        assert cache.fetch!("foo") == "bar bar"
      end

      test "returns false when the key is not found", %{cache: cache} do
        assert cache.replace!("foo", "bar") == false
      end

      test_with_mock "raises an error", %{cache: cache}, cache.__adapter__(), [:passthrough],
        put: fn _, _, _, _, _, _ -> {:error, %Nebulex.Error{reason: :error}} end do
        assert_raise Nebulex.Error, ~r"Nebulex error:\n\n:error", fn ->
          cache.replace!("hello", "world")
        end
      end
    end

    describe "put_all/2" do
      test "puts the given entries at once", %{cache: cache} do
        assert cache.put_all(%{"apples" => 1, "bananas" => 3}) == :ok
        assert cache.put_all(blueberries: 2, strawberries: 5) == :ok
        assert cache.fetch!("apples") == 1
        assert cache.fetch!("bananas") == 3
        assert cache.fetch!(:blueberries) == 2
        assert cache.fetch!(:strawberries) == 5
      end

      test "empty list or map has not any effect", %{cache: cache} do
        assert cache.put_all([]) == :ok
        assert cache.put_all(%{}) == :ok
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
              <<100, elem>> => elem
            }

            Map.merge(acc, sample)
          end)

        assert cache.put_all(entries) == :ok
        for {k, v} <- entries, do: assert(cache.fetch!(k) == v)
      end

      test "raises when invalid option is given", %{cache: cache} do
        assert_raise ArgumentError, ~r"expected ttl: to be a valid timeout", fn ->
          cache.put_all(%{"apples" => 1, "bananas" => 3}, ttl: "1")
        end
      end

      test_with_mock "returns an error", %{cache: cache}, cache.__adapter__(), [:passthrough],
        put_all: fn _, _, _, _, _ -> {:error, %Nebulex.Error{reason: :error}} end do
        assert cache.put_all(%{"apples" => 1, "bananas" => 3}) ==
                 {:error, %Nebulex.Error{module: Nebulex.Error, reason: :error}}
      end
    end

    describe "put_all!/2" do
      test "puts the given entries at once", %{cache: cache} do
        assert cache.put_all!(%{"apples" => 1, "bananas" => 3}) == :ok
        assert cache.put_all!(blueberries: 2, strawberries: 5) == :ok
        assert cache.fetch!("apples") == 1
        assert cache.fetch!("bananas") == 3
        assert cache.fetch!(:blueberries) == 2
        assert cache.fetch!(:strawberries) == 5
      end

      test_with_mock "raises an error", %{cache: cache}, cache.__adapter__(), [:passthrough],
        put_all: fn _, _, _, _, _ -> {:error, %Nebulex.Error{reason: :error}} end do
        assert_raise Nebulex.Error, ~r"Nebulex error:\n\n:error", fn ->
          cache.put_all!(other: 1)
        end
      end
    end

    describe "put_new_all/2" do
      test "puts the given entries only if none of the keys does exist already", %{cache: cache} do
        assert cache.put_new_all(%{"apples" => 1, "bananas" => 3}) == {:ok, true}
        assert cache.fetch!("apples") == 1
        assert cache.fetch!("bananas") == 3

        assert cache.put_new_all(%{"apples" => 3, "oranges" => 1}) == {:ok, false}
        assert cache.fetch!("apples") == 1
        assert cache.fetch!("bananas") == 3
        refute cache.get!("oranges")
      end

      test "raises when invalid option is given", %{cache: cache} do
        assert_raise ArgumentError, ~r"expected ttl: to be a valid timeout", fn ->
          cache.put_new_all(%{"apples" => 1, "bananas" => 3}, ttl: "1")
        end
      end

      test_with_mock "returns an error", %{cache: cache}, cache.__adapter__(), [:passthrough],
        put_all: fn _, _, _, _, _ -> {:error, %Nebulex.Error{reason: :error}} end do
        assert cache.put_new_all(%{"apples" => 1, "bananas" => 3}) ==
                 {:error, %Nebulex.Error{module: Nebulex.Error, reason: :error}}
      end
    end

    describe "put_new_all!/2" do
      test "puts the given entries only if none of the keys does exist already", %{cache: cache} do
        assert cache.put_new_all!(%{"apples" => 1, "bananas" => 3}) == true
        assert cache.fetch!("apples") == 1
        assert cache.fetch!("bananas") == 3
      end

      test "raises an error if any of the keys does exist already", %{cache: cache} do
        assert cache.put_new_all!(%{"apples" => 1, "bananas" => 3}) == true
        assert cache.put_new_all!(%{"apples" => 3, "oranges" => 1}) == false
      end

      test_with_mock "raises an error", %{cache: cache}, cache.__adapter__(), [:passthrough],
        put_all: fn _, _, _, _, _ -> {:error, %Nebulex.Error{reason: :error}} end do
        assert_raise Nebulex.Error, ~r"Nebulex error:\n\n:error", fn ->
          cache.put_new_all!(other: 1)
        end
      end
    end

    describe "fetch/2" do
      test "retrieves a cached entry", %{cache: cache} do
        for x <- 1..5 do
          :ok = cache.put(x, x)
          assert cache.fetch(x) == {:ok, x}
        end
      end

      test "returns {:error, :not_found} if key does not exist in cache", %{cache: cache} do
        assert {:error, %Nebulex.KeyError{key: "non-existent"}} = cache.fetch("non-existent")
      end

      test_with_mock "raises an error", %{cache: cache}, cache.__adapter__(), [:passthrough],
        fetch: fn _, _, _ -> {:error, %Nebulex.Error{reason: :error}} end do
        assert cache.fetch(1) == {:error, %Nebulex.Error{module: Nebulex.Error, reason: :error}}
      end
    end

    describe "fetch!/2" do
      test "retrieves a cached entry", %{cache: cache} do
        for x <- 1..5 do
          :ok = cache.put(x, x)
          assert cache.fetch!(x) == x
        end
      end

      test "raises when the key does not exist in cache", %{cache: cache, name: name} do
        msg = ~r"key \"non-existent\" not found in cache: #{inspect(name)}"

        assert_raise Nebulex.KeyError, msg, fn ->
          cache.fetch!("non-existent")
        end
      end

      test_with_mock "raises an error", %{cache: cache}, cache.__adapter__(), [:passthrough],
        fetch: fn _, _, _ -> {:error, %Nebulex.Error{reason: :error}} end do
        assert_raise Nebulex.Error, ~r"Nebulex error:\n\n:error", fn ->
          cache.fetch!("raise")
        end
      end
    end

    describe "get/2" do
      test "retrieves a cached entry", %{cache: cache} do
        for x <- 1..5 do
          :ok = cache.put(x, x)
          assert cache.get(x) == {:ok, x}
        end
      end

      test "returns default if key does not exist in cache", %{cache: cache} do
        assert cache.get("non-existent") == {:ok, nil}
        assert cache.get("non-existent", "default") == {:ok, "default"}
      end

      test_with_mock "raises an error", %{cache: cache}, cache.__adapter__(), [:passthrough],
        fetch: fn _, _, _ -> {:error, %Nebulex.Error{reason: :error}} end do
        assert {:error, %Nebulex.Error{reason: :error}} = cache.get("error")
      end
    end

    describe "get!/2" do
      test "retrieves a cached entry", %{cache: cache} do
        for x <- 1..5 do
          :ok = cache.put(x, x)
          assert cache.get!(x) == x
        end
      end

      test "returns default if key does not exist in cache", %{cache: cache} do
        refute cache.get!("non-existent")
        assert cache.get!("non-existent", "default") == "default"
      end

      test_with_mock "raises an error", %{cache: cache}, cache.__adapter__(), [:passthrough],
        fetch: fn _, _, _ -> {:error, %Nebulex.Error{reason: :error}} end do
        assert_raise Nebulex.Error, ~r"Nebulex error:\n\n:error", fn ->
          cache.get!("raise")
        end
      end
    end

    describe "get_all/2" do
      test "returns a map with the given keys", %{cache: cache} do
        assert cache.put_all(a: 1, c: 3) == :ok
        assert cache.get_all([:a, :b, :c]) == {:ok, %{a: 1, c: 3}}
        assert cache.delete_all!() == 2
      end

      test "returns an empty map when none of the given keys is in cache", %{cache: cache} do
        assert cache.get_all(["foo", "bar", 1, :a]) == {:ok, %{}}
      end

      test "returns an empty map when the given key list is empty", %{cache: cache} do
        assert cache.get_all([]) == {:ok, %{}}
      end

      test_with_mock "raises an error", %{cache: cache}, cache.__adapter__(), [:passthrough],
        get_all: fn _, _, _ -> {:error, %Nebulex.Error{reason: :error}} end do
        assert cache.get_all(1) == {:error, %Nebulex.Error{module: Nebulex.Error, reason: :error}}
      end
    end

    describe "get_all!/2" do
      test "returns a map with the given keys", %{cache: cache} do
        assert cache.put_all(a: 1, c: 3) == :ok
        assert cache.get_all!([:a, :b, :c]) == %{a: 1, c: 3}
        assert cache.delete_all!() == 2
      end

      test "returns an empty map when none of the given keys is in cache", %{cache: cache} do
        assert cache.get_all!(["foo", "bar", 1, :a]) == %{}
      end

      test "returns an empty map when the given key list is empty", %{cache: cache} do
        assert cache.get_all!([]) == %{}
      end

      test_with_mock "raises an error", %{cache: cache}, cache.__adapter__(), [:passthrough],
        get_all: fn _, _, _ -> {:error, %Nebulex.Error{reason: :error}} end do
        assert_raise Nebulex.Error, ~r"Nebulex error:\n\n:error", fn ->
          cache.get_all!([:foo])
        end
      end
    end

    describe "delete/2" do
      test "deletes the given key", %{cache: cache} do
        for x <- 1..3, do: cache.put(x, x * 2)

        assert cache.fetch!(1) == 2
        assert cache.delete(1) == :ok
        refute cache.get!(1)

        assert cache.fetch!(2) == 4
        assert cache.fetch!(3) == 6

        assert cache.delete(:non_existent) == :ok
        refute cache.get!(:non_existent)
      end

      test_with_mock "raises an error", %{cache: cache}, cache.__adapter__(), [:passthrough],
        delete: fn _, _, _ -> {:error, %Nebulex.Error{reason: :error}} end do
        assert cache.delete("error") ==
                 {:error, %Nebulex.Error{module: Nebulex.Error, reason: :error}}
      end
    end

    describe "delete!/2" do
      test "deletes the given key", %{cache: cache} do
        assert cache.put("foo", "bar") == :ok

        assert cache.fetch!("foo") == "bar"
        assert cache.delete!("foo") == :ok
        refute cache.get!("foo")
      end

      test_with_mock "raises an error", %{cache: cache}, cache.__adapter__(), [:passthrough],
        delete: fn _, _, _ -> {:error, %Nebulex.Error{reason: :error}} end do
        assert_raise Nebulex.Error, ~r"Nebulex error:\n\n:error", fn ->
          cache.delete!("raise")
        end
      end
    end

    describe "take/2" do
      test "returns the given key and removes it from cache", %{cache: cache} do
        for x <- 1..5 do
          :ok = cache.put(x, x)
          assert cache.take(x) == {:ok, x}
          assert {:error, %Nebulex.KeyError{key: ^x}} = cache.take(x)
        end
      end

      test "returns nil if the key does not exist in cache", %{cache: cache} do
        assert {:error, %Nebulex.KeyError{key: :non_existent}} = cache.take(:non_existent)
        assert {:error, %Nebulex.KeyError{key: nil}} = cache.take(nil)
      end

      test_with_mock "raises an error", %{cache: cache}, cache.__adapter__(), [:passthrough],
        take: fn _, _, _ -> {:error, %Nebulex.Error{reason: :error}} end do
        assert cache.take("error") ==
                 {:error, %Nebulex.Error{module: Nebulex.Error, reason: :error}}
      end
    end

    describe "take!/2" do
      test "returns the given key and removes it from cache", %{cache: cache} do
        assert cache.put(1, 1) == :ok
        assert cache.take!(1) == 1
        assert cache.get!(1) == nil
      end

      test "raises when the key does not exist in cache", %{cache: cache, name: name} do
        msg = ~r"key \"non-existent\" not found in cache: #{inspect(name)}"

        assert_raise Nebulex.KeyError, msg, fn ->
          cache.take!("non-existent")
        end
      end

      test_with_mock "raises an error", %{cache: cache}, cache.__adapter__(), [:passthrough],
        take: fn _, _, _ -> {:error, %Nebulex.Error{reason: :error}} end do
        assert_raise Nebulex.Error, ~r"Nebulex error:\n\n:error", fn ->
          cache.take!("raise")
        end
      end
    end

    describe "exists?/1" do
      test "returns true if key does exist in cache", %{cache: cache} do
        for x <- 1..5 do
          :ok = cache.put(x, x)
          assert cache.exists?(x) == {:ok, true}
        end
      end

      test "returns false if key does not exist in cache", %{cache: cache} do
        assert cache.exists?(:non_existent) == {:ok, false}
        assert cache.exists?(nil) == {:ok, false}
      end

      test_with_mock "raises an error", %{cache: cache}, cache.__adapter__(), [:passthrough],
        exists?: fn _, _ -> {:error, %Nebulex.Error{reason: :error}} end do
        assert cache.exists?("error") ==
                 {:error, %Nebulex.Error{module: Nebulex.Error, reason: :error}}
      end
    end

    describe "update!/4" do
      test "updates an entry under a key applying a function on the value", %{cache: cache} do
        :ok = cache.put("foo", "123")
        :ok = cache.put("bar", "foo")

        assert cache.update!("foo", 1, &String.to_integer/1) == 123
        assert cache.update!("bar", "init", &String.to_atom/1) == :foo
      end

      test "creates the entry with the default value if key does not exist", %{cache: cache} do
        assert cache.update!("foo", "123", &Integer.to_string/1) == "123"
      end

      test "updates existing value with nil", %{cache: cache} do
        assert cache.update!("bar", nil, &Integer.to_string/1) == nil
        assert cache.fetch!("bar") == nil
      end

      test "raises because the cache is not started", %{cache: cache} do
        :ok = cache.stop()

        assert_raise Nebulex.Error, fn ->
          cache.update!("error", 1, &String.to_integer/1)
        end
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

      test_with_mock "raises because fetch error",
                     %{cache: cache},
                     cache.__adapter__(),
                     [:passthrough],
                     fetch: fn _, _, _ -> {:error, %Nebulex.Error{reason: :error}} end do
        assert_raise Nebulex.Error, ~r"Nebulex error:\n\n:error", fn ->
          cache.update!("error", 1, &String.to_integer/1)
        end
      end
    end

    describe "incr/3" do
      test "increments a counter by the given amount", %{cache: cache} do
        assert cache.incr(:counter) == {:ok, 1}
        assert cache.incr(:counter) == {:ok, 2}
        assert cache.incr(:counter, 2) == {:ok, 4}
        assert cache.incr(:counter, 3) == {:ok, 7}
        assert cache.incr(:counter, 0) == {:ok, 7}

        assert :counter |> cache.fetch!() |> to_int() == 7

        assert cache.incr(:counter, -1) == {:ok, 6}
        assert cache.incr(:counter, -1) == {:ok, 5}
        assert cache.incr(:counter, -2) == {:ok, 3}
        assert cache.incr(:counter, -3) == {:ok, 0}
      end

      test "increments a counter by the given amount with default", %{cache: cache} do
        assert cache.incr(:counter1, 1, default: 10) == {:ok, 11}
        assert cache.incr(:counter2, 2, default: 10) == {:ok, 12}
        assert cache.incr(:counter3, -2, default: 10) == {:ok, 8}
      end

      test "increments a counter by the given amount ignoring the default", %{cache: cache} do
        assert cache.incr(:counter) == {:ok, 1}
        assert cache.incr(:counter, 1, default: 10) == {:ok, 2}
        assert cache.incr(:counter, -1, default: 100) == {:ok, 1}
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

    describe "incr!/3" do
      test "increments a counter by the given amount", %{cache: cache} do
        assert cache.incr!(:counter) == 1
        assert cache.incr!(:counter) == 2
        assert cache.incr!(:counter, 2) == 4
        assert cache.incr!(:counter, 3) == 7
        assert cache.incr!(:counter, 0) == 7

        assert :counter |> cache.fetch!() |> to_int() == 7

        assert cache.incr!(:counter, -1) == 6
        assert cache.incr!(:counter, -1) == 5
        assert cache.incr!(:counter, -2) == 3
        assert cache.incr!(:counter, -3) == 0
      end

      test_with_mock "raises an error", %{cache: cache}, cache.__adapter__(), [:passthrough],
        update_counter: fn _, _, _, _, _, _ -> {:error, %Nebulex.Error{reason: :error}} end do
        assert_raise Nebulex.Error, ~r"Nebulex error:\n\n:error", fn ->
          cache.incr!(:raise)
        end
      end
    end

    describe "decr/3" do
      test "decrements a counter by the given amount", %{cache: cache} do
        assert cache.decr(:counter) == {:ok, -1}
        assert cache.decr(:counter) == {:ok, -2}
        assert cache.decr(:counter, 2) == {:ok, -4}
        assert cache.decr(:counter, 3) == {:ok, -7}
        assert cache.decr(:counter, 0) == {:ok, -7}

        assert :counter |> cache.fetch!() |> to_int() == -7

        assert cache.decr(:counter, -1) == {:ok, -6}
        assert cache.decr(:counter, -1) == {:ok, -5}
        assert cache.decr(:counter, -2) == {:ok, -3}
        assert cache.decr(:counter, -3) == {:ok, 0}
      end

      test "decrements a counter by the given amount with default", %{cache: cache} do
        assert cache.decr(:counter1, 1, default: 10) == {:ok, 9}
        assert cache.decr(:counter2, 2, default: 10) == {:ok, 8}
        assert cache.decr(:counter3, -2, default: 10) == {:ok, 12}
      end

      test "decrements a counter by the given amount ignoring the default", %{cache: cache} do
        assert cache.decr(:counter) == {:ok, -1}
        assert cache.decr(:counter, 1, default: 10) == {:ok, -2}
        assert cache.decr(:counter, -1, default: 100) == {:ok, -1}
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

    describe "decr!/3" do
      test "decrements a counter by the given amount", %{cache: cache} do
        assert cache.decr!(:counter) == -1
        assert cache.decr!(:counter) == -2
        assert cache.decr!(:counter, 2) == -4
        assert cache.decr!(:counter, 3) == -7
        assert cache.decr!(:counter, 0) == -7

        assert :counter |> cache.fetch!() |> to_int() == -7

        assert cache.decr!(:counter, -1) == -6
        assert cache.decr!(:counter, -1) == -5
        assert cache.decr!(:counter, -2) == -3
        assert cache.decr!(:counter, -3) == 0
      end

      test_with_mock "raises an error", %{cache: cache}, cache.__adapter__(), [:passthrough],
        update_counter: fn _, _, _, _, _, _ -> {:error, %Nebulex.Error{reason: :error}} end do
        assert_raise Nebulex.Error, ~r"Nebulex error:\n\n:error", fn ->
          cache.decr!(:raise)
        end
      end
    end

    ## Helpers

    defp to_int(data) when is_integer(data), do: data
    defp to_int(data) when is_binary(data), do: String.to_integer(data)
  end
end
