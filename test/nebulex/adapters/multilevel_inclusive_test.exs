defmodule Nebulex.Adapters.MultilevelInclusiveTest do
  use ExUnit.Case, async: true
  use Nebulex.NodeCase
  use Nebulex.MultilevelTest
  use Nebulex.Cache.QueryableTest
  use Nebulex.Cache.TransactionTest

  import Nebulex.CacheCase

  alias Nebulex.Adapters.Local.Generation
  alias Nebulex.Cache.Cluster
  alias Nebulex.TestCache.DelayedReadAdapter
  alias Nebulex.TestCache.Multilevel
  alias Nebulex.TestCache.Multilevel.{L1, L2, L3}
  alias Nebulex.TestCache.MultilevelWithDelay

  @gc_interval :timer.hours(1)

  @levels [
    {
      L1,
      name: :multilevel_inclusive_l1, gc_interval: @gc_interval, backend: :shards, partitions: 2
    },
    {
      L2,
      name: :multilevel_inclusive_l2, primary: [gc_interval: @gc_interval]
    },
    {
      L3,
      name: :multilevel_inclusive_l3,
      primary: [gc_interval: @gc_interval, backend: :shards, partitions: 2]
    }
  ]

  setup_with_dynamic_cache(Multilevel, :multilevel_inclusive,
    model: :inclusive,
    levels: @levels
  )

  describe "multilevel inclusive" do
    test "returns partitions for L1 with shards backend", %{name: name} do
      assert :"#{name}_l1"
             |> Generation.newer()
             |> :shards.table_meta()
             |> :shards_meta.partitions() == 2
    end

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
      assert Multilevel.get(3, level: 3) == 3
    end

    test "get_all [replicate: true]" do
      :ok = Process.sleep(2000)
      :ok = Multilevel.put(1, 1, level: 1)
      :ok = Multilevel.put(2, 2, level: 2)
      :ok = Multilevel.put(3, 3, level: 3)

      assert Multilevel.get_all([1]) == %{1 => 1}
      refute Multilevel.get(1, level: 2)
      refute Multilevel.get(1, level: 3)

      assert Multilevel.get_all([1, 2]) == %{1 => 1, 2 => 2}
      assert Multilevel.get(2, level: 1) == 2
      assert Multilevel.get(2, level: 2) == 2
      refute Multilevel.get(2, level: 3)

      assert Multilevel.get(3, level: 3) == 3
      refute Multilevel.get(3, level: 1)
      refute Multilevel.get(3, level: 2)

      assert Multilevel.get_all([1, 2, 3]) == %{1 => 1, 2 => 2, 3 => 3}
      assert Multilevel.get(3, level: 1) == 3
      assert Multilevel.get(3, level: 2) == 3
      assert Multilevel.get(3, level: 3) == 3
    end

    test "get_all [replicate: false]" do
      :ok = Process.sleep(2000)
      :ok = Multilevel.put(1, 1, level: 1)
      :ok = Multilevel.put(2, 2, level: 2)
      :ok = Multilevel.put(3, 3, level: 3)

      assert Multilevel.get_all([1], replicate: false) == %{1 => 1}
      refute Multilevel.get(1, level: 2)
      refute Multilevel.get(1, level: 3)

      assert Multilevel.get_all([1, 2], replicate: false) == %{1 => 1, 2 => 2}
      refute Multilevel.get(2, level: 1)
      assert Multilevel.get(2, level: 2) == 2
      refute Multilevel.get(2, level: 3)

      assert Multilevel.get(3, level: 3) == 3
      refute Multilevel.get(3, level: 1)
      refute Multilevel.get(3, level: 2)

      assert Multilevel.get_all([1, 2, 3], replicate: false) == %{1 => 1, 2 => 2, 3 => 3}
      refute Multilevel.get(3, level: 1)
      refute Multilevel.get(3, level: 2)
      assert Multilevel.get(3, level: 3) == 3
    end

    test "get boolean" do
      :ok = Multilevel.put(1, true, level: 1)
      :ok = Multilevel.put(2, false, level: 1)

      assert Multilevel.get(1) == true
      assert Multilevel.get(2) == false
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

  describe "delayed multilevel" do
    setup_with_dynamic_cache(MultilevelWithDelay, :multilevel_inclusive_with_delay,
      model: :inclusive,
      levels: [
        {MultilevelWithDelay.L1,
         name: :multilevel_inclusive_with_delay_l1,
         gc_interval: @gc_interval,
         backend: :shards,
         partitions: 2},
        {MultilevelWithDelay.L2,
         name: :multilevel_inclusive_with_delay_l2,
         gc_interval: @gc_interval,
         backend: :shards,
         partitions: 2}
      ]
    )

    test "does not replicate the data if the cache expires during replication" do
      # reading from L2 will take 500ms
      DelayedReadAdapter.put_read_delay(500)

      # since we call both `get` and `ttl` the total read time will be 1000ms
      :ok = MultilevelWithDelay.put(:key, :data, ttl: 700, level: 2)

      # the key should expire between the `get` and `tl` calls, so the data
      # should be returned but not replicated
      assert MultilevelWithDelay.get(:key) == :data
      assert MultilevelWithDelay.get(:key, level: 1) == nil

      assert MultilevelWithDelay.ttl(:key) == nil
    end
  end

  describe "distributed levels" do
    test "return cluster nodes" do
      assert Cluster.get_nodes(:multilevel_inclusive_l2) == [node()]
      assert Cluster.get_nodes(:multilevel_inclusive_l3) == [node()]
    end

    test "joining new node" do
      node = :"node1@127.0.0.1"

      {:ok, pid} =
        start_cache(node, Multilevel,
          name: :multilevel_inclusive,
          model: :inclusive,
          levels: @levels
        )

      # check cluster nodes
      assert Cluster.get_nodes(:multilevel_inclusive_l3) == [node, node()]

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
