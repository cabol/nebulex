defmodule Nebulex.Cache.EntryExpirationTest do
  import Nebulex.CacheCase

  deftests do
    describe "ttl option is given to" do
      test "put", %{cache: cache} do
        assert cache.put("foo", "bar", ttl: 500) == :ok
        assert cache.has_key?("foo")

        Process.sleep(600)
        refute cache.has_key?("foo")
      end

      test "put_all", %{cache: cache} do
        entries = [{0, nil} | for(x <- 1..3, do: {x, x})]
        assert cache.put_all(entries, ttl: 1000)

        refute cache.get(0)
        for x <- 1..3, do: assert(x == cache.get(x))
        :ok = Process.sleep(1200)
        for x <- 1..3, do: refute(cache.get(x))
      end

      test "put_new_all", %{cache: cache} do
        assert cache.put_new_all(%{"apples" => 1, "bananas" => 3}, ttl: 1000)
        assert cache.get("apples") == 1
        assert cache.get("bananas") == 3

        refute cache.put_new_all(%{"apples" => 3, "oranges" => 1})
        assert cache.get("apples") == 1
        assert cache.get("bananas") == 3
        refute cache.get("oranges")

        :ok = Process.sleep(1200)
        refute cache.get("apples")
        refute cache.get("bananas")
      end

      test "take", %{cache: cache} do
        :ok = cache.put("foo", "bar", ttl: 500)
        :ok = Process.sleep(600)

        refute cache.take(1)
      end

      test "take!", %{cache: cache} do
        :ok = cache.put(1, 1, ttl: 100)
        :ok = Process.sleep(500)

        assert_raise KeyError, fn ->
          cache.take!(1)
        end
      end

      test "incr (initializes default value if ttl is expired)", %{cache: cache} do
        assert cache.incr(:counter, 1, ttl: 200) == 1
        assert cache.incr(:counter) == 2

        :ok = Process.sleep(210)

        assert cache.incr(:counter, 1, ttl: 200) == 1
        assert cache.incr(:counter) == 2
      end
    end

    describe "ttl" do
      test "returns the remaining ttl for the given key", %{cache: cache} do
        assert cache.put(:a, 1, ttl: 500) == :ok
        assert cache.ttl(:a) > 0
        assert cache.put(:b, 2) == :ok

        :ok = Process.sleep(10)
        assert cache.ttl(:a) > 0
        assert cache.ttl(:b) == :infinity

        :ok = Process.sleep(600)
        refute cache.ttl(:a)
        assert cache.ttl(:b) == :infinity
      end

      test "returns nil if key does not exist", %{cache: cache} do
        refute cache.ttl(:non_existent)
      end
    end

    describe "expire" do
      test "alters the expiration time for the given key", %{cache: cache} do
        assert cache.put(:a, 1, ttl: 500) == :ok
        assert cache.ttl(:a) > 0

        assert cache.expire(:a, 1000)
        assert cache.ttl(:a) > 100

        assert cache.expire(:a, :infinity)
        assert cache.ttl(:a) == :infinity

        refute cache.expire(:b, 5)
      end

      test "returns false if key does not exist", %{cache: cache} do
        assert cache.expire(:non_existent, 1000) == false
      end

      test "raises when ttl is invalid", %{cache: cache} do
        assert_raise ArgumentError, ~r"expected ttl to be a valid timeout", fn ->
          cache.expire(:a, "hello")
        end
      end
    end

    describe "touch" do
      test "updates the last access time for the given entry", %{cache: cache} do
        assert cache.put(:touch, 1, ttl: 1000) == :ok

        :ok = Process.sleep(100)
        assert cache.touch(:touch)

        :ok = Process.sleep(200)
        assert cache.touch(:touch)
        assert cache.get(:touch) == 1

        :ok = Process.sleep(1100)
        refute cache.get(:touch)
      end

      test "returns false if key does not exist", %{cache: cache} do
        assert cache.touch(:non_existent) == false
      end
    end

    describe "expiration" do
      test "single entry put with  ttl", %{cache: cache} do
        assert cache.put(1, 11, ttl: 1000) == :ok
        assert cache.get!(1) == 11

        for _ <- 1..3 do
          assert cache.ttl(1) > 0
          Process.sleep(200)
        end

        :ok = Process.sleep(500)
        refute cache.ttl(1)
        assert cache.put(1, 11, ttl: 1000) == :ok
        assert cache.ttl(1) > 0
      end

      test "multiple entries put with ttl", %{cache: cache} do
        assert cache.put(1, 11, ttl: 1000) == :ok
        assert cache.get!(1) == 11

        :ok = Process.sleep(10)
        assert cache.get(1) == 11
        :ok = Process.sleep(1100)
        refute cache.get(1)

        ops = [
          put: ["foo", "bar", [ttl: 1000]],
          put_all: [[{"foo", "bar"}], [ttl: 1000]]
        ]

        for {action, args} <- ops do
          assert apply(cache, action, args) == :ok
          :ok = Process.sleep(10)
          assert cache.get("foo") == "bar"
          :ok = Process.sleep(1200)
          refute cache.get("foo")

          assert apply(cache, action, args) == :ok
          :ok = Process.sleep(10)
          assert cache.get("foo") == "bar"
          :ok = Process.sleep(1200)
          refute cache.get("foo")
        end
      end
    end

    describe "get_and_update with ttl" do
      test "existing entry", %{cache: cache} do
        assert cache.put(1, 1, ttl: 1000) == :ok
        assert cache.ttl(1) > 0

        :ok = Process.sleep(10)

        assert cache.get_and_update(1, &cache.get_and_update_fun/1) == {1, 2}
        assert cache.ttl(1) == :infinity

        :ok = Process.sleep(1200)
        assert cache.get(1) == 2
      end
    end

    describe "update with ttl" do
      test "existing entry", %{cache: cache} do
        assert cache.put(1, 1, ttl: 1000) == :ok
        assert cache.ttl(1) > 0

        :ok = Process.sleep(10)

        assert cache.update(1, 10, &Integer.to_string/1) == "1"
        assert cache.ttl(1) == :infinity

        :ok = Process.sleep(1200)
        assert cache.get(1) == "1"
      end
    end

    describe "incr with ttl" do
      test "increments a counter", %{cache: cache} do
        assert cache.incr(:counter, 1, ttl: 1000) == 1
        assert cache.ttl(1) > 0

        :ok = Process.sleep(1200)
        refute cache.get(:counter)
      end

      test "increments a counter and then set ttl", %{cache: cache} do
        assert cache.incr(:counter, 1) == 1
        assert cache.ttl(:counter) == :infinity

        assert cache.expire(:counter, 500)
        :ok = Process.sleep(600)
        refute cache.get(:counter)
      end
    end
  end
end
