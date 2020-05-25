defmodule Nebulex.Adapters.MultilevelInclusiveTest do
  use ExUnit.Case, async: true
  use Nebulex.MultilevelTest
  use Nebulex.Cache.QueryableTest
  use Nebulex.Cache.TransactionTest

  import Nebulex.Helpers
  import Nebulex.TestCase

  alias Nebulex.Cache.Cluster
  alias Nebulex.TestCache.Multilevel
  alias Nebulex.Time

  @gc_interval Time.expiry_time(1, :hour)

  @levels [
    l1: [gc_interval: @gc_interval, backend: :shards, partitions: 2],
    l2: [
      adapter: Nebulex.Adapters.Partitioned,
      primary: [gc_interval: @gc_interval]
    ],
    l3: [
      adapter: Nebulex.Adapters.Partitioned,
      primary: [
        gc_interval: @gc_interval,
        backend: :shards,
        partitions: 2
      ]
    ]
  ]

  setup_with_dynamic_cache(Multilevel, :multilevel_inclusive,
    model: :inclusive,
    levels: @levels,
    fallback: fn _ -> nil end
  )

  describe "inclusive" do
    test "get" do
      :ok = Process.sleep(2000)
      :ok = Multilevel.put(1, 1, level: 1)
      :ok = Multilevel.put(2, 2, level: 2)
      :ok = Multilevel.put(3, 3, level: 3)

      assert Multilevel.get(1) == 1
      refute Multilevel.get(1, level: 2)
      refute Multilevel.get(1, level: 3)

      assert Multilevel.get(2) == 2
      assert Multilevel.get(2, level: 1) == 2
      assert Multilevel.get(2, level: 2) == 2
      refute Multilevel.get(2, level: 3)

      assert Multilevel.get(3, level: 3) == 3
      refute Multilevel.get(3, level: 1)
      refute Multilevel.get(3, level: 2)

      assert Multilevel.get(3) == 3
      assert Multilevel.get(3, level: 1) == 3
      assert Multilevel.get(3, level: 2) == 3
      assert Multilevel.get(3, level: 2) == 3
    end

    test "fetched value is replicated with TTL on previous levels" do
      assert Multilevel.put(:a, 1, ttl: 1000) == :ok
      assert Multilevel.ttl(:a) > 0

      :ok = Process.sleep(1100)
      refute Multilevel.get(:a, level: 1)
      refute Multilevel.get(:a, level: 2)
      refute Multilevel.get(:a, level: 3)

      assert Multilevel.put(:b, 1, level: 3) == :ok
      assert Multilevel.ttl(:b) == :infinity
      assert Multilevel.expire(:b, 1000)
      assert Multilevel.ttl(:b) > 0
      refute Multilevel.get(:b, level: 1)
      refute Multilevel.get(:b, level: 2)
      assert Multilevel.get(:b, level: 3) == 1

      assert Multilevel.get(:b) == 1
      assert Multilevel.get(:b, level: 1) == 1
      assert Multilevel.get(:b, level: 2) == 1
      assert Multilevel.get(:b, level: 3) == 1

      :ok = Process.sleep(1100)
      refute Multilevel.get(:b, level: 1)
      refute Multilevel.get(:b, level: 2)
      refute Multilevel.get(:b, level: 3)
    end
  end

  describe "partitioned levels" do
    test "return cluster nodes" do
      assert Cluster.get_nodes(normalize_module_name([:multilevel_inclusive, "L2"])) == [node()]
      assert Cluster.get_nodes(normalize_module_name([:multilevel_inclusive, "L3"])) == [node()]
    end
  end
end
