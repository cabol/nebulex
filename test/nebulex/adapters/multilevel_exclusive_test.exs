defmodule Nebulex.Adapters.MultilevelExclusiveTest do
  use ExUnit.Case, async: true
  use Nebulex.NodeCase
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
    l2: [gc_interval: @gc_interval],
    l3: [
      adapter: Nebulex.Adapters.Partitioned,
      primary: [gc_interval: @gc_interval]
    ]
  ]

  setup_with_dynamic_cache(Multilevel, :multilevel_exclusive,
    model: :exclusive,
    levels: @levels,
    fallback: fn _ -> nil end
  )

  describe "exclusive" do
    test "get" do
      :ok = Multilevel.put(1, 1, level: 1)
      :ok = Multilevel.put(2, 2, level: 2)
      :ok = Multilevel.put(3, 3, level: 3)

      assert Multilevel.get(1) == 1
      assert Multilevel.get(2, return: :key) == 2
      assert Multilevel.get(3) == 3
      refute Multilevel.get(2, level: 1)
      refute Multilevel.get(3, level: 1)
      refute Multilevel.get(1, level: 2)
      refute Multilevel.get(3, level: 2)
      refute Multilevel.get(1, level: 3)
      refute Multilevel.get(2, level: 3)
    end
  end

  describe "partitioned level" do
    test "returns cluster nodes" do
      assert Cluster.get_nodes(normalize_module_name([:multilevel_exclusive, "L3"])) == [node()]
    end

    test "joining new node" do
      node = :"node1@127.0.0.1"

      {:ok, pid} =
        start_cache(node, Multilevel,
          name: :multilevel_exclusive,
          model: :exclusive,
          levels: @levels
        )

      # check cluster nodes
      dist_cache_name = normalize_module_name([:multilevel_exclusive, "L3"])
      assert Cluster.get_nodes(dist_cache_name) == [node, node()]

      kv_pairs = for k <- 1..100, do: {k, k}

      Multilevel.transaction(fn ->
        assert Multilevel.put_all(kv_pairs) == :ok

        for k <- 1..100 do
          assert Multilevel.get(k) == k
        end
      end)

      :ok = stop_cache(:"node1@127.0.0.1", pid)
    end
  end
end
