defmodule Nebulex.Cache.KVTest do
  import Nebulex.CacheCase

  deftests do
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
        assert cache.put("nil", nil) == :ok
        assert cache.fetch("nil") == {:ok, nil}
      end

      test "puts a boolean value", %{cache: cache} do
        assert cache.put(:boolean, true) == :ok
        assert cache.fetch(:boolean) == {:ok, true}

        assert cache.put(:boolean, false) == :ok
        assert cache.fetch(:boolean) == {:ok, false}
      end

      test "raises when invalid option is given", %{cache: cache} do
        assert_raise NimbleOptions.ValidationError, ~r"invalid value for :ttl option", fn ->
          cache.put("hello", "world", ttl: "1")
        end
      end

      test "with dynamic_cache", %{cache: cache} = ctx do
        if name = Map.get(ctx, :name) do
          assert cache.put(name, "foo", "bar", []) == :ok
          assert cache.fetch!(name, "foo", []) == "bar"
          assert cache.delete(name, "foo", []) == :ok
        end
      end

      test "with dynamic_cache raises an exception", %{cache: cache} do
        assert_raise Nebulex.CacheNotFoundError, ~r"unable to find cache:", fn ->
          cache.put!(:invalid, "foo", "bar", [])
        end
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
    end

    describe "put_new/3" do
      test "puts the given entry into the cache if the key does not exist", %{cache: cache} do
        assert cache.put_new("new foo", "new bar") == {:ok, true}
        assert cache.fetch!("new foo") == "new bar"
      end

      test "do nothing if the key does exist already", %{cache: cache} do
        :ok = cache.put("existing foo", "existing bar")

        assert cache.put_new("existing foo", "bar bar") == {:ok, false}
        assert cache.fetch!("existing foo") == "existing bar"
      end

      test "puts a new nil value", %{cache: cache} do
        assert cache.put_new(:mykey, nil) == {:ok, true}
        assert cache.fetch(:mykey) == {:ok, nil}
      end

      test "puts a boolean value", %{cache: cache} do
        assert cache.put_new(true, true) == {:ok, true}
        assert cache.fetch(true) == {:ok, true}

        assert cache.put_new(false, false) == {:ok, true}
        assert cache.fetch(false) == {:ok, false}
      end

      test "raises when invalid option is given", %{cache: cache} do
        assert_raise NimbleOptions.ValidationError, ~r"invalid value for :ttl option", fn ->
          cache.put_new("hello", "world", ttl: "1")
        end
      end
    end

    describe "put_new!/3" do
      test "puts the given entry into the cache if the key does not exist", %{cache: cache} do
        assert cache.put_new!("hello", "world") == true
        assert cache.fetch!("hello") == "world"
      end

      test "returns false if the key does exist already", %{cache: cache} do
        assert cache.put_new!("hello!", "world!") == true
        assert cache.put_new!("hello!", "world!!") == false
      end
    end

    describe "replace/3" do
      test "replaces the cached entry with a new value", %{cache: cache} do
        assert cache.replace("replace", "this") == {:ok, false}

        assert cache.put("replace", "this") == :ok
        assert cache.fetch!("replace") == "this"

        assert cache.replace("replace", "this again") == {:ok, true}
        assert cache.fetch!("replace") == "this again"
      end

      test "existing value with nil", %{cache: cache} do
        :ok = cache.put("replace existing", "entry")

        assert cache.replace("replace existing", nil) == {:ok, true}
        assert cache.fetch("replace existing") == {:ok, nil}
      end

      test "existing boolean value", %{cache: cache} do
        :ok = cache.put(:boolean, true)

        assert cache.replace(:boolean, false) == {:ok, true}
        assert cache.fetch(:boolean) == {:ok, false}

        assert cache.replace(:boolean, true) == {:ok, true}
        assert cache.fetch(:boolean) == {:ok, true}
      end

      test "raises when invalid option is given", %{cache: cache} do
        assert_raise NimbleOptions.ValidationError, ~r"invalid value for :ttl option", fn ->
          cache.replace("hello", "world", ttl: "1")
        end
      end
    end

    describe "replace!/3" do
      test "replaces the cached entry with a new value", %{cache: cache} do
        assert cache.put("replace!", "this") == :ok
        assert cache.replace!("replace!", "this again") == true
        assert cache.fetch!("replace!") == "this again"
      end

      test "returns false when the key is not found", %{cache: cache} do
        assert cache.replace!("another replace!", "this") == false
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
              [elem] => elem,
              true => true,
              false => false
            }

            Map.merge(acc, sample)
          end)

        assert cache.put_all(entries) == :ok

        for {k, v} <- entries, do: assert(cache.fetch!(k) == v)
      end

      test "raises when invalid option is given", %{cache: cache} do
        assert_raise NimbleOptions.ValidationError, ~r"invalid value for :ttl option", fn ->
          cache.put_all(%{"apples" => 1, "bananas" => 3}, ttl: "1")
        end
      end
    end

    describe "put_all!/2" do
      test "puts the given entries at once", %{cache: cache} do
        assert cache.put_all!(%{"apples!" => 1, "bananas!" => 3}) == :ok
        assert cache.put_all!(blueberries!: 2, strawberries!: 5) == :ok
        assert cache.fetch!("apples!") == 1
        assert cache.fetch!("bananas!") == 3
        assert cache.fetch!(:blueberries!) == 2
        assert cache.fetch!(:strawberries!) == 5
      end
    end

    describe "put_new_all/2" do
      test "puts the given entries only if none of the keys does exist already", %{cache: cache} do
        assert cache.put_new_all(%{"new_apples" => 1, "new_bananas" => 3}) == {:ok, true}
        assert cache.fetch!("new_apples") == 1
        assert cache.fetch!("new_bananas") == 3

        assert cache.put_new_all(%{"new_apples" => 3, "new_oranges" => 1}) == {:ok, false}
        assert cache.fetch!("new_apples") == 1
        assert cache.fetch!("new_bananas") == 3
        refute cache.get!("new_oranges")
      end

      test "puts a boolean values", %{cache: cache} do
        assert cache.put_new_all(%{true => true, false => false}) == {:ok, true}
        assert cache.fetch!(true) == true
        assert cache.fetch!(false) == false
      end

      test "raises when invalid option is given", %{cache: cache} do
        assert_raise NimbleOptions.ValidationError, ~r"invalid value for :ttl option", fn ->
          cache.put_new_all(%{"apples" => 1, "bananas" => 3}, ttl: "1")
        end
      end
    end

    describe "put_new_all!/2" do
      test "puts the given entries only if none of the keys does exist already", %{cache: cache} do
        assert cache.put_new_all!(%{"new_apples!" => 1, "new_bananas!" => 3}) == true
        assert cache.fetch!("new_apples!") == 1
        assert cache.fetch!("new_bananas!") == 3
      end

      test "raises an error if any of the keys does exist already", %{cache: cache} do
        assert cache.put_new_all!(%{"dogs" => 1, "cats" => 3}) == true
        assert cache.put_new_all!(%{"dogs" => 3, "birds" => 1}) == false
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
    end

    describe "fetch!/2" do
      test "retrieves a cached entry", %{cache: cache} do
        for x <- 1..5 do
          :ok = cache.put(x, x)

          assert cache.fetch!(x) == x
        end
      end

      test "raises when the key does not exist in cache", %{cache: cache} do
        msg = ~r/key "non-existent" not found/

        assert_raise Nebulex.KeyError, msg, fn ->
          cache.fetch!("non-existent")
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

      test "deletes boolean and nil values", %{cache: cache} do
        :ok = cache.put_all(true: true, false: false, nil: nil)

        assert cache.fetch!(true) == true
        assert cache.fetch!(false) == false
        assert cache.fetch!(nil) == nil

        assert cache.delete(true) == :ok
        assert cache.delete(false) == :ok
        assert cache.delete(nil) == :ok

        refute cache.get!(true)
        refute cache.get!(false)
        refute cache.get!(nil)
      end
    end

    describe "delete!/2" do
      test "deletes the given key", %{cache: cache} do
        assert cache.put("foo", "bar") == :ok

        assert cache.fetch!("foo") == "bar"
        assert cache.delete!("foo") == :ok
        refute cache.get!("foo")
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

      test "returns boolean and nil values", %{cache: cache} do
        :ok = cache.put_all(true: true, false: false, nil: nil)

        assert cache.take(true) == {:ok, true}
        assert cache.take(false) == {:ok, false}
        assert cache.take(nil) == {:ok, nil}

        refute cache.get!(true)
        refute cache.get!(false)
        refute cache.get!(nil)
      end

      test "returns nil if the key does not exist in cache", %{cache: cache} do
        assert {:error, %Nebulex.KeyError{key: :non_existent}} = cache.take(:non_existent)
        assert {:error, %Nebulex.KeyError{key: nil}} = cache.take(nil)
      end
    end

    describe "take!/2" do
      test "returns the given key and removes it from cache", %{cache: cache} do
        assert cache.put(1, 1) == :ok
        assert cache.take!(1) == 1
        assert cache.get!(1) == nil
      end

      test "raises when the key does not exist in cache", %{cache: cache} do
        msg = ~r/key "non-existent" not found/

        assert_raise Nebulex.KeyError, msg, fn ->
          cache.take!("non-existent")
        end
      end
    end

    describe "has_key?/1" do
      test "returns true if key does exist in cache", %{cache: cache} do
        for x <- 1..5 do
          :ok = cache.put(x, x)

          assert cache.has_key?(x) == {:ok, true}
        end
      end

      test "returns boolean and nil values", %{cache: cache} do
        :ok = cache.put_all(true: true, false: false, nil: nil)

        assert cache.has_key?(true) == {:ok, true}
        assert cache.has_key?(false) == {:ok, true}
        assert cache.has_key?(nil) == {:ok, true}
      end

      test "returns false if key does not exist in cache", %{cache: cache} do
        assert cache.has_key?(:non_existent) == {:ok, false}
        assert cache.has_key?(nil) == {:ok, false}
      end
    end

    describe "update!/4" do
      test "updates an entry under a key applying a function on the value", %{cache: cache} do
        :ok = cache.put("update_int", "123")
        :ok = cache.put("update_str", "foo")

        assert cache.update!("update_int", 1, &String.to_integer/1) == 123
        assert cache.update!("update_str", "str", &String.to_atom/1) == :foo
      end

      test "creates the entry with the default value if key does not exist", %{cache: cache} do
        assert cache.update!("k123", "123", &Integer.to_string/1) == "123"
      end

      test "updates existing value with nil", %{cache: cache} do
        assert cache.update!("update with nil", nil, &Integer.to_string/1) == nil
        assert cache.fetch!("update with nil") == nil
      end

      test "raises because the cache is not started", %{cache: cache} do
        :ok = cache.stop()

        assert_raise Nebulex.CacheNotFoundError, ~r"unable to find cache:", fn ->
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
        assert cache.incr(:counter4) == {:ok, 1}
        assert cache.incr(:counter4, 1, default: 10) == {:ok, 2}
        assert cache.incr(:counter4, -1, default: 100) == {:ok, 1}
      end

      test "raises when amount is invalid", %{cache: cache} do
        assert_raise ArgumentError, ~r"invalid value for amount argument", fn ->
          cache.incr(:counter, "counter")
        end
      end

      test "raises when default is invalid", %{cache: cache} do
        assert_raise NimbleOptions.ValidationError,
                     ~r"invalid value for :default option: expected integer",
                     fn ->
                       cache.incr(:counter, 1, default: :invalid)
                     end
      end
    end

    describe "incr!/3" do
      test "increments a counter by the given amount", %{cache: cache} do
        assert cache.incr!(:counter!) == 1
        assert cache.incr!(:counter!) == 2
        assert cache.incr!(:counter!, 2) == 4
        assert cache.incr!(:counter!, 3) == 7
        assert cache.incr!(:counter!, 0) == 7

        assert :counter! |> cache.fetch!() |> to_int() == 7

        assert cache.incr!(:counter!, -1) == 6
        assert cache.incr!(:counter!, -1) == 5
        assert cache.incr!(:counter!, -2) == 3
        assert cache.incr!(:counter!, -3) == 0
      end
    end

    describe "decr/3" do
      test "decrements a counter by the given amount", %{cache: cache} do
        assert cache.decr(:decr) == {:ok, -1}
        assert cache.decr(:decr) == {:ok, -2}
        assert cache.decr(:decr, 2) == {:ok, -4}
        assert cache.decr(:decr, 3) == {:ok, -7}
        assert cache.decr(:decr, 0) == {:ok, -7}

        assert :decr |> cache.fetch!() |> to_int() == -7

        assert cache.decr(:decr, -1) == {:ok, -6}
        assert cache.decr(:decr, -1) == {:ok, -5}
        assert cache.decr(:decr, -2) == {:ok, -3}
        assert cache.decr(:decr, -3) == {:ok, 0}
      end

      test "decrements a counter by the given amount with default", %{cache: cache} do
        assert cache.decr(:decr1, 1, default: 10) == {:ok, 9}
        assert cache.decr(:decr2, 2, default: 10) == {:ok, 8}
        assert cache.decr(:decr3, -2, default: 10) == {:ok, 12}
      end

      test "decrements a counter by the given amount ignoring the default", %{cache: cache} do
        assert cache.decr(:decr4) == {:ok, -1}
        assert cache.decr(:decr4, 1, default: 10) == {:ok, -2}
        assert cache.decr(:decr4, -1, default: 100) == {:ok, -1}
      end

      test "raises when amount is invalid", %{cache: cache} do
        assert_raise ArgumentError, ~r"invalid value for amount argument", fn ->
          cache.decr(:decr, "decr")
        end
      end

      test "raises when default is invalid", %{cache: cache} do
        assert_raise NimbleOptions.ValidationError,
                     ~r"invalid value for :default option: expected integer",
                     fn -> cache.decr(:decr, 1, default: :invalid) end
      end
    end

    describe "decr!/3" do
      test "decrements a counter by the given amount", %{cache: cache} do
        assert cache.decr!(:decr!) == -1
        assert cache.decr!(:decr!) == -2
        assert cache.decr!(:decr!, 2) == -4
        assert cache.decr!(:decr!, 3) == -7
        assert cache.decr!(:decr!, 0) == -7

        assert :decr! |> cache.fetch!() |> to_int() == -7

        assert cache.decr!(:decr!, -1) == -6
        assert cache.decr!(:decr!, -1) == -5
        assert cache.decr!(:decr!, -2) == -3
        assert cache.decr!(:decr!, -3) == 0
      end
    end

    ## Helpers

    defp to_int(data) when is_integer(data), do: data
    defp to_int(data) when is_binary(data), do: String.to_integer(data)
  end
end
