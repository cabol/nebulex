defmodule Nebulex.LocalTest do
  import Nebulex.TestCase

  deftests "local" do
    import Ex2ms
    import Nebulex.CacheHelpers

    alias Nebulex.{Adapter, Entry}
    alias Nebulex.Adapters.Local.Generation

    test "fail on init because invalid backend", %{cache: cache} do
      assert {:error, {%RuntimeError{message: msg}, _}} =
               cache.start_link(name: :invalid_backend, backend: :xyz)

      assert msg ==
               "expected backend: to be within the supported backends [:ets, :shards], got: :xyz"
    end

    test "fail with ArgumentError because cache was stopped", %{cache: cache} do
      :ok = cache.stop()

      msg = ~r"could not lookup Nebulex cache"
      assert_raise RuntimeError, msg, fn -> cache.put(1, 13) end
      assert_raise RuntimeError, msg, fn -> cache.get(1) end
      assert_raise RuntimeError, msg, fn -> cache.delete(1) end
    end

    test "get_and_update", %{cache: cache} do
      fun = fn
        nil -> {nil, 1}
        val -> {val, val * 2}
      end

      assert cache.get_and_update(1, fun) == {nil, 1}

      assert cache.get_and_update(1, &{&1, &1 * 2}) == {1, 2}
      assert cache.get_and_update(1, &{&1, &1 * 3}) == {2, 6}
      assert cache.get_and_update(1, &{&1, nil}) == {6, 6}
      assert cache.get(1) == 6
      assert cache.get_and_update(1, fn _ -> :pop end) == {6, nil}
      assert cache.get_and_update(1, fn _ -> :pop end) == {nil, nil}
      assert cache.get_and_update(3, &{&1, 3}) == {nil, 3}

      assert_raise ArgumentError, fn ->
        cache.get_and_update(1, fn _ -> :other end)
      end
    end

    test "incr with update", %{cache: cache} do
      assert cache.incr(:counter) == 1
      assert cache.incr(:counter) == 2

      assert cache.get_and_update(:counter, &{&1, &1 * 2}) == {2, 4}
      assert cache.incr(:counter) == 5

      assert cache.update(:counter, 1, &(&1 * 2)) == 10
      assert cache.incr(:counter, -10) == 0

      assert cache.put("foo", "bar") == :ok

      assert_raise ArgumentError, fn ->
        cache.incr("foo")
      end
    end

    test "incr with ttl", %{cache: cache} do
      assert cache.incr(:counter_with_ttl, 1, ttl: 1000) == 1
      assert cache.incr(:counter_with_ttl) == 2
      assert cache.get(:counter_with_ttl) == 2

      :ok = Process.sleep(1010)
      refute cache.get(:counter_with_ttl)

      assert cache.incr(:counter_with_ttl, 1, ttl: 5000) == 1
      assert cache.ttl(:counter_with_ttl) > 1000

      assert cache.expire(:counter_with_ttl, 500)
      :ok = Process.sleep(600)
      refute cache.get(:counter_with_ttl)
    end

    test "incr over an existing entry", %{cache: cache} do
      assert cache.put(:counter, 0) == :ok
      assert cache.incr(:counter) == 1
      assert cache.incr(:counter, 2) == 3
    end

    test "all and stream using match_spec queries", %{cache: cache, name: name} do
      values = cache_put(cache, 1..5, &(&1 * 2))
      _ = cache.new_generation(name: name)
      values = values ++ cache_put(cache, 6..10, &(&1 * 2))

      assert nil
             |> cache.stream(page_size: 3, return: :value)
             |> Enum.to_list()
             |> :lists.usort() == values

      {_, expected} = Enum.split(values, 5)

      test_ms =
        fun do
          {_, _, value, _, _} when value > 10 -> value
        end

      for action <- [:all, :stream] do
        assert all_or_stream(cache, action, test_ms, page_size: 3, return: :value) == expected

        msg = ~r"invalid match spec"

        assert_raise Nebulex.QueryError, msg, fn ->
          all_or_stream(cache, action, :invalid_query)
        end
      end
    end

    test "all and stream using expired and unexpired queries", %{cache: cache} do
      for action <- [:all, :stream] do
        expired = cache_put(cache, 1..5, &(&1 * 2), ttl: 1000)
        unexpired = cache_put(cache, 6..10, &(&1 * 2))

        all = expired ++ unexpired

        opts = [page_size: 3, return: :value]

        assert all_or_stream(cache, action, nil, opts) == all
        assert all_or_stream(cache, action, :unexpired, opts) == all
        assert all_or_stream(cache, action, :expired, opts) == []

        :ok = Process.sleep(1100)

        assert all_or_stream(cache, action, :unexpired, opts) == unexpired
        assert all_or_stream(cache, action, :expired, opts) == expired
      end
    end

    test "all returns entries", %{cache: cache} do
      assert cache.put_all([a: 1, b: 2, c: 3], ttl: 5000) == :ok

      assert all = cache.all(:unexpired, return: :entry)
      assert length(all) == 3

      for %Entry{} = entry <- all do
        assert Entry.ttl(entry) > 0
      end
    end

    test "unexpired entries through generations", %{cache: cache, name: name} do
      assert cache.put("foo", "bar") == :ok
      assert cache.get("foo") == "bar"
      assert cache.ttl("foo") == :infinity

      _ = cache.new_generation(name: name)
      assert cache.get("foo") == "bar"
    end

    test "push generations", %{cache: cache, name: name} do
      # should be empty
      refute cache.get(1)

      # set some entries
      for x <- 1..2, do: cache.put(x, x)

      # fetch one entry from new generation
      assert cache.get(1) == 1

      # fetch non-existent entries
      refute cache.get(3)
      refute cache.get(:non_existent)

      # create a new generation
      _ = cache.new_generation(name: name)

      # both entries should be in the old generation
      refute get_from_new(name, 1)
      refute get_from_new(name, 2)
      assert get_from_old(name, 1) == 1
      assert get_from_old(name, 2) == 2

      # fetch entry 1 and put it into the new generation
      assert cache.get(1) == 1
      assert get_from_new(name, 1) == 1
      refute get_from_new(name, 2)
      refute get_from_old(name, 1)
      assert get_from_old(name, 2) == 2

      # create a new generation, the old generation should be deleted
      _ = cache.new_generation(name: name)

      # entry 1 should be into the old generation and entry 2 deleted
      refute get_from_new(name, 1)
      refute get_from_new(name, 2)
      assert get_from_old(name, 1) == 1
      refute get_from_old(name, 2)
    end

    test "push generations with ttl", %{cache: cache, name: name} do
      assert cache.put(1, 1, ttl: 1000) == :ok
      assert cache.get(1) == 1

      _ = cache.new_generation(name: name)

      refute get_from_new(name, 1)
      assert get_from_old(name, 1) == 1
      assert cache.get(1) == 1

      :ok = Process.sleep(1100)

      refute cache.get(1)
      refute get_from_new(name, 1)
      refute get_from_old(name, 1)
    end

    ## Helpers

    defp get_from_new(name, key) do
      name
      |> Generation.newer()
      |> get_from(name, key)
    end

    defp get_from_old(name, key) do
      name
      |> Generation.list()
      |> List.last()
      |> get_from(name, key)
    end

    defp get_from(gen, name, key) do
      Adapter.with_meta(name, fn _, %{backend: backend} ->
        case backend.lookup(gen, key) do
          [] -> nil
          [{_, ^key, val, _, _}] -> val
        end
      end)
    end

    defp all_or_stream(cache, action, ms, opts \\ []) do
      cache
      |> apply(action, [ms, opts])
      |> case do
        list when is_list(list) ->
          :lists.usort(list)

        stream ->
          stream
          |> Enum.to_list()
          |> :lists.usort()
      end
    end
  end
end
