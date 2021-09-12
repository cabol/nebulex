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

  describe "entry" do
    property "put", %{cache: cache} do
      check all term <- term() do
        assert cache.exists?(term) == {:ok, false}

        assert cache.replace(term, term) == {:ok, true}
        assert cache.put(term, term) == :ok
        assert cache.put_new(term, term) == {:ok, true}
        assert cache.exists?(term) == {:ok, false}
      end
    end

    test "put_all", %{cache: cache} do
      assert cache.put_all(a: 1, b: 2, c: 3) == :ok
      assert cache.exists?(:a) == {:ok, false}
      assert cache.exists?(:b) == {:ok, false}
      assert cache.exists?(:c) == {:ok, false}
    end

    test "fetch", %{cache: cache} do
      assert {:error, %Nebulex.KeyError{key: "foo"}} = cache.fetch("foo")
    end

    test "get_all", %{cache: cache} do
      assert cache.get_all("foo") == {:ok, %{}}
    end

    test "delete", %{cache: cache} do
      assert cache.delete("foo") == :ok
    end

    test "take", %{cache: cache} do
      assert {:error, %Nebulex.KeyError{key: "foo"}} = cache.take("foo")
    end

    test "exists?", %{cache: cache} do
      assert cache.exists?("foo") == {:ok, false}
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
    test "all", %{cache: cache} do
      assert cache.put("foo", "bar") == :ok
      assert cache.all!() == []
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
        :ok = cache.put(1, 11, return: :key)
        {:ok, true} = cache.in_transaction?()
      end)
    end
  end

  describe "persistence" do
    test "dump and load", %{cache: cache} do
      tmp = System.tmp_dir!()
      path = "#{tmp}/#{cache}"

      :ok = cache.put("foo", "bar")

      assert cache.dump(path) == :ok
      assert cache.load(path) == :ok
      assert cache.count_all!() == 0
    end
  end

  describe "stats" do
    test "stats/0", %{cache: cache} do
      assert cache.put("foo", "bar") == :ok
      refute cache.get!("foo")
      assert cache.stats() == %Nebulex.Stats{}
    end
  end

  ## Private Functions

  defp setup_cache(_config) do
    {:ok, pid} = NilCache.start_link()

    on_exit(fn ->
      :ok = Process.sleep(100)
      if Process.alive?(pid), do: NilCache.stop()
    end)

    {:ok, cache: NilCache}
  end
end
