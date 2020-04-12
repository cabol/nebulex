defmodule Nebulex.Cache.QueryableTest do
  import Nebulex.SharedTestCase

  deftests "queryable" do
    import Nebulex.CacheHelpers

    test "all" do
      set1 = cache_put(@cache, 1..50)
      set2 = cache_put(@cache, 51..100)

      for x <- 1..100, do: assert(@cache.get(x) == x)
      expected = set1 ++ set2

      assert expected == :lists.usort(@cache.all())

      set3 = Enum.to_list(20..60)
      :ok = Enum.each(set3, &@cache.delete(&1))
      expected = :lists.usort(expected -- set3)

      assert expected == :lists.usort(@cache.all())
    end

    test "stream" do
      entries = for x <- 1..10, do: {x, x * 2}
      assert :ok == @cache.put_all(entries)

      expected = Keyword.keys(entries)
      assert expected == nil |> @cache.stream() |> Enum.to_list() |> :lists.usort()

      expected = Keyword.values(entries)

      assert expected ==
               nil
               |> @cache.stream(return: :value, page_size: 3)
               |> Enum.to_list()
               |> :lists.usort()

      assert_raise Nebulex.QueryError, fn ->
        :invalid_query
        |> @cache.stream()
        |> Enum.to_list()
      end
    end
  end
end
