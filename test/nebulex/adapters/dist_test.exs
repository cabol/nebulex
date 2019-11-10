defmodule Nebulex.Adapters.PartitionedTest do
  use Nebulex.NodeCase
  use Nebulex.CacheTest, cache: Nebulex.TestCache.Partitioned

  alias Nebulex.Adapters.Partitioned.Cluster

  alias Nebulex.TestCache.{
    LocalMock,
    Partitioned,
    PartitionedMock,
    PartitionedWithCustomHashSlot
  }

  alias Nebulex.TestCache.Partitioned.Primary, as: PartitionedPrimary
  alias Nebulex.TestCache.PartitionedWithCustomHashSlot.Primary, as: PrimaryWithCustomHashSlot

  @primary :"primary@127.0.0.1"
  @cluster :lists.usort([@primary | Application.get_env(:nebulex, :nodes, [])])

  setup do
    {:ok, local} = PartitionedPrimary.start_link()
    {:ok, partitioned} = Partitioned.start_link()
    node_pid_list = start_caches(Node.list(), [PartitionedPrimary, Partitioned])
    :ok

    on_exit(fn ->
      :ok = Process.sleep(100)
      if Process.alive?(local), do: PartitionedPrimary.stop(local)
      if Process.alive?(partitioned), do: Partitioned.stop(partitioned)
      stop_caches(node_pid_list)
    end)
  end

  test "fail on __before_compile__ because missing primary storage" do
    assert_raise ArgumentError, ~r"missing :primary configuration", fn ->
      defmodule WrongPartitioned do
        use Nebulex.Cache,
          otp_app: :nebulex,
          adapter: Nebulex.Adapters.Partitioned
      end
    end
  end

  test "check cluster nodes" do
    assert @primary == node()
    assert @cluster -- [node()] == :lists.usort(Node.list())
    assert @cluster == Partitioned.__nodes__()

    :ok = Cluster.leave(Partitioned)
    assert @cluster -- [node()] == Partitioned.__nodes__()
  end

  test "get_and_update" do
    assert {nil, 1} == Partitioned.get_and_update(1, &Partitioned.get_and_update_fun/1)
    assert {1, 2} == Partitioned.get_and_update(1, &Partitioned.get_and_update_fun/1)
    assert {2, 4} == Partitioned.get_and_update(1, &Partitioned.get_and_update_fun/1)

    {4, %Object{key: 1, value: 8, expire_at: _, version: _}} =
      Partitioned.get_and_update(1, &Partitioned.get_and_update_fun/1, return: :object)

    assert_raise ArgumentError, fn ->
      Partitioned.get_and_update(1, &Partitioned.get_and_update_bad_fun/1)
    end

    assert_raise Nebulex.VersionConflictError, fn ->
      1
      |> Partitioned.set(1, return: :key)
      |> Partitioned.get_and_update(&Partitioned.get_and_update_fun/1, version: -1)
    end
  end

  test "set_many rollback" do
    assert 4 == Partitioned.set(4, 4)
    assert 4 == Partitioned.get(4)

    :ok = teardown_cache(1)

    assert {:error, [1]} == Partitioned.set_many([{4, 44}, {2, 2}, {1, 1}])

    assert 44 == Partitioned.get(4)
    assert 2 == Partitioned.get(2)

    assert_raise ArgumentError, fn ->
      Partitioned.get(1)
    end
  end

  test "rpc timeout" do
    assert :ok == Partitioned.set_many(for(x <- 1..100_000, do: {x, x}), timeout: 60_000)
    assert 1 == Partitioned.get(1, timeout: 1000)

    msg = ~r"RPC error executing action: all\n\nErrors:\n\n\[\n  timeout:"

    assert_raise Nebulex.RPCMultiCallError, msg, fn ->
      Partitioned.all(nil, timeout: 1)
    end
  end

  test "rpc errors" do
    _ = Process.flag(:trap_exit, true)

    {:ok, pid1} = PartitionedMock.start_link()
    {:ok, pid2} = LocalMock.start_link()

    assert 0 == map_size(PartitionedMock.get_many([1, 2, 3], timeout: 10))

    {:error, err_keys} = PartitionedMock.set_many(a: 1, b: 2)
    assert [:a, :b] == :lists.usort(err_keys)

    assert_raise ArgumentError, fn ->
      PartitionedMock.get(1)
    end

    msg = ~r"RPC error executing action: size\n\nErrors:\n\n\[\n  {{:exit,"

    assert_raise Nebulex.RPCMultiCallError, msg, fn ->
      PartitionedMock.size()
    end

    :ok = Enum.each([pid1, pid2], &PartitionedMock.stop/1)
  end

  test "custom hash_slot" do
    {:ok, pid1} = PartitionedWithCustomHashSlot.start_link()
    {:ok, pid2} = PrimaryWithCustomHashSlot.start_link()

    refute PartitionedWithCustomHashSlot.get("foo")
    assert "bar" == PartitionedWithCustomHashSlot.set("foo", "bar")
    assert "bar" == PartitionedWithCustomHashSlot.get("foo")

    :ok = Enum.each([pid1, pid2], &PartitionedMock.stop/1)
  end

  ## Private Functions

  defp teardown_cache(key) do
    node = Partitioned.get_node(key)
    remote_pid = :rpc.call(node, Process, :whereis, [Partitioned.__primary__()])
    :ok = :rpc.call(node, Partitioned.__primary__(), :stop, [remote_pid])
  end
end
