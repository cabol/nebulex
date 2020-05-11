defmodule Nebulex.CachingTest do
  use ExUnit.Case, async: true
  use Nebulex.Caching

  defmodule Cache do
    use Nebulex.Cache,
      otp_app: :nebulex,
      adapter: Nebulex.Adapters.Local
  end

  defmodule Meta do
    defstruct [:id, :count]
  end

  alias Nebulex.CachingTest.{Cache, Meta}

  setup do
    {:ok, pid} = Cache.start_link(generations: 2)
    :ok

    on_exit(fn ->
      :ok = Process.sleep(10)
      if Process.alive?(pid), do: Cache.stop(pid)
    end)
  end

  describe "compile-time errors" do
    test "fail on cacheable because missing cache" do
      assert_raise ArgumentError, "expected cache: to be given as argument", fn ->
        defmodule Test do
          use Nebulex.Caching

          @decorate cacheable(a: 1)
          def t(a, b) do
            {a, b}
          end
        end
      end
    end
  end

  describe "cacheable" do
    test "with default opts" do
      refute Cache.get("x")
      assert {"x", "y"} == get_by_x("x")
      assert {"x", "y"} == Cache.get("x")
      refute get_by_x("nil")
      refute Cache.get("nil")

      refute Cache.get({"x", "y"})
      assert {"x", "y"} == get_by_xy("x", "y")
      assert {"x", "y"} == Cache.get({"x", "y"})

      :ok = Process.sleep(1100)
      assert {"x", "y"} == Cache.get("x")
      assert {"x", "y"} == Cache.get({"x", "y"})
    end

    test "with opts" do
      refute Cache.get("x")
      assert 1 == get_with_opts(1)
      assert 1 == Cache.get(1)

      :ok = Process.sleep(1100)
      refute Cache.get(1)
    end

    test "with match function" do
      refute Cache.get(:x)
      assert :x == get_with_match(:x)
      refute Cache.get(:x)

      refute Cache.get(:y)
      assert :y == get_with_match(:y)
      assert Cache.get(:y)

      refute Cache.get("true")
      assert {:ok, "true"} == get_with_match_fun("true")
      assert {:ok, "true"} == Cache.get("true")

      refute Cache.get(1)
      assert {:ok, "1"} == get_with_match_fun(1)
      assert "1" == Cache.get(1)

      refute Cache.get({:ok, "hello"})
      assert :error == get_with_match_fun({:ok, "hello"})
      refute Cache.get({:ok, "hello"})
    end

    test "with default key" do
      key = :erlang.phash2({__MODULE__, :get_with_default_key})

      refute Cache.get(key)
      assert :ok == get_with_default_key(123, {:foo, "bar"})
      assert :ok == Cache.get(key)
      assert :ok == get_with_default_key(:foo, "bar")
      assert :ok == Cache.get(key)
    end

    test "defining keys using structs and maps" do
      refute Cache.get("x")
      assert %Meta{id: 1, count: 1} == get_meta(%Meta{id: 1, count: 1})
      assert %Meta{id: 1, count: 1} == Cache.get({Meta, 1})

      refute Cache.get("y")
      assert %{id: 1} == get_map(%{id: 1})
      assert %{id: 1} == Cache.get(1)
    end
  end

  describe "cache_put" do
    test "with default opts" do
      assert :ok == set_keys(x: 1, y: 2, z: 3)
      assert :x == update_fun(:x)
      assert :y == update_fun(:y)
      assert :x == Cache.get(:x)
      assert :y == Cache.get(:y)
      assert 3 == Cache.get(:z)

      :ok = Process.sleep(1100)
      assert :x == Cache.get(:x)
      assert :y == Cache.get(:y)
      assert 3 == Cache.get(:z)
    end

    test "with opts" do
      assert :ok == set_keys(x: 1, y: 2, z: 3)
      assert :x == update_with_opts(:x)
      assert :y == update_with_opts(:y)

      :ok = Process.sleep(1100)
      refute Cache.get(:x)
      refute Cache.get(:y)
    end

    test "with match function" do
      assert {:ok, "x"} == update_with_match(:x)
      assert {:ok, "true"} == update_with_match(true)
      assert :error == update_with_match({:z, 1})
      assert "x" == Cache.get(:x)
      assert {:ok, "true"} == Cache.get(true)
      refute Cache.get({:z, 1})
    end
  end

  describe "cache_evict" do
    test "with single key" do
      assert :ok == set_keys(x: 1, y: 2, z: 3)

      assert :x == evict_fun(:x)
      refute Cache.get(:x)
      assert 2 == Cache.get(:y)
      assert 3 == Cache.get(:z)

      assert :y == evict_fun(:y)
      refute Cache.get(:x)
      refute Cache.get(:y)
      assert 3 == Cache.get(:z)
    end

    test "with multiple keys" do
      assert :ok == set_keys(x: 1, y: 2, z: 3)
      assert {:x, :y} == evict_keys_fun(:x, :y)
      refute Cache.get(:x)
      refute Cache.get(:y)
      assert 3 == Cache.get(:z)
    end

    test "all entries" do
      assert :ok == set_keys(x: 1, y: 2, z: 3)
      assert "hello" == evict_all_fun("hello")
      refute Cache.get(:x)
      refute Cache.get(:y)
      refute Cache.get(:z)
    end
  end

  ## Caching Functions

  @decorate cacheable(cache: Cache, key: x)
  def get_by_x(x, y \\ "y") do
    case x do
      "nil" -> nil
      _ -> {x, y}
    end
  end

  @decorate cacheable(cache: Cache, key: x, opts: [ttl: 1000])
  def get_with_opts(x) do
    x
  end

  @decorate cacheable(cache: Cache, key: x, match: fn x -> x != :x end)
  def get_with_match(x) do
    x
  end

  @decorate cacheable(cache: Cache, key: x, match: &match_fun/1)
  def get_with_match_fun(x) do
    {:ok, to_string(x)}
  rescue
    _ -> :error
  end

  @decorate cacheable(cache: Cache, key: {x, y})
  def get_by_xy(x, y) do
    {x, y}
  end

  @decorate cacheable(cache: Cache)
  def get_with_default_key(x, y) do
    _ = {x, y}
    :ok
  end

  @decorate cacheable(cache: Cache, key: {Meta, meta.id})
  def get_meta(%Meta{} = meta) do
    meta
  end

  @decorate cacheable(cache: Cache, key: map[:id])
  def get_map(map) do
    map
  end

  @decorate cache_evict(cache: Cache, key: x)
  def evict_fun(x) do
    x
  end

  @decorate cache_evict(cache: Cache, keys: [x, y])
  def evict_keys_fun(x, y) do
    {x, y}
  end

  @decorate cache_evict(cache: Cache, all_entries: true)
  def evict_all_fun(x) do
    x
  end

  @decorate cache_put(cache: Cache, key: x)
  def update_fun(x) do
    x
  end

  @decorate cache_put(cache: Cache, key: x, opts: [ttl: 1000])
  def update_with_opts(x) do
    x
  end

  @decorate cache_put(cache: Cache, key: x, match: &match_fun/1)
  def update_with_match(x) do
    {:ok, to_string(x)}
  rescue
    _ -> :error
  end

  ## Private Functions

  defp match_fun({:ok, "true"}), do: true
  defp match_fun({:ok, val}), do: {true, val}
  defp match_fun(_), do: false

  defp set_keys(entries) do
    assert :ok == Cache.put_all(entries)

    Enum.each(entries, fn {k, v} ->
      assert v == Cache.get(k)
    end)
  end
end
