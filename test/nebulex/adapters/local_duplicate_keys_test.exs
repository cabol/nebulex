defmodule Nebulex.Adapters.LocalDuplicateKeysTest do
  use ExUnit.Case, async: true

  defmodule ETS do
    use Nebulex.Cache,
      otp_app: :nebulex,
      adapter: Nebulex.Adapters.Local
  end

  defmodule Shards do
    use Nebulex.Cache,
      otp_app: :nebulex,
      adapter: Nebulex.Adapters.Local
  end

  import Ex2ms

  alias Nebulex.Adapters.LocalDuplicateKeysTest.{ETS, Shards}

  setup do
    {:ok, ets} = ETS.start_link(backend_type: :duplicate_bag)
    {:ok, shards} = Shards.start_link(backend: :shards, backend_type: :duplicate_bag)

    on_exit(fn ->
      :ok = Process.sleep(100)
      if Process.alive?(ets), do: ETS.stop()
      if Process.alive?(shards), do: Shards.stop()
    end)

    {:ok, caches: [ETS, Shards]}
  end

  describe "duplicate keys" do
    test "get and get_all", %{caches: caches} do
      for_all_caches(caches, fn cache ->
        :ok = cache.put_all(a: 1, a: 2, a: 2, b: 1, b: 2, c: 1)

        assert cache.get(:a) == [1, 2, 2]
        assert cache.get(:b) == [1, 2]
        assert cache.get(:c) == 1

        assert cache.get_all!([:a, :b, :c]) == %{a: [1, 2, 2], b: [1, 2], c: 1}
      end)
    end

    test "take!", %{caches: caches} do
      for_all_caches(caches, fn cache ->
        :ok = cache.put_all(a: 1, a: 2, a: 2, b: 1, b: 2, c: 1)

        assert cache.take!(:a) == [1, 2, 2]
        assert cache.take!(:b) == [1, 2]
        assert cache.take!(:c) == 1

        assert cache.get_all!([:a, :b, :c]) == %{}
      end)
    end

    test "delete", %{caches: caches} do
      for_all_caches(caches, fn cache ->
        :ok = cache.put(:a, 1)
        :ok = cache.put(:a, 2)
        :ok = cache.put(:a, 2)

        assert cache.get(:a) == [1, 2, 2]
        assert cache.delete!(:a) == :ok
        refute cache.get(:a)
      end)
    end

    test "put_new", %{caches: caches} do
      for_all_caches(caches, fn cache ->
        assert cache.put_new(:a, 1) == {:ok, true}
        :ok = cache.put(:a, 2)
        assert cache.put_new(:a, 3) == {:ok, false}

        assert cache.get(:a) == [1, 2]
      end)
    end

    test "exists?", %{caches: caches} do
      for_all_caches(caches, fn cache ->
        :ok = cache.put(:a, 1)
        :ok = cache.put(:a, 2)

        assert cache.exists?(:a) == {:ok, true}
        assert cache.exists?(:b) == {:ok, false}
      end)
    end

    test "ttl", %{caches: caches} do
      for_all_caches(caches, fn cache ->
        :ok = cache.put(:a, 1, ttl: 5000)
        :ok = cache.put(:a, 2, ttl: 10_000)
        :ok = cache.put(:a, 3)

        {:ok, [ttl1, ttl2, ttl3]} = cache.ttl(:a)
        assert ttl1 > 1000
        assert ttl2 > 6000
        assert ttl3 == :infinity

        assert {:error, %Nebulex.KeyError{key: :b}} = cache.ttl(:b)
      end)
    end

    test "count_all and delete_all", %{caches: caches} do
      for_all_caches(caches, fn cache ->
        :ok = cache.put_all(a: 1, a: 2, a: 2, b: 1, b: 2, c: 1)

        assert cache.count_all() == 6
        assert cache.delete_all() == 6
        assert cache.count_all() == 0
      end)
    end

    test "all and stream using match_spec queries", %{caches: caches} do
      for_all_caches(caches, fn cache ->
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
    test "replace", %{caches: caches} do
      for_all_caches(caches, fn cache ->
        assert_raise ArgumentError, fn ->
          cache.replace(:a, 1)
        end
      end)
    end

    test "incr", %{caches: caches} do
      for_all_caches(caches, fn cache ->
        assert_raise ArgumentError, fn ->
          cache.incr(:a)
        end
      end)
    end

    test "expire", %{caches: caches} do
      for_all_caches(caches, fn cache ->
        :ok = cache.put(:a, 1)
        :ok = cache.put(:a, 2)

        assert_raise ArgumentError, fn ->
          cache.expire(:a, 5000)
        end
      end)
    end

    test "touch", %{caches: caches} do
      for_all_caches(caches, fn cache ->
        :ok = cache.put(:a, 1)
        :ok = cache.put(:a, 2)

        assert_raise ArgumentError, fn ->
          cache.touch(:a)
        end
      end)
    end
  end

  ## Helpers

  defp for_all_caches(caches, fun) do
    Enum.each(caches, fn cache ->
      fun.(cache)
    end)
  end
end
