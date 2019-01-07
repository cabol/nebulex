defmodule Nebulex.CachingTest do
  use ExUnit.Case, async: true

  defmodule Cache do
    use Nebulex.Cache,
      otp_app: :nebulex,
      adapter: Nebulex.Adapters.Local
  end

  defmodule Meta do
    defstruct [:id, :count]
  end

  import Nebulex.Caching
  alias Nebulex.CachingTest.{Cache, Meta}

  setup do
    {:ok, pid} = Cache.start_link(n_generations: 2)
    :ok

    on_exit(fn ->
      _ = :timer.sleep(10)
      if Process.alive?(pid), do: Cache.stop(pid)
    end)
  end

  test "fail on cacheable because missing cache" do
    assert_raise ArgumentError, "expected cache: to be given as argument", fn ->
      defmodule Test do
        import Nebulex.Caching

        defcacheable t(a, b) do
          {a, b}
        end
      end
    end
  end

  test "fail on cacheable because invalid syntax" do
    assert_raise ArgumentError, "invalid syntax in defcacheable t.t(a)", fn ->
      defmodule Test do
        import Nebulex.Caching

        defcacheable t.t(a), cache: Cache do
          a
        end
      end
    end
  end

  test "cacheable" do
    refute Cache.get("x")
    assert {"x", "y"} == get_by_x("x")
    assert {"x", "y"} == Cache.get("x")

    refute Cache.get({"x", "y"})
    assert {"x", "y"} == get_by_xy("x", "y")
    assert {"x", "y"} == Cache.get({"x", "y"})
  end

  test "cacheable with default key" do
    key = :erlang.phash2({:get_with_default_key, [123, {:foo, "bar"}]})

    refute Cache.get(key)
    assert {123, {:foo, "bar"}} == get_with_default_key(123, {:foo, "bar"})
    assert {123, {:foo, "bar"}} == Cache.get(key)
  end

  test "defining keys using structs and maps" do
    refute Cache.get("x")
    assert %Meta{id: 1, count: 1} == get_meta(%Meta{id: 1, count: 1})
    assert %Meta{id: 1, count: 1} == Cache.get({Meta, 1})

    refute Cache.get("y")
    assert %{id: 1} == get_map(%{id: 1})
    assert %{id: 1} == Cache.get(1)
  end

  test "evict" do
    Cache.set_many(x: 1, y: 2, z: 3)
    assert 1 == Cache.get(:x)
    assert 2 == Cache.get(:y)
    assert 3 == Cache.get(:z)

    assert :ok == cache_evict(:x)
    assert :ok == cache_evict(:y)
    refute Cache.get(:x)
    refute Cache.get(:y)
    assert 3 == Cache.get(:z)
  end

  test "evict all entries" do
    Cache.set_many(x: 1, y: 2, z: 3)
    assert 1 == Cache.get(:x)
    assert 2 == Cache.get(:y)
    assert 3 == Cache.get(:z)

    assert :ok == cache_evict_all("hello")
    refute Cache.get(:x)
    refute Cache.get(:y)
    refute Cache.get(:z)
  end

  test "updatable" do
    Cache.set_many(x: 1, y: 2, z: 3)
    assert 1 == Cache.get(:x)
    assert 2 == Cache.get(:y)
    assert 3 == Cache.get(:z)

    assert :ok == cache_put(:x)
    assert :ok == cache_put(:y)
    assert :ok == Cache.get(:x)
    assert :ok == Cache.get(:y)
    assert 3 == Cache.get(:z)
  end

  ## Caching Functions

  defcacheable get_by_x(x, y \\ "y"), cache: Cache, key: x do
    {x, y}
  end

  defcacheable get_by_xy(x, y), cache: Cache, key: {x, y} do
    {x, y}
  end

  defcacheable get_with_default_key(x, y), cache: Cache do
    {x, y}
  end

  defcacheable get_meta(%Meta{} = meta), cache: Cache, key: {Meta, meta.id} do
    meta
  end

  defcacheable get_map(map), cache: Cache, key: map[:id] do
    map
  end

  defevict cache_evict(x), cache: Cache, key: x do
    :ok
  end

  defevict cache_evict_all(x), cache: Cache, all_entries: true do
    :ok
  end

  defupdatable cache_put(x), cache: Cache, key: x do
    :ok
  end
end
