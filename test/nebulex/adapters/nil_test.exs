defmodule Nebulex.Adapters.NilTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  defmodule NilCache do
    use Nebulex.Cache,
      otp_app: :nebulex,
      adapter: Nebulex.Adapters.Nil
  end

  alias __MODULE__.NilCache

  setup [:setup_cache]

  describe "kv" do
    property "put", %{cache: cache} do
      check all term <- term() do
        assert cache.has_key?(term) == {:ok, false}

        assert cache.replace(term, term) == {:ok, true}
        assert cache.put(term, term) == :ok
        assert cache.put_new(term, term) == {:ok, true}
        assert cache.has_key?(term) == {:ok, false}
      end
    end

    test "put_all", %{cache: cache} do
      assert cache.put_all(a: 1, b: 2, c: 3) == :ok
      assert cache.has_key?(:a) == {:ok, false}
      assert cache.has_key?(:b) == {:ok, false}
      assert cache.has_key?(:c) == {:ok, false}
    end

    test "fetch", %{cache: cache} do
      assert {:error, %Nebulex.KeyError{key: "foo"}} = cache.fetch("foo")
    end

    test "delete", %{cache: cache} do
      assert cache.delete("foo") == :ok
    end

    test "take", %{cache: cache} do
      assert {:error, %Nebulex.KeyError{key: "foo"}} = cache.take("foo")
    end

    test "has_key?", %{cache: cache} do
      assert cache.has_key?("foo") == {:ok, false}
    end

    test "ttl", %{cache: cache} do
      assert {:error, %Nebulex.KeyError{key: "foo"}} = cache.ttl("foo")
    end

    test "expire", %{cache: cache} do
      assert cache.expire("foo", 1000) == {:ok, false}
    end

    test "touch", %{cache: cache} do
      assert cache.touch("foo") == {:ok, false}
    end

    test "incr", %{cache: cache} do
      assert cache.incr!(:counter) == 1
      assert cache.incr!(:counter, 10) == 10
      assert cache.incr!(:counter, -10) == -10
      assert cache.incr!(:counter, 5, default: 10) == 15
      assert cache.incr!(:counter, -5, default: 10) == 5
    end

    test "decr", %{cache: cache} do
      assert cache.decr!(:counter) == -1
      assert cache.decr!(:counter, 10) == -10
      assert cache.decr!(:counter, -10) == 10
      assert cache.decr!(:counter, 5, default: 10) == 5
      assert cache.decr!(:counter, -5, default: 10) == 15
    end
  end

  describe "queryable" do
    test "get_all", %{cache: cache} do
      assert cache.put("foo", "bar") == :ok
      assert cache.get_all!() == []
    end

    test "stream", %{cache: cache} do
      assert cache.put("foo", "bar") == :ok
      assert cache.stream!() |> Enum.to_list() == []
    end

    test "count_all", %{cache: cache} do
      assert cache.put("foo", "bar") == :ok
      assert cache.count_all!() == 0
    end

    test "delete_all", %{cache: cache} do
      assert cache.put("foo", "bar") == :ok
      assert cache.delete_all!() == 0
    end
  end

  describe "transaction" do
    test "single transaction", %{cache: cache} do
      assert cache.transaction(fn ->
               :ok = cache.put("foo", "bar")
               cache.get!("foo")
             end) == {:ok, nil}
    end

    test "in_transaction?", %{cache: cache} do
      assert cache.in_transaction?() == {:ok, false}

      cache.transaction(fn ->
        :ok = cache.put(1, 11)

        assert cache.in_transaction?() == {:ok, true}
      end)
    end
  end

  describe "info" do
    test "ok: returns stats info", %{cache: cache} do
      assert cache.put("foo", "bar") == :ok
      refute cache.get!("foo")

      assert cache.info!(:stats) == %{
               deletions: 0,
               evictions: 0,
               expirations: 0,
               hits: 0,
               misses: 0,
               updates: 0,
               writes: 0
             }
    end
  end

  describe "pre/post hooks" do
    test "are given as options", %{cache: cache} do
      assert cache.fetch("foo",
               timeout: 1000,
               before: fn -> :noop end,
               after_return: fn _ -> {:ok, :noop} end
             ) == {:ok, :noop}
    end
  end

  ## Private Functions

  defp setup_cache(_config) do
    {:ok, _pid} = NilCache.start_link(telemetry: false)

    on_exit(fn -> safe_stop() end)

    {:ok, cache: NilCache}
  end

  defp safe_stop do
    NilCache.stop()
  catch
    # Perhaps the `pid` has terminated already (race-condition),
    # so we don't want to crash the test
    :exit, _ -> :ok
  end
end
