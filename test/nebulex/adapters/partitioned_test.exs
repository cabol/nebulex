defmodule Nebulex.Adapters.PartitionedTest do
  use Nebulex.NodeCase
  use Nebulex.CacheTest

  import Nebulex.CacheCase

  alias Nebulex.Adapter
  alias Nebulex.Cache.Cluster

  alias Nebulex.TestCache.{Partitioned, PartitionedMock}

  @primary :"primary@127.0.0.1"
  @cache_name :partitioned_cache

  # Set config
  :ok = Application.put_env(:nebulex, Partitioned, primary: [backend: :shards])

  setup do
    cluster = :lists.usort([@primary | Application.get_env(:nebulex, :nodes, [])])

    node_pid_list =
      start_caches(
        [node() | Node.list()],
        [
          {Partitioned, [name: @cache_name, stats: true]},
          {PartitionedMock, []}
        ]
      )

    default_dynamic_cache = Partitioned.get_dynamic_cache()
    _ = Partitioned.put_dynamic_cache(@cache_name)

    on_exit(fn ->
      _ = Partitioned.put_dynamic_cache(default_dynamic_cache)
      :ok = Process.sleep(100)
      stop_caches(node_pid_list)
    end)

    {:ok, cache: Partitioned, name: @cache_name, cluster: cluster}
  end

  describe "c:init/1" do
    test "initializes the primary store metadata" do
      Adapter.with_meta(PartitionedCache.Primary, fn adapter, meta ->
        assert adapter == Nebulex.Adapters.Local
        assert meta.backend == :shards
      end)
    end

    test "raises an exception because invalid primary store" do
      assert_raise ArgumentError, ~r"adapter Invalid was not compiled", fn ->
        defmodule Demo do
          use Nebulex.Cache,
            otp_app: :nebulex,
            adapter: Nebulex.Adapters.Partitioned,
            primary_storage_adapter: Invalid
        end
      end
    end

    test "fails because unloaded keyslot module" do
      assert {:error, {%ArgumentError{message: msg}, _}} =
               Partitioned.start_link(
                 name: :unloaded_keyslot,
                 keyslot: UnloadedKeyslot
               )

      assert Regex.match?(~r"keyslot UnloadedKeyslot was not compiled", msg)
    end

    test "fails because invalid keyslot module" do
      assert {:error, {%ArgumentError{message: msg}, _}} =
               Partitioned.start_link(
                 name: :invalid_keyslot,
                 keyslot: __MODULE__
               )

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
        def hash_slot(key, range) do
          key
          |> :erlang.phash2()
          |> rem(range)
        end
      end

      test_with_dynamic_cache(Partitioned, [name: :custom_keyslot, keyslot: Keyslot], fn ->
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

    test "incr raises when the counter is not an integer" do
      :ok = Partitioned.put(:counter, "string")

      assert_raise ArgumentError, fn ->
        Partitioned.incr(:counter, 10)
      end
    end
  end

  describe "cluster" do
    test "established", %{name: name, cluster: cluster} do
      assert node() == @primary
      assert :lists.usort(Node.list()) == cluster -- [node()]
      assert Partitioned.nodes() == cluster

      :ok = Cluster.leave(name)
      assert Partitioned.nodes() == cluster -- [node()]
    end

    test "teardown cache node", %{cluster: cluster} do
      assert Partitioned.put(4, 4) == :ok
      assert Partitioned.get(4) == 4

      assert Partitioned.nodes() == cluster

      node = teardown_cache(1)
      :ok = Process.sleep(1000)

      assert Partitioned.nodes() == cluster -- [node]

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

      msg = ~r"RPC error executing action: all\n\nErrors:"

      assert_raise Nebulex.RPCMultiCallError, msg, fn ->
        Partitioned.all(nil, timeout: 1)
      end
    end

    test "runtime error" do
      _ = Process.flag(:trap_exit, true)

      assert [1, 2] |> PartitionedMock.get_all(timeout: 10) |> map_size() == 0

      assert PartitionedMock.put_all(a: 1, b: 2) == :ok

      assert [1, 2] |> PartitionedMock.get_all() |> map_size() == 0

      assert_raise ArgumentError, fn ->
        PartitionedMock.get(1)
      end

      msg = ~r"RPC error executing action: count_all\n\nErrors:"

      assert_raise Nebulex.RPCMultiCallError, msg, fn ->
        PartitionedMock.count_all()
      end
    end
  end

  ## Private Functions

  defp teardown_cache(key) do
    node = Partitioned.get_node(key)
    remote_pid = :rpc.call(node, Process, :whereis, [@cache_name])
    :ok = :rpc.call(node, Supervisor, :stop, [remote_pid])
    node
  end
end
