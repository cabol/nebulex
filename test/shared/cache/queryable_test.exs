defmodule Nebulex.Cache.QueryableTest do
  import Nebulex.CacheCase

  deftests do
    import Nebulex.CacheCase

    describe "all/2" do
      test "ok: returns all keys in cache", %{cache: cache} do
        set1 = cache_put(cache, 1..50)
        set2 = cache_put(cache, 51..100)

        for x <- 1..100, do: assert(cache.fetch!(x) == x)
        expected = set1 ++ set2

        assert cache.all!() |> :lists.usort() == expected

        set3 = Enum.to_list(20..60)
        :ok = Enum.each(set3, &cache.delete!(&1))
        expected = :lists.usort(expected -- set3)

        assert cache.all!() |> :lists.usort() == expected
      end

      test "error: query error", %{cache: cache} = test_opts do
        on_error = test_opts[:on_error] || fn %Nebulex.QueryError{} -> :ok end

        assert {:error, reason} = cache.all(:invalid)
        on_error.(reason)
      end
    end

    describe "stream/2" do
      @entries for x <- 1..10, into: %{}, do: {x, x * 2}

      test "ok: returns all keys in cache", %{cache: cache} do
        :ok = cache.put_all(@entries)

        assert nil
               |> cache.stream!()
               |> Enum.to_list()
               |> :lists.usort() == Map.keys(@entries)
      end

      test "ok: returns all values in cache", %{cache: cache} do
        :ok = cache.put_all(@entries)

        assert nil
               |> cache.stream!(return: :value, page_size: 3)
               |> Enum.to_list()
               |> :lists.usort() == Map.values(@entries)
      end

      test "ok: returns all key/value pairs in cache", %{cache: cache} do
        :ok = cache.put_all(@entries)

        assert nil
               |> cache.stream!(return: {:key, :value}, page_size: 3)
               |> Enum.to_list()
               |> :lists.usort() == :maps.to_list(@entries)
      end

      test "error: raises when query is invalid", %{cache: cache} do
        assert_raise Nebulex.QueryError, fn ->
          :invalid_query
          |> cache.stream!()
          |> Enum.to_list()
        end
      end
    end

    describe "delete_all/2" do
      test "ok: evicts all entries in the cache", %{cache: cache} do
        Enum.each(1..2, fn _ ->
          entries = cache_put(cache, 1..50)

          assert cache.all!() |> :lists.usort() |> length() == length(entries)

          cached = cache.count_all!()
          assert cache.delete_all!() == cached
          assert cache.count_all!() == 0
        end)
      end

      test "error: query error", %{cache: cache} = test_opts do
        on_error = test_opts[:on_error] || fn %Nebulex.QueryError{} -> :ok end

        assert {:error, reason} = cache.delete_all(:invalid)
        on_error.(reason)
      end
    end

    describe "count_all/2" do
      test "ok: returns the total number of cached entries", %{cache: cache} do
        for x <- 1..100, do: cache.put(x, x)
        total = cache.all!() |> length()
        assert cache.count_all!() == total

        for x <- 1..50, do: cache.delete!(x)
        total = cache.all!() |> length()
        assert cache.count_all!() == total

        for x <- 51..60, do: assert(cache.fetch!(x) == x)
      end

      test "error: query error", %{cache: cache} = test_opts do
        on_error = test_opts[:on_error] || fn %Nebulex.QueryError{} -> :ok end

        assert {:error, reason} = cache.count_all(:invalid)
        on_error.(reason)
      end
    end
  end
end
