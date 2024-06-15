defmodule Nebulex.LocalTest do
  import Nebulex.CacheCase

  deftests do
    import Ex2ms
    import Nebulex.CacheCase

    alias Nebulex.{Adapter, Entry}

    describe "error" do
      test "on init because invalid backend", %{cache: cache} do
        _ = Process.flag(:trap_exit, true)

        assert {:error, {%RuntimeError{message: msg}, _}} =
                 cache.start_link(name: :invalid_backend, backend: :xyz)

        assert msg ==
                 "expected backend: option to be one of the supported " <>
                   "backends [:ets, :shards], got: :xyz"
      end

      test "because cache is stopped", %{cache: cache} do
        :ok = cache.stop()

        msg = ~r"could not lookup Nebulex cache"
        assert_raise Nebulex.RegistryLookupError, msg, fn -> cache.put(1, 13) end
        assert_raise Nebulex.RegistryLookupError, msg, fn -> cache.get(1) end
        assert_raise Nebulex.RegistryLookupError, msg, fn -> cache.delete(1) end
      end
    end

    describe "entry:" do
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

      test "incr and update", %{cache: cache} do
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

      test "incr existing entry", %{cache: cache} do
        assert cache.put(:counter, 0) == :ok
        assert cache.incr(:counter) == 1
        assert cache.incr(:counter, 2) == 3
      end
    end

    describe "queryable:" do
      test "ETS match_spec queries", %{cache: cache, name: name} do
        values = cache_put(cache, 1..5, &(&1 * 2))
        _ = new_generation(cache, name)
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

      test "expired and unexpired queries", %{cache: cache} do
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

      test "all entries", %{cache: cache} do
        assert cache.put_all([a: 1, b: 2, c: 3], ttl: 5000) == :ok

        assert all = cache.all(:unexpired, return: :entry)
        assert length(all) == 3

        for %Entry{} = entry <- all do
          assert Entry.ttl(entry) > 0
        end
      end

      test "delete all expired and unexpired entries", %{cache: cache} do
        _ = cache_put(cache, 1..5, & &1, ttl: 1500)
        _ = cache_put(cache, 6..10)

        assert cache.delete_all(:expired) == 0
        assert cache.count_all(:expired) == 0

        :ok = Process.sleep(1600)

        assert cache.delete_all(:expired) == 5
        assert cache.count_all(:expired) == 0
        assert cache.count_all(:unexpired) == 5

        assert cache.delete_all(:unexpired) == 5
        assert cache.count_all(:unexpired) == 0
        assert cache.count_all() == 0
      end

      test "delete all matched entries", %{cache: cache, name: name} do
        values = cache_put(cache, 1..5)

        _ = new_generation(cache, name)

        values = values ++ cache_put(cache, 6..10)

        assert cache.count_all() == 10

        test_ms =
          fun do
            {_, _, value, _, _} when rem(value, 2) == 0 -> value
          end

        {expected, rem} = Enum.split_with(values, &(rem(&1, 2) == 0))

        assert cache.count_all(test_ms) == 5
        assert cache.all(test_ms) |> Enum.sort() == Enum.sort(expected)

        assert cache.delete_all(test_ms) == 5
        assert cache.count_all(test_ms) == 0
        assert cache.all() |> Enum.sort() == Enum.sort(rem)
      end

      test "delete all entries with special query {:in, keys}", %{cache: cache} do
        entries = for x <- 1..10, into: %{}, do: {x, x}

        :ok = cache.put_all(entries)

        assert cache.count_all() == 10

        assert cache.delete_all({:in, [2, 4, 6, 8, 10, 12]}) == 5

        assert cache.count_all() == 5
        assert cache.all() |> Enum.sort() == [1, 3, 5, 7, 9]
      end

      test "delete all entries with special query {:in, keys} (nested tuples)", %{cache: cache} do
        [
          {1, {:foo, "bar"}},
          {2, {nil, nil}},
          {3, {nil, {nil, nil}}},
          {4, {nil, {nil, nil, {nil, nil}}}},
          {5, {:a, {:b, {:c, {:d, {:e, "f"}}}}}},
          {6, {:a, :b, {:c, :d, {:e, :f, {:g, :h, {:i, :j, "k"}}}}}}
        ]
        |> Enum.each(fn {k, v} ->
          :ok = cache.put(k, v)

          assert cache.count_all() == 1
          assert cache.delete_all({:in, [k]}) == 1
          assert cache.count_all() == 0
        end)
      end
    end

    describe "older generation hitted on" do
      test "put/3 (key is removed from older generation)", %{cache: cache, name: name} do
        :ok = cache.put("foo", "bar")

        _ = new_generation(cache, name)

        refute get_from_new(cache, name, "foo")
        assert get_from_old(cache, name, "foo") == "bar"

        :ok = cache.put("foo", "bar bar")

        assert get_from_new(cache, name, "foo") == "bar bar"
        refute get_from_old(cache, name, "foo")
      end

      test "put_new/3 (fallback to older generation)", %{cache: cache, name: name} do
        assert cache.put_new("foo", "bar") == true

        _ = new_generation(cache, name)

        refute get_from_new(cache, name, "foo")
        assert get_from_old(cache, name, "foo") == "bar"

        assert cache.put_new("foo", "bar") == false

        refute get_from_new(cache, name, "foo")
        assert get_from_old(cache, name, "foo") == "bar"

        _ = new_generation(cache, name)

        assert cache.put_new("foo", "bar") == true

        assert get_from_new(cache, name, "foo") == "bar"
        refute get_from_old(cache, name, "foo")
      end

      test "replace/3 (fallback to older generation)", %{cache: cache, name: name} do
        assert cache.replace("foo", "bar bar") == false

        :ok = cache.put("foo", "bar")

        _ = new_generation(cache, name)

        refute get_from_new(cache, name, "foo")
        assert get_from_old(cache, name, "foo") == "bar"

        assert cache.replace("foo", "bar bar") == true

        assert get_from_new(cache, name, "foo") == "bar bar"
        refute get_from_old(cache, name, "foo")

        _ = new_generation(cache, name)
        _ = new_generation(cache, name)

        assert cache.replace("foo", "bar bar") == false
      end

      test "put_all/2 skips nil values", %{cache: cache} do
        assert cache.put_all(a: 1, b: nil, nil: nil) == :ok
        assert cache.get_all([:a, :b]) == %{a: 1}
      end

      test "put_all/2 (keys are removed from older generation)", %{cache: cache, name: name} do
        entries = Enum.map(1..100, &{{:key, &1}, &1})

        :ok = cache.put_all(entries)

        _ = new_generation(cache, name)

        Enum.each(entries, fn {k, v} ->
          refute get_from_new(cache, name, k)
          assert get_from_old(cache, name, k) == v
        end)

        :ok = cache.put_all(entries)

        Enum.each(entries, fn {k, v} ->
          assert get_from_new(cache, name, k) == v
          refute get_from_old(cache, name, k)
        end)
      end

      test "put_new_all/2 (fallback to older generation)", %{cache: cache, name: name} do
        entries = Enum.map(1..100, &{&1, &1})

        assert cache.put_new_all(entries) == true

        _ = new_generation(cache, name)

        Enum.each(entries, fn {k, v} ->
          refute get_from_new(cache, name, k)
          assert get_from_old(cache, name, k) == v
        end)

        assert cache.put_new_all(entries) == false

        Enum.each(entries, fn {k, v} ->
          refute get_from_new(cache, name, k)
          assert get_from_old(cache, name, k) == v
        end)

        _ = new_generation(cache, name)

        assert cache.put_new_all(entries) == true

        Enum.each(entries, fn {k, v} ->
          assert get_from_new(cache, name, k) == v
          refute get_from_old(cache, name, k)
        end)
      end

      test "expire/3 (fallback to older generation)", %{cache: cache, name: name} do
        assert cache.put("foo", "bar") == :ok

        _ = new_generation(cache, name)

        refute get_from_new(cache, name, "foo")
        assert get_from_old(cache, name, "foo") == "bar"

        assert cache.expire("foo", 200) == true

        assert get_from_new(cache, name, "foo") == "bar"
        refute get_from_old(cache, name, "foo")

        :ok = Process.sleep(210)

        refute cache.get("foo")
      end

      test "incr/3 (fallback to older generation)", %{cache: cache, name: name} do
        assert cache.put(:counter, 0, ttl: 200) == :ok

        _ = new_generation(cache, name)

        refute get_from_new(cache, name, :counter)
        assert get_from_old(cache, name, :counter) == 0

        assert cache.incr(:counter) == 1
        assert cache.incr(:counter) == 2

        assert get_from_new(cache, name, :counter) == 2
        refute get_from_old(cache, name, :counter)

        :ok = Process.sleep(210)

        assert cache.incr(:counter) == 1
      end

      test "all/2 (no duplicates)", %{cache: cache, name: name} do
        entries = for x <- 1..20, into: %{}, do: {x, x}
        keys = Map.keys(entries) |> Enum.sort()

        :ok = cache.put_all(entries)

        assert cache.count_all() == 20
        assert cache.all() |> Enum.sort() == keys

        _ = new_generation(cache, name)

        :ok = cache.put_all(entries)

        assert cache.count_all() == 20
        assert cache.all() |> Enum.sort() == keys

        _ = new_generation(cache, name)

        more_entries = for x <- 10..30, into: %{}, do: {x, x}
        more_keys = Map.keys(more_entries) |> Enum.sort()

        :ok = cache.put_all(more_entries)

        assert cache.count_all() == 30
        assert cache.all() |> Enum.sort() == (keys ++ more_keys) |> Enum.uniq()

        _ = new_generation(cache, name)

        assert cache.count_all() == 21
        assert cache.all() |> Enum.sort() == more_keys
      end
    end

    describe "generation" do
      test "created with unexpired entries", %{cache: cache, name: name} do
        assert cache.put("foo", "bar") == :ok
        assert cache.get("foo") == "bar"
        assert cache.ttl("foo") == :infinity

        _ = new_generation(cache, name)

        assert cache.get("foo") == "bar"
      end

      test "lifecycle", %{cache: cache, name: name} do
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
        _ = new_generation(cache, name)

        # both entries should be in the old generation
        refute get_from_new(cache, name, 1)
        refute get_from_new(cache, name, 2)
        assert get_from_old(cache, name, 1) == 1
        assert get_from_old(cache, name, 2) == 2

        # fetch entry 1 and put it into the new generation
        assert cache.get(1) == 1
        assert get_from_new(cache, name, 1) == 1
        refute get_from_new(cache, name, 2)
        refute get_from_old(cache, name, 1)
        assert get_from_old(cache, name, 2) == 2

        # create a new generation, the old generation should be deleted
        _ = new_generation(cache, name)

        # entry 1 should be into the old generation and entry 2 deleted
        refute get_from_new(cache, name, 1)
        refute get_from_new(cache, name, 2)
        assert get_from_old(cache, name, 1) == 1
        refute get_from_old(cache, name, 2)
      end

      test "creation with ttl", %{cache: cache, name: name} do
        assert cache.put(1, 1, ttl: 1000) == :ok
        assert cache.get(1) == 1

        _ = new_generation(cache, name)

        refute get_from_new(cache, name, 1)
        assert get_from_old(cache, name, 1) == 1
        assert cache.get(1) == 1

        :ok = Process.sleep(1100)

        refute cache.get(1)
        refute get_from_new(cache, name, 1)
        refute get_from_old(cache, name, 1)
      end
    end

    ## Helpers

    defp new_generation(cache, name) do
      cache.with_dynamic_cache(name, fn ->
        cache.new_generation()
      end)
    end

    defp get_from_new(cache, name, key) do
      cache.with_dynamic_cache(name, fn ->
        get_from(cache.newer_generation(), name, key)
      end)
    end

    defp get_from_old(cache, name, key) do
      cache.with_dynamic_cache(name, fn ->
        cache.generations()
        |> List.last()
        |> get_from(name, key)
      end)
    end

    defp get_from(gen, name, key) do
      Adapter.with_meta(name, fn _, %{backend: backend} ->
        case backend.lookup(gen, key) do
          [] -> nil
          [{_, ^key, val, _, _}] -> val
        end
      end)
    end

    defp all_or_stream(cache, action, ms, opts \\ [])

    defp all_or_stream(cache, :all, ms, opts) do
      ms
      |> cache.all(opts)
      |> handle_query_result()
    end

    defp all_or_stream(cache, :stream, ms, opts) do
      ms
      |> cache.stream(opts)
      |> handle_query_result()
    end

    defp handle_query_result(list) when is_list(list) do
      :lists.usort(list)
    end

    defp handle_query_result(stream) do
      stream
      |> Enum.to_list()
      |> :lists.usort()
    end
  end
end
