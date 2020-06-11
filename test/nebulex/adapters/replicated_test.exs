defmodule Nebulex.Adapters.ReplicatedTest do
  use Nebulex.NodeCase
  use Nebulex.CacheTest, cache: Nebulex.TestCache.Replicated

  alias Nebulex.TestCache.{Replicated, ReplicatedMock}

  setup do
    node_pid_list = start_caches(cluster_nodes(), [Replicated])
    :ok

    on_exit(fn ->
      :ok = Process.sleep(100)
      stop_caches(node_pid_list)
    end)
  end

  test "fail on __before_compile__ because missing primary storage" do
    assert_raise ArgumentError, "expected primary: to be given as argument", fn ->
      defmodule WrongReplicated do
        use Nebulex.Cache,
          otp_app: :nebulex,
          adapter: Nebulex.Adapters.Replicated
      end
    end
  end

  test "replicated set" do
    assert Replicated.put(1, 1) == :ok
    assert Replicated.get(1) == 1

    assert_for_all_replicas(Replicated, :get, [1], 1)

    assert Replicated.put_all(a: 1, b: 2, c: 3) == :ok

    assert_for_all_replicas(Replicated, :get_all, [[:a, :b, :c]], %{a: 1, b: 2, c: 3})
  end

  test "replicated delete" do
    assert Replicated.put("foo", "bar") == :ok
    assert Replicated.get("foo") == "bar"

    assert_for_all_replicas(Replicated, :get, ["foo"], "bar")

    assert Replicated.delete("foo") == :ok
    refute Replicated.get("foo")

    assert_for_all_replicas(Replicated, :get, ["foo"], nil)
  end

  test "replicated take" do
    assert Replicated.put("foo", "bar") == :ok
    assert Replicated.get("foo") == "bar"

    assert_for_all_replicas(Replicated, :get, ["foo"], "bar")

    assert Replicated.take("foo") == "bar"
    refute Replicated.get("foo")

    assert_for_all_replicas(Replicated, :take, ["foo"], nil)
  end

  test "replicated incr" do
    assert Replicated.incr(:counter, 3) == 3
    assert Replicated.incr(:counter) == 4

    assert_for_all_replicas(Replicated, :get, [:counter], 4)
  end

  test "replicated flush" do
    assert Replicated.put_all(a: 1, b: 2, c: 3) == :ok

    assert_for_all_replicas(Replicated, :get_all, [[:a, :b, :c]], %{a: 1, b: 2, c: 3})

    assert Replicated.flush() == 3
    assert Replicated.size() == 0

    assert_for_all_replicas(Replicated, :get_all, [[:a, :b, :c]], %{})
  end

  test "rpc errors" do
    _ = Process.flag(:trap_exit, true)
    pids = start_mock()

    msg = ~r"RPC error executing action: put_all\n\nErrors:\n\n\[\n  {{:exit,"

    assert_raise Nebulex.RPCMultiCallError, msg, fn ->
      ReplicatedMock.put_all(a: 1, b: 2)
    end

    :ok = stop_mock(pids)
  end

  test "global lock" do
    true = Process.register(self(), __MODULE__)
    _ = Process.flag(:trap_exit, true)
    pids = start_mock()

    task1 =
      Task.async(fn ->
        _ = ReplicatedMock.flush()
        send(__MODULE__, :flush)
      end)

    task2 =
      Task.async(fn ->
        :ok = Process.sleep(500)
        assert :ok == ReplicatedMock.put("foo", "bar")
        send(__MODULE__, :put)
      end)

    assert_receive :flush, 5000
    assert_receive :put, 5000

    [_, _] = Task.yield_many([task1, task2])
    :ok = stop_mock(pids)
  end

  test "join new cache node" do
    assert Replicated.put_all(a: 1, b: 2, c: 3) == :ok
    assert :lists.usort(Replicated.__nodes__()) == :lists.usort(cluster_nodes())

    assert_for_all_replicas(Replicated, :get_all, [[:a, :b, :c]], %{a: 1, b: 2, c: 3})

    # join new cache node
    node_pid_list = start_caches([:"node3@127.0.0.1"], [Replicated])

    assert :lists.usort(Replicated.__nodes__()) ==
             :lists.usort([:"node3@127.0.0.1" | cluster_nodes()])

    :ok = Process.sleep(2000)
    assert_for_all_replicas(Replicated, :get_all, [[:a, :b, :c]], %{a: 1, b: 2, c: 3})

    :ok = stop_caches(node_pid_list)
  end

  ## Helpers

  defp assert_for_all_replicas(cache, action, args, expected) do
    assert {res_lst, []} = :rpc.multicall(cache.__nodes__, cache, action, args)
    Enum.each(res_lst, fn res -> assert res == expected end)
  end

  defp start_mock do
    {:ok, pid} = ReplicatedMock.start_link()
    pid
  end

  defp stop_mock(pid) do
    ReplicatedMock.stop(pid)
  end

  defp cluster_nodes do
    [node() | Node.list()] -- [:"node3@127.0.0.1"]
  end
end
