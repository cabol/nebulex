defmodule Nebulex.Adapters.ReplicatedTest do
  use Nebulex.NodeCase
  use Nebulex.CacheTest

  import Nebulex.TestCase

  alias Nebulex.TestCache.Replicated

  setup do
    node_pid_list = start_caches(cluster_nodes(), [{Replicated, []}])

    on_exit(fn ->
      :ok = Process.sleep(100)
      stop_caches(node_pid_list)
    end)

    {:ok, cache: Replicated, name: Replicated}
  end

  describe "c:init/1" do
    test "fail because invalid primary adapter" do
      assert {:error, {%RuntimeError{message: msg}, _}} =
               Replicated.start_link(
                 name: :invalid_primary_adapter,
                 primary: [adapter: __MODULE__]
               )

      mod = inspect(__MODULE__)
      assert Regex.match?(~r"expected #{mod} to implement the behaviour Nebulex.Adapter", msg)
    end
  end

  describe "replicated cache" do
    test "set" do
      assert Replicated.put(1, 1) == :ok
      assert Replicated.get(1) == 1

      assert_for_all_replicas(Replicated, :get, [1], 1)

      assert Replicated.put_all(a: 1, b: 2, c: 3) == :ok

      assert_for_all_replicas(Replicated, :get_all, [[:a, :b, :c]], %{a: 1, b: 2, c: 3})
    end

    test "delete" do
      assert Replicated.put("foo", "bar") == :ok
      assert Replicated.get("foo") == "bar"

      assert_for_all_replicas(Replicated, :get, ["foo"], "bar")

      assert Replicated.delete("foo") == :ok
      refute Replicated.get("foo")

      assert_for_all_replicas(Replicated, :get, ["foo"], nil)
    end

    test "take" do
      assert Replicated.put("foo", "bar") == :ok
      assert Replicated.get("foo") == "bar"

      assert_for_all_replicas(Replicated, :get, ["foo"], "bar")

      assert Replicated.take("foo") == "bar"
      refute Replicated.get("foo")

      assert_for_all_replicas(Replicated, :take, ["foo"], nil)
    end

    test "incr" do
      assert Replicated.incr(:counter, 3) == 3
      assert Replicated.incr(:counter) == 4

      assert_for_all_replicas(Replicated, :get, [:counter], 4)
    end

    test "flush" do
      assert Replicated.put_all(a: 1, b: 2, c: 3) == :ok

      assert_for_all_replicas(Replicated, :get_all, [[:a, :b, :c]], %{a: 1, b: 2, c: 3})

      assert Replicated.flush() == 3
      assert Replicated.size() == 0

      assert_for_all_replicas(Replicated, :get_all, [[:a, :b, :c]], %{})
    end
  end

  describe "cluster" do
    test "rpc errors" do
      with_dynamic_cache(
        Replicated,
        [name: :replicated_mock, primary: [adapter: Nebulex.TestCache.AdapterMock]],
        fn ->
          _ = Process.flag(:trap_exit, true)

          msg = ~r"RPC error executing action: put_all\n\nErrors:\n\n\[\n  {{:exit,"

          assert_raise Nebulex.RPCMultiCallError, msg, fn ->
            Replicated.put_all(a: 1, b: 2)
          end
        end
      )
    end

    test "join new cache node" do
      assert Replicated.put_all(a: 1, b: 2) == :ok
      assert Replicated.put(:c, 3, ttl: 5000) == :ok
      assert :lists.usort(Replicated.nodes()) == :lists.usort(cluster_nodes())

      assert_for_all_replicas(Replicated, :get_all, [[:a, :b, :c]], %{a: 1, b: 2, c: 3})

      # join new cache node
      node_pid_list = start_caches([:"node3@127.0.0.1"], [{Replicated, []}])

      assert :lists.usort(Replicated.nodes()) ==
               :lists.usort([:"node3@127.0.0.1" | cluster_nodes()])

      :ok = Process.sleep(3000)
      assert_for_all_replicas(Replicated, :get_all, [[:a, :b, :c]], %{a: 1, b: 2, c: 3})

      :ok = stop_caches(node_pid_list)
    end
  end

  describe "global lock" do
    test "concurrency" do
      with_dynamic_cache(
        Replicated,
        [name: :replicated_global_mock, primary: [adapter: Nebulex.TestCache.AdapterMock]],
        fn ->
          true = Process.register(self(), __MODULE__)
          _ = Process.flag(:trap_exit, true)

          task1 =
            Task.async(fn ->
              _ = Replicated.put_dynamic_cache(:replicated_global_mock)
              _ = Replicated.flush()
              send(__MODULE__, :flush)
            end)

          task2 =
            Task.async(fn ->
              :ok = Process.sleep(500)
              _ = Replicated.put_dynamic_cache(:replicated_global_mock)
              assert :ok == Replicated.put("foo", "bar")
              send(__MODULE__, :put)
            end)

          assert_receive :flush, 5000
          assert_receive :put, 5000

          [_, _] = Task.yield_many([task1, task2])
        end
      )
    end
  end

  # ## Helpers

  defp assert_for_all_replicas(cache, action, args, expected) do
    assert {res_lst, []} = :rpc.multicall(cache.nodes(cache), cache, action, args)
    Enum.each(res_lst, fn res -> assert res == expected end)
  end

  defp cluster_nodes do
    [node() | Node.list()] -- [:"node3@127.0.0.1"]
  end
end
