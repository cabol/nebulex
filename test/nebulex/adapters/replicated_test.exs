defmodule Nebulex.Adapters.ReplicatedTest do
  use Nebulex.NodeCase
  use Nebulex.CacheTest, cache: Nebulex.TestCache.Replicated

  alias Nebulex.TestCache.{Replicated, ReplicatedMock}
  alias Nebulex.TestCache.Replicated.Primary, as: ReplicatedPrimary
  alias Nebulex.TestCache.ReplicatedMock.Primary, as: ReplicatedMockPrimary

  setup do
    node_pid_list = start_caches(cluster_nodes(), [ReplicatedPrimary, Replicated])
    :ok

    on_exit(fn ->
      :ok = Process.sleep(100)
      stop_caches(node_pid_list)
    end)
  end

  test "fail on __before_compile__ because missing primary storage" do
    assert_raise ArgumentError, ~r"missing :primary configuration", fn ->
      defmodule WrongReplicated do
        use Nebulex.Cache,
          otp_app: :nebulex,
          adapter: Nebulex.Adapters.Replicated
      end
    end
  end

  test "replicated set" do
    assert 1 == Replicated.set(1, 1)
    assert 1 == Replicated.get(1)

    assert_for_all_replicas(Replicated, :get, [1], 1)

    assert :ok == Replicated.set_many(a: 1, b: 2, c: 3)

    assert_for_all_replicas(Replicated, :get_many, [[:a, :b, :c]], %{a: 1, b: 2, c: 3})
  end

  test "replicated delete" do
    assert "bar" == Replicated.set("foo", "bar")
    assert "bar" == Replicated.get("foo")

    assert_for_all_replicas(Replicated, :get, ["foo"], "bar")

    assert "foo" == Replicated.delete("foo")
    refute Replicated.get("foo")

    assert_for_all_replicas(Replicated, :get, ["foo"], nil)
  end

  test "replicated take" do
    assert "bar" == Replicated.set("foo", "bar")
    assert "bar" == Replicated.get("foo")

    assert_for_all_replicas(Replicated, :get, ["foo"], "bar")

    assert "bar" == Replicated.take("foo")
    refute Replicated.get("foo")

    assert_for_all_replicas(Replicated, :take, ["foo"], nil)
  end

  test "replicated update_counter" do
    assert 3 == Replicated.update_counter(:counter, 3)
    assert 4 == Replicated.update_counter(:counter)

    assert_for_all_replicas(Replicated, :get, [:counter], 4)
  end

  test "replicated flush" do
    assert :ok == Replicated.set_many(a: 1, b: 2, c: 3)

    assert_for_all_replicas(Replicated, :get_many, [[:a, :b, :c]], %{a: 1, b: 2, c: 3})

    assert :ok == Replicated.flush()
    assert 0 == Replicated.size()

    assert_for_all_replicas(Replicated, :get_many, [[:a, :b, :c]], %{})
  end

  test "rpc errors" do
    _ = Process.flag(:trap_exit, true)
    pids = start_mocks()

    msg = ~r"RPC error executing action: set_many\n\nErrors:\n\n\[\n  {{:exit,"

    assert_raise Nebulex.RPCMultiCallError, msg, fn ->
      ReplicatedMock.set_many(a: 1, b: 2)
    end

    :ok = stop_mocks(pids)
  end

  test "global lock" do
    true = Process.register(self(), __MODULE__)
    _ = Process.flag(:trap_exit, true)
    pids = start_mocks()

    task1 =
      Task.async(fn ->
        assert :ok == ReplicatedMock.flush()
        send(__MODULE__, :flush)
      end)

    task2 =
      Task.async(fn ->
        :ok = Process.sleep(500)
        assert "bar" == ReplicatedMock.set("foo", "bar")
        send(__MODULE__, :set)
      end)

    assert_receive :flush, 5000
    assert_receive :set, 5000

    [_, _] = Task.yield_many([task1, task2])
    :ok = stop_mocks(pids)
  end

  test "join new cache node" do
    assert :ok == Replicated.set_many(a: 1, b: 2, c: 3)
    assert :lists.usort(cluster_nodes()) == :lists.usort(Replicated.__nodes__())

    assert_for_all_replicas(Replicated, :get_many, [[:a, :b, :c]], %{a: 1, b: 2, c: 3})

    # join new cache node
    node_pid_list = start_caches([:"node3@127.0.0.1"], [ReplicatedPrimary, Replicated])

    assert :lists.usort([:"node3@127.0.0.1" | cluster_nodes()]) ==
             :lists.usort(Replicated.__nodes__())

    :ok = Process.sleep(2000)
    assert_for_all_replicas(Replicated, :get_many, [[:a, :b, :c]], %{a: 1, b: 2, c: 3})

    :ok = stop_caches(node_pid_list)
  end

  ## Helpers

  defp assert_for_all_replicas(cache, action, args, expected) do
    assert {res_lst, []} = :rpc.multicall(cache.__nodes__, cache, action, args)
    Enum.each(res_lst, fn res -> assert res == expected end)
  end

  defp start_mocks do
    for cache <- [ReplicatedMock, ReplicatedMockPrimary] do
      {:ok, pid} = cache.start_link()
      pid
    end
  end

  defp stop_mocks(pids) do
    Enum.each(pids, &ReplicatedMock.stop/1)
  end

  defp cluster_nodes do
    [node() | Node.list()] -- [:"node3@127.0.0.1"]
  end
end
