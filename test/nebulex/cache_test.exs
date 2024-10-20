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

    test "get_and_update fails because cache is not started", %{cache: cache, name: name} do
      :ok = cache.stop()

      assert_raise Nebulex.CacheNotFoundError, ~r/unable to find cache: #{inspect(name)}/, fn ->
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
      assert cache.incr!(:counter_with_ttl, 1, keep_ttl: true) == 2
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

      ops = [
        fn -> cache.put(1, 13) end,
        fn -> cache.put!(1, 13) end,
        fn -> cache.get!(1) end,
        fn -> cache.delete!(1) end
      ]

      for fun <- ops do
        assert_raise Nebulex.CacheNotFoundError, ~r/unable to find cache: #{inspect(name)}/, fun
      end
    end
  end

  describe "persistence" do
    test "dump and load", %{cache: cache} = attrs do
      tmp = System.tmp_dir!()
      path = "#{tmp}/#{attrs[:name] || cache}"

      try do
        assert cache.count_all!() == 0
        assert cache.dump(path) == :ok
        assert File.exists?(path)
        assert cache.load(path) == :ok
        assert cache.count_all!() == 0

        count = 100
        unexpired = for x <- 1..count, into: %{}, do: {x, x}

        assert cache.put_all(unexpired) == :ok
        assert cache.put_all(%{a: 1, b: 2}, ttl: 10) == :ok
        assert cache.put_all(%{c: 1, d: 2}, ttl: :timer.hours(1)) == :ok
        assert cache.count_all!() == count + 4

        _ = t_sleep(1100)

        assert cache.dump(path) == :ok
        assert File.exists?(path)
        assert cache.delete_all!() == count + 4
        assert cache.count_all!() == 0

        assert cache.load(path) == :ok
        assert cache.get_all!(in: Enum.to_list(1..count)) |> Map.new() == unexpired
        assert cache.get_all!(in: [:a, :b, :c, :d]) |> Map.new() == %{c: 1, d: 2}
        assert cache.count_all!() == count + 2
      after
        File.rm_rf!(path)
      end
    end
  end

  describe "persistence error" do
    test "dump/2 fails because invalid path", %{cache: cache, name: name} do
      assert {:error,
              %Nebulex.Error{
                module: Nebulex.Error,
                metadata: metadata,
                reason: %File.Error{action: "open", path: "/invalid/path", reason: :enoent}
              }} = cache.dump("/invalid/path")

      assert Keyword.fetch!(metadata, :cache) == name
      assert Keyword.fetch!(metadata, :stacktrace) != []
    end

    test "load/2 error because invalid path", %{cache: cache, name: name} do
      assert {:error,
              %Nebulex.Error{
                module: Nebulex.Error,
                metadata: metadata,
                reason: %File.Error{action: "open", path: "wrong_file", reason: :enoent}
              }} = cache.load("wrong_file")

      assert Keyword.fetch!(metadata, :cache) == name
      assert Keyword.fetch!(metadata, :stacktrace) != []
    end
  end
end
