defmodule Nebulex.Adapters.MultilevelExclusiveTest do
  use ExUnit.Case, async: true
  use Nebulex.MultilevelTest, cache: Nebulex.TestCache.MultilevelExclusive
  use Nebulex.Cache.QueryableTest, cache: Nebulex.TestCache.MultilevelExclusive
  use Nebulex.Cache.TransactionTest, cache: Nebulex.TestCache.MultilevelExclusive

  alias Nebulex.TestCache.MultilevelExclusive, as: Multilevel

  test "get for exclusive mode" do
    :ok = @l1.put(1, 1)
    :ok = @l2.put(2, 2)
    :ok = @l3.put(3, 3)

    assert 1 == Multilevel.get(1)
    assert 2 == Multilevel.get(2, return: :key)
    assert 3 == Multilevel.get(3)
    refute @l1.get(2)
    refute @l1.get(3)
    refute @l2.get(1)
    refute @l2.get(3)
    refute @l3.get(1)
    refute @l3.get(2)
  end
end
