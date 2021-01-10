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
        refute cache.get(term)

        assert cache.replace(term, term)
        assert cache.put(term, term) == :ok
        assert cache.put_new(term, term)
        refute cache.get(term)
      end
    end

    test "put_all", %{cache: cache} do
      assert cache.put_all(a: 1, b: 2, c: 3) == :ok
      refute cache.get(:a)
      refute cache.get(:b)
      refute cache.get(:c)
    end

    test "get", %{cache: cache} do
      assert cache.put("foo", "bar") == :ok
      refute cache.get("foo")
    end

    test "get_all", %{cache: cache} do
      assert cache.put("foo", "bar") == :ok
      assert cache.get_all("foo") == %{}
    end

    test "delete", %{cache: cache} do
      assert cache.put("foo", "bar") == :ok
      assert cache.delete("foo") == :ok
    end

    test "take", %{cache: cache} do
      assert cache.put("foo", "bar") == :ok
      refute cache.take("foo")
    end

    test "has_key?", %{cache: cache} do
      assert cache.put("foo", "bar") == :ok
      refute cache.has_key?("foo")
    end

    test "ttl", %{cache: cache} do
      assert cache.put("foo", "bar") == :ok
      refute cache.ttl("foo")
    end

    test "expire", %{cache: cache} do
      assert cache.put("foo", "bar") == :ok
      assert cache.expire("foo", 1000)
      refute cache.get("foo")
    end

    test "touch", %{cache: cache} do
      assert cache.put("foo", "bar") == :ok
      assert cache.touch("foo")
      refute cache.get("foo")
    end

    test "incr", %{cache: cache} do
      assert cache.incr(:counter) == 1
      assert cache.incr(:counter, 10) == 1
      assert cache.incr(:counter, -10) == 1
    end
  end

  describe "storage" do
    test "size", %{cache: cache} do
      assert cache.put("foo", "bar") == :ok
      assert cache.size() == 0
    end

    test "flush", %{cache: cache} do
      assert cache.put("foo", "bar") == :ok
      assert cache.flush() == 0
    end
  end

  describe "queryable" do
    test "all", %{cache: cache} do
      assert cache.put("foo", "bar") == :ok
      assert cache.all() == []
    end

    test "stream", %{cache: cache} do
      assert cache.put("foo", "bar") == :ok
      assert cache.stream() |> Enum.to_list() == []
    end
  end

  describe "transaction" do
    test "single transaction", %{cache: cache} do
      refute cache.transaction(fn ->
               :ok = cache.put("foo", "bar")
               cache.get("foo")
             end)
    end

    test "in_transaction?", %{cache: cache} do
      refute cache.in_transaction?()

      cache.transaction(fn ->
        :ok = cache.put(1, 11, return: :key)
        true = cache.in_transaction?()
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
      assert cache.size() == 0
    end
  end

  describe "stats" do
    test "stats/0", %{cache: cache} do
      assert cache.put("foo", "bar") == :ok
      refute cache.get("foo")
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
