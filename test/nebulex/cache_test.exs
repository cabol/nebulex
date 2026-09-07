defmodule Nebulex.Adapters.CacheTest do
  use ExUnit.Case, async: true

  # Cache API test cases
  use Nebulex.CacheTestCase

  import Nebulex.CacheCase, only: [setup_with_dynamic_cache: 2, t_sleep: 1]

  setup_with_dynamic_cache Nebulex.TestCache.Cache, __MODULE__

  describe "error" do
    test "because cache is stopped", %{cache: cache, name: name} do
      :ok = stop_supervised!(name)

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

  describe "KV:" do
    test "get_and_update", %{cache: cache} do
      fun = fn
        nil -> {nil, 1}
        val -> {val, val * 2}
      end

      assert cache.get_and_update!(1, fun) == {nil, 1}
      assert cache.get_and_update!(1, &{&1, &1 * 2}) == {1, 2}
      assert cache.get_and_update!(1, &{&1, &1 * 3}) == {2, 6}
      assert cache.get_and_update!(1, &{&1, nil}) == {6, nil}
      assert cache.get!(1) == nil
      assert cache.get_and_update!(1, &{&1, 6}) == {nil, 6}
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
      :ok = stop_supervised!(name)

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

    test "fetch_or_store stores the value in the cache if the key does not exist", %{cache: cache} do
      assert cache.fetch_or_store("lazy", fn -> {:ok, "value"} end) == {:ok, "value"}
      assert cache.get!("lazy") == "value"

      assert cache.fetch_or_store("lazy", fn -> {:ok, "new value"} end) == {:ok, "value"}
      assert cache.get!("lazy") == "value"
    end

    test "fetch_or_store returns error if the function returns an error", %{cache: cache} do
      assert {:error, %Nebulex.Error{reason: "error"}} =
               cache.fetch_or_store("lazy", fn -> {:error, "error"} end)

      refute cache.get!("lazy")
    end

    test "fetch_or_store raises if the function returns an invalid value", %{cache: cache} do
      msg =
        "the supplied lambda function must return {:ok, value} or " <>
          "{:error, reason}, got: :invalid"

      assert_raise RuntimeError, msg, fn ->
        cache.fetch_or_store!("lazy", fn -> :invalid end)
      end
    end

    test "fetch_or_store! stores the value in the cache if the key does not exist", %{cache: cache} do
      assert cache.fetch_or_store!("lazy", fn -> {:ok, "value"} end) == "value"
      assert cache.get!("lazy") == "value"

      assert cache.fetch_or_store!("lazy", fn -> {:ok, "new value"} end) == "value"
      assert cache.get!("lazy") == "value"
    end

    test "fetch_or_store! raises if an error occurs", %{cache: cache} do
      assert_raise Nebulex.Error, ~r"fetch_or_store command failed with reason: :error", fn ->
        cache.fetch_or_store!("lazy", fn -> {:error, :error} end)
      end

      refute cache.get!("lazy")
    end

    test "fetch_or_store! stores the value with TTL", %{cache: cache} do
      assert cache.fetch_or_store!("lazy", fn -> {:ok, "value"} end, ttl: :timer.seconds(1)) ==
               "value"

      assert cache.get!("lazy") == "value"

      _ = t_sleep(:timer.seconds(1) + 100)

      assert cache.fetch_or_store!("lazy", fn -> {:ok, "new value"} end, ttl: :timer.seconds(1)) ==
               "new value"

      assert cache.get!("lazy") == "new value"
    end

    test "get_or_store stores what the function returns if the key does not exist", %{cache: cache} do
      ["value", {:ok, "value"}, {:error, "error"}]
      |> Enum.with_index()
      |> Enum.each(fn {ret, i} ->
        assert cache.get_or_store(i, fn -> ret end) == {:ok, ret}
        assert cache.get!(i) == ret
      end)
    end

    test "get_or_store! stores what the function returns if the key does not exist", %{cache: cache} do
      ["value", {:ok, "value"}, {:error, "error"}]
      |> Enum.with_index()
      |> Enum.each(fn {ret, i} ->
        assert cache.get_or_store!(i, fn -> ret end) == ret
        assert cache.get!(i) == ret
      end)
    end

    test "get_or_store! stores the value with TTL", %{cache: cache} do
      assert cache.get_or_store!("ttl", fn -> "value" end, ttl: :timer.seconds(1)) == "value"
      assert cache.get!("ttl") == "value"

      _ = t_sleep(:timer.seconds(1) + 100)

      assert cache.get_or_store!("ttl", fn -> "new value" end) == "new value"
      assert cache.get!("ttl") == "new value"
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

  describe "transaction" do
    test "aborted", %{name: name, cache: cache} do
      key = {name, :aborted}

      Task.start_link(fn ->
        _ = cache.put_dynamic_cache(name)

        cache.transaction(
          fn ->
            :ok = cache.put(key, true)

            Process.sleep(1100)
          end,
          keys: [key],
          retries: 1
        )
      end)

      :ok = Process.sleep(200)

      assert_raise Nebulex.Error, ~r/transaction aborted\n\nError metadata:/, fn ->
        {:error, %Nebulex.Error{} = reason} =
          cache.transaction(
            fn -> cache.get(key) end,
            keys: [key],
            retries: 1
          )

        raise reason
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
