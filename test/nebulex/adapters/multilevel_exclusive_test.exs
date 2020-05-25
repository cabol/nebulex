defmodule Nebulex.Adapters.MultilevelExclusiveTest do
  use ExUnit.Case, async: true
  use Nebulex.MultilevelTest, cache: Nebulex.TestCache.MultilevelExclusive
  use Nebulex.Cache.QueryableTest, cache: Nebulex.TestCache.MultilevelExclusive
  use Nebulex.Cache.TransactionTest, cache: Nebulex.TestCache.MultilevelExclusive

  alias Nebulex.TestCache.MultilevelExclusive, as: Multilevel

  setup do
    {:ok, ml_cache} = @cache.start_link()
    :ok

    on_exit(fn ->
      :ok = Process.sleep(100)
      if Process.alive?(ml_cache), do: @cache.stop(ml_cache)
    end)
  end

  describe "exclusive" do
    test "get" do
      :ok = @l1.put(1, 1)
      :ok = @l2.put(2, 2)
      :ok = @l3.put(3, 3)

      assert Multilevel.get(1) == 1
      assert Multilevel.get(2, return: :key) == 2
      assert Multilevel.get(3) == 3
      refute @l1.get(2)
      refute @l1.get(3)
      refute @l2.get(1)
      refute @l2.get(3)
      refute @l3.get(1)
      refute @l3.get(2)
    end
  end
end
