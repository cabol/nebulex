defmodule Nebulex.Adapters.CacheTest do
  use ExUnit.Case, async: true

  # Cache API test cases
  use Nebulex.CacheTestCase

  import Nebulex.CacheCase, only: [setup_with_dynamic_cache: 2, t_sleep: 1]

  setup_with_dynamic_cache Nebulex.TestCache.Cache, __MODULE__

  describe "KV:" do
    test "get_and_update", %{cache: cache} do
      fun = fn
        nil -> {nil, 1}
        val -> {val, val * 2}
      end

      assert cache.get_and_update!(1, fun) == {nil, 1}
      assert cache.get_and_update!(1, &{&1, &1 * 2}) == {1, 2}
      assert cache.get_and_update!(1, &{&1, &1 * 3}) == {2, 6}
      assert cache.get_and_update!(1, &{&1, nil}) == {6, 6}
      assert cache.get!(1) == 6
      assert cache.get_and_update!(1, fn _ -> :pop end) == {6, nil}
      assert cache.get_and_update!(1, fn _ -> :pop end) == {nil, nil}
      assert cache.get_and_update!(3, &{&1, 3}) == {nil, 3}
    end

    test "get_and_update fails because function returns invalid value", %{cache: cache} do
      assert_raise ArgumentError, fn ->
        cache.get_and_update(1, fn _ -> :other end)
      end
    end

    test "get_and_update fails because cache is not started", %{cache: cache} do
      :ok = cache.stop()

      assert_raise Nebulex.Error, fn ->
        assert cache.get_and_update!(1, fn _ -> :pop end)
      end
    end

    test "incr and update", %{cache: cache} do
      assert cache.incr!(:counter) == 1
      assert cache.incr!(:counter) == 2

      assert cache.get_and_update!(:counter, &{&1, &1 * 2}) == {2, 4}
      assert cache.incr!(:counter) == 5

      assert cache.update!(:counter, 1, &(&1 * 2)) == 10
      assert cache.incr!(:counter, -10) == 0

      assert cache.put("foo", "bar") == :ok

      assert_raise Nebulex.Error, fn ->
        cache.incr!("foo")
      end
    end

    test "incr with ttl", %{cache: cache} do
      assert cache.incr!(:counter_with_ttl, 1, ttl: 1000) == 1
      assert cache.incr!(:counter_with_ttl) == 2
      assert cache.fetch!(:counter_with_ttl) == 2

      _ = t_sleep(1010)

      assert {:error, %Nebulex.KeyError{key: :counter_with_ttl}} = cache.fetch(:counter_with_ttl)

      assert cache.incr!(:counter_with_ttl, 1, ttl: 5000) == 1
      assert {:ok, ttl} = cache.ttl(:counter_with_ttl)
      assert ttl > 1000

      assert cache.expire(:counter_with_ttl, 500) == {:ok, true}

      _ = t_sleep(600)

      assert {:error, %Nebulex.KeyError{key: :counter_with_ttl}} = cache.fetch(:counter_with_ttl)
    end

    test "incr existing entry", %{cache: cache} do
      assert cache.put(:counter, 0) == :ok
      assert cache.incr!(:counter) == 1
      assert cache.incr!(:counter, 2) == 3
    end
  end

  describe "queryable:" do
    test "raises an exception because of an invalid query", %{cache: cache} do
      for action <- [:get_all, :stream] do
        assert_raise Nebulex.QueryError, fn ->
          apply(cache, action, [[query: :invalid]])
        end
      end
    end
  end

  describe "error" do
    test "because cache is stopped", %{cache: cache, name: name} do
      :ok = cache.stop()

      assert cache.put(1, 13) ==
               {:error,
                %Nebulex.Error{
                  module: Nebulex.Error,
                  reason: :registry_lookup_error,
                  opts: [cache: name]
                }}

      msg = ~r"could not lookup Nebulex cache"

      assert_raise Nebulex.Error, msg, fn -> cache.put!(1, 13) end
      assert_raise Nebulex.Error, msg, fn -> cache.get!(1) end
      assert_raise Nebulex.Error, msg, fn -> cache.delete!(1) end
    end
  end
end
