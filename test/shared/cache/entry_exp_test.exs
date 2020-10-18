defmodule Nebulex.Cache.EntryExpTest do
  import Nebulex.CacheCase

  deftests "cache expiration" do
    alias Nebulex.TestCache.Partitioned

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

    test "has_key?", %{cache: cache} do
      assert cache.put("foo", "bar", ttl: 500) == :ok
      assert cache.has_key?("foo")

      Process.sleep(600)
      refute cache.has_key?("foo")
    end

    test "ttl", %{cache: cache} do
      assert cache.put(:a, 1, ttl: 500) == :ok
      assert cache.ttl(:a) > 0
      assert cache.put(:b, 2) == :ok

      :ok = Process.sleep(10)
      assert cache.ttl(:a) > 0
      assert cache.ttl(:b) == :infinity
      refute cache.ttl(:c)

      :ok = Process.sleep(600)
      refute cache.ttl(:a)
    end

    test "expire", %{cache: cache} do
      assert cache.put(:a, 1, ttl: 500) == :ok
      assert cache.ttl(:a) > 0

      assert cache.expire(:a, 1000)
      assert cache.ttl(:a) > 100

      assert cache.expire(:a, :infinity)
      assert cache.ttl(:a) == :infinity

      refute cache.expire(:b, 5)

      assert_raise ArgumentError, ~r"expected ttl to be a valid timeout", fn ->
        cache.expire(:a, "hello")
      end
    end

    test "touch", %{cache: cache} do
      assert cache.put(:touch, 1, ttl: 1000) == :ok

      :ok = Process.sleep(100)
      assert cache.touch(:touch)

      :ok = Process.sleep(200)
      assert cache.touch(:touch)
      assert cache.get(:touch) == 1

      :ok = Process.sleep(1100)
      refute cache.get(:touch)

      refute cache.touch(:non_existent)
    end

    test "key expiration with ttl", %{cache: cache} do
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

    test "entry ttl", %{cache: cache} do
      assert cache.put(1, 11, ttl: 1000) == :ok
      assert cache.get!(1) == 11

      for _ <- 3..1 do
        assert cache.ttl(1) > 0
        Process.sleep(200)
      end

      :ok = Process.sleep(500)
      refute cache.ttl(1)
      assert cache.put(1, 11, ttl: 1000) == :ok
      assert cache.ttl(1) > 0
    end

    test "get_and_update existing entry with ttl", %{cache: cache} do
      assert cache.put(1, 1, ttl: 1000) == :ok
      assert cache.ttl(1) > 0

      :ok = Process.sleep(10)

      assert cache.get_and_update(1, &Partitioned.get_and_update_fun/1) == {1, 2}
      assert cache.ttl(1) == :infinity

      :ok = Process.sleep(1200)
      assert cache.get(1) == 2
    end

    test "update existing entry with ttl", %{cache: cache} do
      assert cache.put(1, 1, ttl: 1000) == :ok
      assert cache.ttl(1) > 0

      :ok = Process.sleep(10)

      assert cache.update(1, 10, &Integer.to_string/1) == "1"
      assert cache.ttl(1) == :infinity

      :ok = Process.sleep(1200)
      assert cache.get(1) == "1"
    end

    test "incr with ttl", %{cache: cache} do
      assert cache.incr(:counter, 1, ttl: 1000) == 1
      assert cache.ttl(1) > 0

      :ok = Process.sleep(1200)
      refute cache.get(:counter)
    end

    test "incr and then set ttl", %{cache: cache} do
      assert cache.incr(:counter, 1) == 1
      assert cache.ttl(:counter) == :infinity

      assert cache.expire(:counter, 500)
      :ok = Process.sleep(600)
      refute cache.get(:counter)
    end
  end
end
