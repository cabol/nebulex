defmodule Nebulex.Adapters.PartitionedTest do
  use Nebulex.NodeCase
  use Nebulex.CacheTest

  import Nebulex.TestCase

  alias Nebulex.Adapter
  alias Nebulex.Cache.Cluster
  alias Nebulex.TestCache.Partitioned

  @primary :"primary@127.0.0.1"
  @cluster :lists.usort([@primary | Application.get_env(:nebulex, :nodes, [])])

  :ok = Application.put_env(:nebulex, Partitioned, primary: [adapter: Nebulex.Adapters.Local])

  setup do
    node_pid_list =
      start_caches([node() | Node.list()], [{Partitioned, [primary: [backend: :shards]]}])

    on_exit(fn ->
      :ok = Process.sleep(100)
      stop_caches(node_pid_list)
    end)

    {:ok, cache: Partitioned, name: Partitioned}
  end

  describe "c:init/1" do
    test "primary store backend" do
      Adapter.with_meta(Partitioned, fn _, meta ->
        assert meta.primary_meta.backend == :shards
      end)
    end

    test "fail because invalid primary adapter" do
      assert {:error, {%RuntimeError{message: msg}, _}} =
               Partitioned.start_link(
                 name: :invalid_primary_adapter,
                 primary: [adapter: __MODULE__]
               )

      mod = inspect(__MODULE__)
      assert Regex.match?(~r"expected #{mod} to implement the behaviour Nebulex.Adapter", msg)
    end

    test "fail because unloaded keyslot module" do
      assert {:error, {%RuntimeError{message: msg}, _}} =
               Partitioned.start_link(name: :unloaded_keyslot, keyslot: UnloadedKeyslot)

      assert Regex.match?(~r"keyslot UnloadedKeyslot was not compiled", msg)
    end

    test "fail because invalid keyslot module" do
      assert {:error, {%RuntimeError{message: msg}, _}} =
               Partitioned.start_link(name: :invalid_keyslot, keyslot: __MODULE__)

      mod = inspect(__MODULE__)
      behaviour = "Nebulex.Adapter.Keyslot"
      assert Regex.match?(~r"expected #{mod} to implement the behaviour #{behaviour}", msg)
    end
  end

  describe "partitioned cache" do
    test "custom keyslot" do
      defmodule Keyslot do
        @behaviour Nebulex.Adapter.Keyslot

        @impl true
        def compute(key, range) do
          key
          |> :erlang.phash2()
          |> rem(range)
        end
      end

      with_dynamic_cache(Partitioned, [name: :custom_keyslot, keyslot: Keyslot], fn ->
        refute Partitioned.get("foo")
        assert Partitioned.put("foo", "bar") == :ok
        assert Partitioned.get("foo") == "bar"
      end)
    end

    test "get_and_update" do
      assert Partitioned.get_and_update(1, &Partitioned.get_and_update_fun/1) == {nil, 1}
      assert Partitioned.get_and_update(1, &Partitioned.get_and_update_fun/1) == {1, 2}
      assert Partitioned.get_and_update(1, &Partitioned.get_and_update_fun/1) == {2, 4}

      assert_raise ArgumentError, fn ->
        Partitioned.get_and_update(1, &Partitioned.get_and_update_bad_fun/1)
      end
    end
  end

  describe "custer" do
    test "check cluster nodes" do
      assert node() == @primary
      assert :lists.usort(Node.list()) == @cluster -- [node()]
      assert Partitioned.nodes() == @cluster

      :ok = Cluster.leave(Partitioned)
      assert Partitioned.nodes() == @cluster -- [node()]
    end

    test "teardown cache" do
      assert Partitioned.put(4, 4) == :ok
      assert Partitioned.get(4) == 4

      assert Partitioned.nodes() == @cluster

      node = teardown_cache(1)
      :ok = Process.sleep(1000)

      assert Partitioned.nodes() == @cluster -- [node]

      assert :ok == Partitioned.put_all([{4, 44}, {2, 2}, {1, 1}])

      assert Partitioned.get(4) == 44
      assert Partitioned.get(2) == 2
      assert Partitioned.get(1) == 1
    end
  end

  describe "rpc" do
    test "timeout error" do
      assert Partitioned.put_all(for(x <- 1..100_000, do: {x, x}), timeout: 60_000) == :ok
      assert Partitioned.get(1, timeout: 1000) == 1

      msg = ~r"RPC error executing action: all\n\nErrors:\n\n\[\n  timeout:"

      assert_raise Nebulex.RPCMultiCallError, msg, fn ->
        Partitioned.all(nil, timeout: 1)
      end
    end

    test "runtime error" do
      with_dynamic_cache(
        Partitioned,
        [name: :partitioned_mock, primary: [adapter: Nebulex.TestCache.AdapterMock]],
        fn ->
          _ = Process.flag(:trap_exit, true)

          assert [1, 2] |> Partitioned.get_all(timeout: 10) |> map_size() == 0

          assert Partitioned.put_all(a: 1, b: 2) == :ok

          assert [1, 2] |> Partitioned.get_all() |> map_size() == 0

          assert_raise ArgumentError, fn ->
            Partitioned.get(1)
          end

          msg = ~r"RPC error executing action: size\n\nErrors:\n\n\[\n  {{:exit,"

          assert_raise Nebulex.RPCMultiCallError, msg, fn ->
            Partitioned.size()
          end
        end
      )
    end
  end

  ## Private Functions

  defp teardown_cache(key) do
    node = Partitioned.get_node(key)
    remote_pid = :rpc.call(node, Process, :whereis, [Partitioned])
    :ok = :rpc.call(node, Supervisor, :stop, [remote_pid])
    node
  end
end
