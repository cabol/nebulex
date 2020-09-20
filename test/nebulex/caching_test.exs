defmodule Nebulex.CachingTest do
  use ExUnit.Case, async: true
  use Nebulex.Caching

  import Nebulex.TestCase

  defmodule Cache do
    use Nebulex.Cache,
      otp_app: :nebulex,
      adapter: Nebulex.Adapters.Local
  end

  defmodule Meta do
    defstruct [:id, :count]
  end

  alias Nebulex.CachingTest.{Cache, Meta}

  setup_with_cache(Cache)

  describe "decorator" do
    test "cacheable fails because missing cache" do
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
      assert get_by_x("x") == {"x", "y"}
      assert Cache.get("x") == {"x", "y"}
      refute get_by_x("nil")
      refute Cache.get("nil")

      refute Cache.get({"x", "y"})
      assert get_by_xy("x", "y") == {"x", "y"}
      assert Cache.get({"x", "y"}) == {"x", "y"}

      :ok = Process.sleep(1100)
      assert Cache.get("x") == {"x", "y"}
      assert Cache.get({"x", "y"}) == {"x", "y"}
    end

    test "with opts" do
      refute Cache.get("x")
      assert get_with_opts(1) == 1
      assert Cache.get(1) == 1

      :ok = Process.sleep(1100)
      refute Cache.get(1)
    end

    test "with match function" do
      refute Cache.get(:x)
      assert get_with_match(:x) == :x
      refute Cache.get(:x)

      refute Cache.get(:y)
      assert get_with_match(:y) == :y
      assert Cache.get(:y)

      refute Cache.get("true")
      assert get_with_match_fun("true") == {:ok, "true"}
      assert Cache.get("true") == {:ok, "true"}

      refute Cache.get(1)
      assert get_with_match_fun(1) == {:ok, "1"}
      assert Cache.get(1) == "1"

      refute Cache.get({:ok, "hello"})
      assert get_with_match_fun({:ok, "hello"}) == :error
      refute Cache.get({:ok, "hello"})
    end

    test "with default key" do
      key = :erlang.phash2({__MODULE__, :get_with_default_key})

      refute Cache.get(key)
      assert get_with_default_key(123, {:foo, "bar"}) == :ok
      assert Cache.get(key) == :ok
      assert get_with_default_key(:foo, "bar") == :ok
      assert Cache.get(key) == :ok
    end

    test "defining keys using structs and maps" do
      refute Cache.get("x")
      assert get_meta(%Meta{id: 1, count: 1}) == %Meta{id: 1, count: 1}
      assert Cache.get({Meta, 1}) == %Meta{id: 1, count: 1}

      refute Cache.get("y")
      assert get_map(%{id: 1}) == %{id: 1}
      assert Cache.get(1) == %{id: 1}
    end
  end

  describe "cache_put" do
    test "with default opts" do
      assert set_keys(x: 1, y: 2, z: 3) == :ok
      assert update_fun(:x) == :x
      assert update_fun(:y) == :y
      assert Cache.get(:x) == :x
      assert Cache.get(:y) == :y
      assert Cache.get(:z) == 3

      :ok = Process.sleep(1100)
      assert Cache.get(:x) == :x
      assert Cache.get(:y) == :y
      assert Cache.get(:z) == 3
    end

    test "with opts" do
      assert set_keys(x: 1, y: 2, z: 3) == :ok
      assert update_with_opts(:x) == :x
      assert update_with_opts(:y) == :y

      :ok = Process.sleep(1100)
      refute Cache.get(:x)
      refute Cache.get(:y)
    end

    test "with match function" do
      assert update_with_match(:x) == {:ok, "x"}
      assert update_with_match(true) == {:ok, "true"}
      assert update_with_match({:z, 1}) == :error
      assert Cache.get(:x) == "x"
      assert Cache.get(true) == {:ok, "true"}
      refute Cache.get({:z, 1})
    end
  end

  describe "cache_evict" do
    test "with single key" do
      assert set_keys(x: 1, y: 2, z: 3) == :ok

      assert evict_fun(:x) == :x
      refute Cache.get(:x)
      assert Cache.get(:y) == 2
      assert Cache.get(:z) == 3

      assert evict_fun(:y) == :y
      refute Cache.get(:x)
      refute Cache.get(:y)
      assert Cache.get(:z) == 3
    end

    test "with multiple keys" do
      assert set_keys(x: 1, y: 2, z: 3) == :ok
      assert evict_keys_fun(:x, :y) == {:x, :y}
      refute Cache.get(:x)
      refute Cache.get(:y)
      assert Cache.get(:z) == 3
    end

    test "all entries" do
      assert set_keys(x: 1, y: 2, z: 3) == :ok
      assert evict_all_fun("hello") == "hello"
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
