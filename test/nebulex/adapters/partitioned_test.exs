defmodule Nebulex.Adapters.PartitionedTest do
  use Nebulex.NodeCase
  use Nebulex.CacheTest, cache: Nebulex.TestCache.Partitioned

  alias Nebulex.Cache.Cluster

  alias Nebulex.TestCache.{
    Partitioned,
    PartitionedMock,
    PartitionedWithCustomHashSlot
  }

  @primary :"primary@127.0.0.1"
  @cluster :lists.usort([@primary | Application.get_env(:nebulex, :nodes, [])])

  setup do
    node_pid_list = start_caches([node() | Node.list()], [Partitioned])
    :ok

    on_exit(fn ->
      :ok = Process.sleep(100)
      stop_caches(node_pid_list)
    end)
  end

  test "fail on __before_compile__ because missing primary storage" do
    assert_raise ArgumentError, "expected primary: to be given as argument", fn ->
      defmodule WrongPartitioned do
        use Nebulex.Cache,
          otp_app: :nebulex,
          adapter: Nebulex.Adapters.Partitioned
      end
    end
  end

  test "fail on __before_compile__ because invalid hash_slot" do
    mod = "Nebulex.Adapters.PartitionedTest"

    assert_raise ArgumentError, ~r"hash_slot #{mod}.WrongPartitioned was not compiled", fn ->
      defmodule WrongPartitioned do
        use Nebulex.Cache,
          otp_app: :nebulex,
          adapter: Nebulex.Adapters.Partitioned,
          primary: Primary,
          hash_slot: __MODULE__
      end
    end

    msg = "expected #{mod}.WrongHashSlot to implement the behaviour Nebulex.Adapter.HashSlot"

    assert_raise ArgumentError, msg, fn ->
      defmodule WrongHashSlot do
      end

      defmodule WrongPartitioned do
        use Nebulex.Cache,
          otp_app: :nebulex,
          adapter: Nebulex.Adapters.Partitioned,
          primary: Primary,
          hash_slot: WrongHashSlot
      end
    end
  end

  test "__before_compile__ with hash_slot" do
    defmodule MyyHashSlot do
      @behaviour Nebulex.Adapter.HashSlot

      def keyslot(_key, _range), do: 0
    end

    defmodule MyPartitioned do
      use Nebulex.Cache,
        otp_app: :nebulex,
        adapter: Nebulex.Adapters.Partitioned,
        primary: Primary,
        hash_slot: MyyHashSlot
    end
  end

  test "check cluster nodes" do
    assert node() == @primary
    assert :lists.usort(Node.list()) == @cluster -- [node()]
    assert Partitioned.__nodes__() == @cluster

    :ok = Cluster.leave(Partitioned)
    assert Partitioned.__nodes__() == @cluster -- [node()]
  end

  test "get_and_update" do
    assert Partitioned.get_and_update(1, &Partitioned.get_and_update_fun/1) == {nil, 1}
    assert Partitioned.get_and_update(1, &Partitioned.get_and_update_fun/1) == {1, 2}
    assert Partitioned.get_and_update(1, &Partitioned.get_and_update_fun/1) == {2, 4}

    assert_raise ArgumentError, fn ->
      Partitioned.get_and_update(1, &Partitioned.get_and_update_bad_fun/1)
    end
  end

  test "teardown cache" do
    assert Partitioned.put(4, 4) == :ok
    assert Partitioned.get(4) == 4

    assert Partitioned.__nodes__() == @cluster

    node = teardown_cache(1)
    :ok = Process.sleep(1000)

    assert Partitioned.__nodes__() == @cluster -- [node]

    assert :ok == Partitioned.put_all([{4, 44}, {2, 2}, {1, 1}])

    assert Partitioned.get(4) == 44
    assert Partitioned.get(2) == 2
    assert Partitioned.get(1) == 1
  end

  test "rpc timeout" do
    assert Partitioned.put_all(for(x <- 1..100_000, do: {x, x}), timeout: 60_000) == :ok
    assert Partitioned.get(1, timeout: 1000) == 1

    msg = ~r"RPC error executing action: all\n\nErrors:\n\n\[\n  timeout:"

    assert_raise Nebulex.RPCMultiCallError, msg, fn ->
      Partitioned.all(nil, timeout: 1)
    end
  end

  test "rpc errors" do
    _ = Process.flag(:trap_exit, true)
    {:ok, pid} = PartitionedMock.start_link()

    assert [1, 2] |> PartitionedMock.get_all(timeout: 10) |> map_size() == 0

    assert PartitionedMock.put_all(a: 1, b: 2) == :ok

    assert [1, 2] |> PartitionedMock.get_all() |> map_size() == 0

    assert_raise ArgumentError, fn ->
      PartitionedMock.get(1)
    end

    msg = ~r"RPC error executing action: size\n\nErrors:\n\n\[\n  {{:exit,"

    assert_raise Nebulex.RPCMultiCallError, msg, fn ->
      PartitionedMock.size()
    end

    :ok = PartitionedMock.stop(pid)
  end

  test "custom hash_slot" do
    {:ok, pid} = PartitionedWithCustomHashSlot.start_link()

    refute PartitionedWithCustomHashSlot.get("foo")
    assert PartitionedWithCustomHashSlot.put("foo", "bar") == :ok
    assert PartitionedWithCustomHashSlot.get("foo") == "bar"

    :ok = PartitionedWithCustomHashSlot.stop(pid)
  end

  ## Private Functions

  defp teardown_cache(key) do
    node = Partitioned.get_node(key)
    remote_pid = :rpc.call(node, Process, :whereis, [Partitioned])
    :ok = :rpc.call(node, Partitioned, :stop, [remote_pid])
    node
  end
end
