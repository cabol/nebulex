defmodule Nebulex.Adapters.LocalDuplicateKeysTest do
  use ExUnit.Case, async: true

  import Ex2ms

  alias Nebulex.TestCache.Local.{ETS, Shards}

  @caches [ETS, Shards]

  setup do
    cache_pids =
      for cache <- @caches do
        {:ok, pid} = cache.start_link(n_generations: 2, backend_type: :duplicate_bag)
        {cache, pid}
      end

    :ok

    on_exit(fn ->
      :ok = Process.sleep(10)

      for {cache, pid} <- cache_pids do
        if Process.alive?(pid), do: cache.stop(pid)
      end
    end)
  end

  describe "duplicate keys" do
    test "get and get_all" do
      for_all_caches(fn cache ->
        :ok = cache.put_all(a: 1, a: 2, a: 2, b: 1, b: 2, c: 1)

        assert cache.get(:a) == [1, 2, 2]
        assert cache.get(:b) == [1, 2]
        assert cache.get(:c) == 1

        assert cache.get_all([:a, :b, :c]) == %{a: [1, 2, 2], b: [1, 2], c: 1}
      end)
    end

    test "take" do
      for_all_caches(fn cache ->
        :ok = cache.put_all(a: 1, a: 2, a: 2, b: 1, b: 2, c: 1)

        assert cache.take(:a) == [1, 2, 2]
        assert cache.take(:b) == [1, 2]
        assert cache.take(:c) == 1

        assert cache.get_all([:a, :b, :c]) == %{}
      end)
    end

    test "delete" do
      for_all_caches(fn cache ->
        :ok = cache.put(:a, 1)
        :ok = cache.put(:a, 2)
        :ok = cache.put(:a, 2)

        assert cache.get(:a) == [1, 2, 2]
        assert cache.delete(:a)
        refute cache.get(:a)
      end)
    end

    test "put_new" do
      for_all_caches(fn cache ->
        assert cache.put_new(:a, 1)
        :ok = cache.put(:a, 2)
        refute cache.put_new(:a, 3)

        assert cache.get(:a) == [1, 2]
      end)
    end

    test "has_key?" do
      for_all_caches(fn cache ->
        :ok = cache.put(:a, 1)
        :ok = cache.put(:a, 2)

        assert cache.has_key?(:a)
        refute cache.has_key?(:b)
      end)
    end

    test "ttl" do
      for_all_caches(fn cache ->
        :ok = cache.put(:a, 1, ttl: 5000)
        :ok = cache.put(:a, 2, ttl: 10_000)
        :ok = cache.put(:a, 3)

        [ttl1, ttl2, ttl3] = cache.ttl(:a)
        assert ttl1 > 1000
        assert ttl2 > 6000
        assert ttl3 == :infinity

        refute cache.ttl(:b)
      end)
    end

    test "size and flush" do
      for_all_caches(fn cache ->
        :ok = cache.put_all(a: 1, a: 2, a: 2, b: 1, b: 2, c: 1)

        assert cache.size() == 6
        assert cache.flush() == 6
        assert cache.size() == 0
      end)
    end

    test "all and stream using match_spec queries" do
      for_all_caches(fn cache ->
        :ok = cache.put_all(a: 1, a: 2, a: 2, b: 1, b: 2, c: 1)

        test_ms =
          fun do
            {_, key, value, _, _} when value == 2 -> key
          end

        res_stream = test_ms |> cache.stream() |> Enum.to_list() |> Enum.sort()
        res_query = test_ms |> cache.all() |> Enum.sort()

        assert res_stream == [:a, :a, :b]
        assert res_query == res_stream
      end)
    end
  end

  describe "unsupported commands" do
    test "replace" do
      for_all_caches(fn cache ->
        assert_raise ArgumentError, fn ->
          cache.replace(:a, 1)
        end
      end)
    end

    test "incr" do
      for_all_caches(fn cache ->
        assert_raise ArgumentError, fn ->
          cache.incr(:a)
        end
      end)
    end

    test "expire" do
      for_all_caches(fn cache ->
        :ok = cache.put(:a, 1)
        :ok = cache.put(:a, 2)

        assert_raise ArgumentError, fn ->
          cache.expire(:a, 5000)
        end
      end)
    end

    test "touch" do
      for_all_caches(fn cache ->
        :ok = cache.put(:a, 1)
        :ok = cache.put(:a, 2)

        assert_raise ArgumentError, fn ->
          cache.touch(:a)
        end
      end)
    end
  end

  ## Helpers

  defp for_all_caches(fun) do
    Enum.each(@caches, fn cache ->
      fun.(cache)
    end)
  end
end
