defmodule Nebulex.Cache.QueryableTest do
  import Nebulex.SharedTestCase

  deftests do
    alias Nebulex.Object

    test "all" do
      set1 = for x <- 1..50, do: @cache.set(x, x)
      set2 = for x <- 51..100, do: @cache.set(x, x)

      for x <- 1..100, do: assert(@cache.get(x) == x)
      expected = set1 ++ set2

      assert expected == :lists.usort(@cache.all())

      set3 = for x <- 20..60, do: @cache.delete(x, return: :key)
      expected = :lists.usort(expected -- set3)

      assert expected == :lists.usort(@cache.all())
    end

    test "stream" do
      entries = for x <- 1..10, do: {x, x * 2}
      assert :ok == @cache.set_many(entries)

      expected = Keyword.keys(entries)
      assert expected == :all |> @cache.stream() |> Enum.to_list() |> :lists.usort()

      expected = Keyword.values(entries)

      assert expected ==
               :all
               |> @cache.stream(return: :value, page_size: 3)
               |> Enum.to_list()
               |> :lists.usort()

      stream = @cache.stream(:all, return: :object, page_size: 3)
      [%Object{key: 1, value: 2} | _] = stream |> Enum.to_list() |> :lists.usort()

      assert_raise Nebulex.QueryError, fn ->
        :invalid_query
        |> @cache.stream()
        |> Enum.to_list()
      end
    end
  end
end
