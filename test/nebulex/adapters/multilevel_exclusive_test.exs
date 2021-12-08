defmodule Nebulex.Adapters.MultilevelExclusiveTest do
  use ExUnit.Case, async: true
  use Nebulex.NodeCase
  use Nebulex.MultilevelTest
  use Nebulex.Cache.QueryableTest
  use Nebulex.Cache.TransactionTest

  import Nebulex.CacheCase

  alias Nebulex.Adapters.Local.Generation
  alias Nebulex.Cache.Cluster
  alias Nebulex.TestCache.Multilevel
  alias Nebulex.TestCache.Multilevel.{L1, L2, L3}

  @gc_interval :timer.hours(1)

  @levels [
    {
      L1,
      name: :multilevel_exclusive_l1, gc_interval: @gc_interval, backend: :shards, partitions: 2
    },
    {
      L2,
      name: :multilevel_exclusive_l2, primary: [gc_interval: @gc_interval]
    },
    {
      L3,
      name: :multilevel_exclusive_l3,
      primary: [gc_interval: @gc_interval, backend: :shards, partitions: 2]
    }
  ]

  setup_with_dynamic_cache(Multilevel, :multilevel_exclusive,
    model: :exclusive,
    levels: @levels
  )

  describe "multilevel exclusive" do
    test "returns partitions for L1 with shards backend", %{name: name} do
      assert :"#{name}_l1"
             |> Generation.newer()
             |> :shards.meta()
             |> :shards_meta.partitions() == 2
    end

    test "get" do
      :ok = Multilevel.put(1, 1, level: 1)
      :ok = Multilevel.put(2, 2, level: 2)
      :ok = Multilevel.put(3, 3, level: 3)

      assert Multilevel.get!(1) == 1
      assert Multilevel.get!(2, return: :key) == 2
      assert Multilevel.get!(3) == 3
      refute Multilevel.get!(2, nil, level: 1)
      refute Multilevel.get!(3, nil, level: 1)
      refute Multilevel.get!(1, nil, level: 2)
      refute Multilevel.get!(3, nil, level: 2)
      refute Multilevel.get!(1, nil, level: 3)
      refute Multilevel.get!(2, nil, level: 3)
    end
  end

  describe "partitioned level" do
    test "returns cluster nodes" do
      assert Cluster.get_nodes(:multilevel_exclusive_l3) == [node()]
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
      assert Cluster.get_nodes(:multilevel_exclusive_l3) == [node, node()]

      kv_pairs = for k <- 1..100, do: {k, k}

      Multilevel.transaction(fn ->
        assert Multilevel.put_all(kv_pairs) == :ok

        for k <- 1..100 do
          assert Multilevel.get!(k) == k
        end
      end)

      :ok = stop_cache(:"node1@127.0.0.1", pid)
    end
  end
end
