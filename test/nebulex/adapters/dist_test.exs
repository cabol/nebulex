defmodule Nebulex.Adapters.DistTest do
  use Nebulex.NodeCase
  use Nebulex.CacheTest, cache: Nebulex.TestCache.Dist

  alias Nebulex.Adapters.Dist.Cluster
  alias Nebulex.TestCache.{Dist, DistLocal, DistMock, DistWithCustomHashSlot, LocalMock}
  alias Nebulex.TestCache.DistWithCustomHashSlot.Local, as: DistLocalWithCustomHashSlot

  @primary :"primary@127.0.0.1"
  @cluster :lists.usort([@primary | Application.get_env(:nebulex, :nodes, [])])

  setup do
    {:ok, local} = DistLocal.start_link()
    {:ok, dist} = Dist.start_link()
    node_pid_list = start_caches(Node.list(), [DistLocal, Dist])
    :ok

    on_exit(fn ->
      _ = :timer.sleep(100)
      if Process.alive?(local), do: DistLocal.stop(local)
      if Process.alive?(dist), do: Dist.stop(dist)
      stop_caches(node_pid_list)
    end)
  end

  test "fail on __before_compile__ because missing local cache" do
    assert_raise ArgumentError, ~r"missing :local configuration", fn ->
      defmodule WrongDist do
        use Nebulex.Cache,
          otp_app: :nebulex,
          adapter: Nebulex.Adapters.Dist
      end
    end
  end

  test "check cluster nodes" do
    assert @primary == node()
    assert @cluster -- [node()] == :lists.usort(Node.list())
    assert @cluster == Dist.__nodes__()

    :ok = Cluster.leave(Dist)
    assert @cluster -- [node()] == Dist.__nodes__()
  end

  test "get_and_update" do
    assert {nil, 1} == Dist.get_and_update(1, &Dist.get_and_update_fun/1)
    assert {1, 2} == Dist.get_and_update(1, &Dist.get_and_update_fun/1)
    assert {2, 4} == Dist.get_and_update(1, &Dist.get_and_update_fun/1)

    {4, %Object{key: 1, value: 8, expire_at: _, version: _}} =
      Dist.get_and_update(1, &Dist.get_and_update_fun/1, return: :object)

    assert_raise ArgumentError, fn ->
      Dist.get_and_update(1, &Dist.get_and_update_bad_fun/1)
    end

    assert_raise Nebulex.VersionConflictError, fn ->
      1
      |> Dist.set(1, return: :key)
      |> Dist.get_and_update(&Dist.get_and_update_fun/1, version: -1)
    end
  end

  test "set_many rollback" do
    assert 4 == Dist.set(4, 4)
    assert 4 == Dist.get(4)

    :ok = teardown_cache(1)

    assert {:error, [1]} == Dist.set_many([{4, 44}, {2, 2}, {1, 1}])

    assert 44 == Dist.get(4)
    assert 2 == Dist.get(2)

    assert_raise ArgumentError, fn ->
      Dist.get(1)
    end
  end

  test "rpc timeout" do
    assert :ok == Dist.set_many(for(x <- 1..100_000, do: {x, x}), timeout: 60_000)
    assert 1 == Dist.get(1, timeout: 1000)

    msg = ~r"RPC error executing action: all\n\nErrors:\n\n\[\n  timeout:"

    assert_raise Nebulex.RPCMultiCallError, msg, fn ->
      Dist.all(nil, timeout: 1)
    end
  end

  test "rpc errors" do
    _ = Process.flag(:trap_exit, true)

    {:ok, pid1} = DistMock.start_link()
    {:ok, pid2} = LocalMock.start_link()

    assert 0 == map_size(DistMock.get_many([1, 2, 3], timeout: 10))

    {:error, err_keys} = DistMock.set_many(a: 1, b: 2)
    assert [:a, :b] == :lists.usort(err_keys)

    assert_raise ArgumentError, fn ->
      DistMock.get(1)
    end

    msg = ~r"RPC error executing action: size\n\nErrors:\n\n\[\n  {{:exit,"

    assert_raise Nebulex.RPCMultiCallError, msg, fn ->
      DistMock.size()
    end

    :ok = Enum.each([pid1, pid2], &DistMock.stop/1)
  end

  test "custom hash_slot" do
    {:ok, pid1} = DistWithCustomHashSlot.start_link()
    {:ok, pid2} = DistLocalWithCustomHashSlot.start_link()

    refute DistWithCustomHashSlot.get("foo")
    assert "bar" == DistWithCustomHashSlot.set("foo", "bar")
    assert "bar" == DistWithCustomHashSlot.get("foo")

    :ok = Enum.each([pid1, pid2], &DistMock.stop/1)
  end

  ## Private Functions

  defp teardown_cache(key) do
    node = Dist.get_node(key)
    remote_pid = :rpc.call(node, Process, :whereis, [Dist.__local__()])
    :ok = :rpc.call(node, Dist.__local__(), :stop, [remote_pid])
  end
end
