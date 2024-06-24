defmodule Nebulex.Cache.KVExpirationTest do
  import Nebulex.CacheCase

  deftests do
    import Nebulex.CacheCase, only: [t_sleep: 1]

    describe "ttl option is given to" do
      test "put", %{cache: cache} do
        assert cache.put!("foo", "bar", ttl: 500) == :ok
        assert cache.has_key?("foo") == {:ok, true}

        _ = t_sleep(600)

        assert cache.has_key?("foo") == {:ok, false}
      end

      test "put_all", %{cache: cache} do
        entries = [{0, nil} | for(x <- 1..3, do: {x, x})]

        assert cache.put_all!(entries, ttl: 1000) == :ok

        refute cache.get!(0)

        for x <- 1..3, do: assert(cache.fetch!(x) == x)

        _ = t_sleep(1200)

        for x <- 1..3, do: refute(cache.get!(x))
      end

      test "put_new_all", %{cache: cache} do
        assert cache.put_new_all!(%{"apples" => 1, "bananas" => 3}, ttl: 1000) == true
        assert cache.fetch!("apples") == 1
        assert cache.fetch!("bananas") == 3

        assert cache.put_new_all!(%{"apples" => 3, "oranges" => 1}) == false
        assert cache.fetch!("apples") == 1
        assert cache.fetch!("bananas") == 3
        refute cache.get!("oranges")

        _ = t_sleep(1200)

        refute cache.get!("apples")
        refute cache.get!("bananas")
      end

      test "take", %{cache: cache} do
        :ok = cache.put!("foo", "bar", ttl: 500)

        _ = t_sleep(600)

        assert {:error, %Nebulex.KeyError{key: "foo"}} = cache.take("foo")
      end

      test "take!", %{cache: cache} do
        :ok = cache.put!(1, 1, ttl: 100)

        _ = t_sleep(500)

        assert_raise Nebulex.KeyError, ~r"key 1", fn ->
          cache.take!(1)
        end
      end

      test "incr! (initializes default value if ttl is expired)", %{cache: cache} do
        assert cache.incr!(:counter, 1, ttl: 200) == 1
        assert cache.incr!(:counter) == 2

        _ = t_sleep(210)

        assert cache.incr!(:counter, 1, ttl: 200) == 1
        assert cache.incr!(:counter) == 2
      end
    end

    describe "ttl!/1" do
      test "returns the remaining ttl for the given key", %{cache: cache} do
        assert cache.put!(:a, 1, ttl: 500) == :ok
        assert cache.ttl!(:a) > 0
        assert cache.put!(:b, 2) == :ok

        t = t_sleep(10)

        assert cache.ttl!(:a) > 0
        assert cache.ttl!(:b) == :infinity

        _ = t_sleep(t + 600)

        assert {:error, %Nebulex.KeyError{key: :a}} = cache.ttl(:a)
        assert cache.ttl!(:b) == :infinity
      end

      test "raises Nebulex.KeyError if key does not exist", %{cache: cache} do
        msg = ~r|key :non_existent not found|

        assert_raise Nebulex.KeyError, msg, fn ->
          cache.ttl!(:non_existent)
        end
      end
    end

    describe "expire!/2" do
      test "alters the expiration time for the given key", %{cache: cache} do
        assert cache.put!(:a, 1, ttl: 500) == :ok
        assert cache.ttl!(:a) > 0

        assert cache.expire!(:a, 1000) == true
        assert cache.ttl!(:a) > 100

        assert cache.expire!(:a, :infinity) == true
        assert cache.ttl!(:a) == :infinity
      end

      test "returns false if key does not exist", %{cache: cache} do
        assert cache.expire!(:non_existent, 100) == false
      end

      test "raises when ttl is invalid", %{cache: cache} do
        assert_raise ArgumentError, ~r"expected ttl to be a valid timeout", fn ->
          cache.expire!(:a, "hello")
        end
      end
    end

    describe "touch!/1" do
      test "updates the last access time for the given entry", %{cache: cache} do
        assert cache.put!(:touch, 1, ttl: 1000) == :ok

        t = t_sleep(100)

        assert cache.touch!(:touch) == true

        t = t_sleep(t + 200)

        assert cache.touch!(:touch) == true
        assert cache.fetch!(:touch) == 1

        _ = t_sleep(t + 1100)

        refute cache.get!(:touch)
      end

      test "returns false if key does not exist", %{cache: cache} do
        assert cache.touch!(:non_existent) == false
      end
    end

    describe "expiration" do
      test "single entry put with  ttl", %{cache: cache} do
        assert cache.put!(1, 11, ttl: 1000) == :ok
        assert cache.fetch!(1) == 11

        t =
          Enum.reduce(1..3, 0, fn _, acc ->
            assert cache.ttl!(1) > 0

            t_sleep(acc + 200)
          end)

        _ = t_sleep(t + 500)

        assert {:error, %Nebulex.KeyError{key: 1}} = cache.ttl(1)
        assert cache.put!(1, 11, ttl: 1000) == :ok
        assert cache.ttl!(1) > 0
      end

      test "multiple entries put with ttl", %{cache: cache} do
        assert cache.put!(1, 11, ttl: 1000) == :ok
        assert cache.fetch!(1) == 11

        t = t_sleep(10)

        assert cache.fetch!(1) == 11

        t = t_sleep(t + 1100)

        refute cache.get!(1)

        ops = [
          put!: ["foo", "bar", [ttl: 1000]],
          put_all!: [[{"foo", "bar"}], [ttl: 1000]]
        ]

        Enum.reduce(ops, t, fn {action, args}, acc ->
          assert apply(cache, action, args) == :ok

          t = t_sleep(acc + 10)

          assert cache.fetch!("foo") == "bar"

          t = t_sleep(t + 1200)

          refute cache.get!("foo")

          t
        end)
      end
    end

    describe "get_and_update with ttl" do
      test "existing entry", %{cache: cache} do
        assert cache.put!(1, 1, ttl: 1000) == :ok
        assert cache.ttl!(1) > 0

        t = t_sleep(10)

        assert cache.get_and_update!(1, &cache.get_and_update_fun/1) == {1, 2}
        assert cache.ttl!(1) == :infinity

        _ = t_sleep(t + 1200)

        assert cache.fetch!(1) == 2
      end
    end

    describe "update with ttl" do
      test "existing entry", %{cache: cache} do
        assert cache.put!(1, 1, ttl: 1000) == :ok
        assert cache.ttl!(1) > 0

        t = t_sleep(10)

        assert cache.update!(1, 10, &Integer.to_string/1) == "1"
        assert cache.ttl!(1) == :infinity

        _ = t_sleep(t + 1200)

        assert cache.fetch!(1) == "1"
      end
    end

    describe "incr with ttl" do
      test "increments a counter", %{cache: cache} do
        assert cache.incr!(:counter, 1, ttl: 1000) == 1
        assert cache.ttl!(:counter) > 0

        _ = t_sleep(1200)

        refute cache.get!(:counter)
      end

      test "increments a counter and then set ttl", %{cache: cache} do
        assert cache.incr!(:counter, 1) == 1
        assert cache.ttl!(:counter) == :infinity

        assert cache.expire!(:counter, 500) == true

        _ = t_sleep(600)

        refute cache.get!(:counter)
      end
    end
  end
end
