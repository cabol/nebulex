defmodule Nebulex.DecoratorsTest do
  use ExUnit.Case, async: true
  use Nebulex.Decorators

  defmodule Hook do
    use Nebulex.Hook

    @impl true
    def handle_post(event), do: send(self(), event)
  end

  defmodule Cache do
    use Nebulex.Cache,
      otp_app: :nebulex,
      adapter: Nebulex.Adapters.Local
  end

  defmodule Meta do
    defstruct [:id, :count]
  end

  alias Nebulex.DecoratorsTest.{Cache, Hook, Meta}
  alias Nebulex.Hook.Event

  setup do
    {:ok, pid} = Cache.start_link(generations: 2)
    :ok

    on_exit(fn ->
      :ok = Process.sleep(10)
      if Process.alive?(pid), do: Cache.stop(pid)
    end)
  end

  test "fail on cacheable because missing cache" do
    assert_raise ArgumentError, "expected cache: to be given as argument", fn ->
      defmodule Test do
        use Nebulex.Decorators

        @decorate cacheable(a: 1)
        def t(a, b) do
          {a, b}
        end
      end
    end
  end

  test "cache" do
    refute Cache.get("x")
    assert {"x", "y"} == get_by_x("x")
    assert {"x", "y"} == Cache.get("x")

    refute Cache.get({"x", "y"})
    assert {"x", "y"} == get_by_xy("x", "y")
    assert {"x", "y"} == Cache.get({"x", "y"})

    :ok = Process.sleep(1100)
    assert {"x", "y"} == Cache.get("x")
    assert {"x", "y"} == Cache.get({"x", "y"})
  end

  test "cache with opts" do
    refute Cache.get("x")
    assert 1 == get_with_opts(1)
    assert 1 == Cache.get(1)

    :ok = Process.sleep(1100)
    refute Cache.get(1)
  end

  test "cache with match" do
    refute Cache.get(:x)
    assert :x == get_with_match(:x)
    refute Cache.get(:x)

    refute Cache.get(:y)
    assert :y == get_with_match(:y)
    assert Cache.get(:y)

    refute Cache.get(:ok)
    assert :ok == get_with_match2(:ok)
    assert Cache.get(:ok)

    refute Cache.get(:error)
    assert :error == get_with_match2(:error)
    refute Cache.get(:error)
  end

  test "cache with default key" do
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

  test "evict" do
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

  test "evict with multiple keys" do
    assert :ok == set_keys(x: 1, y: 2, z: 3)
    assert {:x, :y} == evict_keys_fun(:x, :y)
    refute Cache.get(:x)
    refute Cache.get(:y)
    assert 3 == Cache.get(:z)
  end

  test "evict all entries" do
    assert :ok == set_keys(x: 1, y: 2, z: 3)
    assert "hello" == evict_all_fun("hello")
    refute Cache.get(:x)
    refute Cache.get(:y)
    refute Cache.get(:z)
  end

  test "update" do
    assert :ok == set_keys(x: 1, y: 2, z: 3)
    assert :x == cache_update(:x)
    assert :y == cache_update(:y)
    assert :x == Cache.get(:x)
    assert :y == Cache.get(:y)
    assert 3 == Cache.get(:z)

    :ok = Process.sleep(1100)
    assert :x == Cache.get(:x)
    assert :y == Cache.get(:y)
    assert 3 == Cache.get(:z)
  end

  test "update with opts" do
    assert :ok == set_keys(x: 1, y: 2, z: 3)
    assert :x == cache_update_with_opts(:x)
    assert :y == cache_update_with_opts(:y)

    :ok = Process.sleep(1100)
    refute Cache.get(:x)
    refute Cache.get(:y)
  end

  test "update with match" do
    assert :ok == set_keys(x: 0, y: 0, z: 0)
    assert :x == cache_update_with_match(:x)
    assert :y == cache_update_with_match(:y)
    assert 0 == Cache.get(:x)
    assert :y == Cache.get(:y)
  end

  test "hook" do
    assert 1 = hookable_fun(1)
    assert_receive %Event{module: __MODULE__, name: :hookable_fun, arity: 1} = event, 200

    assert_raise(Nebulex.HookError, ~r"hook execution failed with error", fn ->
      wrong_hookable_fun(1)
    end)
  end

  ## Caching Functions

  @decorate cacheable(cache: Cache, key: x)
  def get_by_x(x, y \\ "y") do
    {x, y}
  end

  @decorate cacheable(cache: Cache, key: x, opts: [ttl: 1000])
  def get_with_opts(x) do
    x
  end

  @decorate cacheable(cache: Cache, key: x, match: fn x -> x != :x end)
  def get_with_match(x) do
    x
  end

  @decorate cacheable(cache: Cache, key: x, match: &match/1)
  def get_with_match2(x) do
    x
  end

  defp match(:ok), do: true
  defp match(_), do: false

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
  def cache_update(x) do
    x
  end

  @decorate cache_put(cache: Cache, key: x, opts: [ttl: 1000])
  def cache_update_with_opts(x) do
    x
  end

  @decorate cache_put(cache: Cache, key: x, match: fn x -> x != :x end)
  def cache_update_with_match(x) do
    x
  end

  @decorate hook(Hook)
  def hookable_fun(x) do
    x
  end

  @decorate hook(WrongHook)
  def wrong_hookable_fun(x) do
    x
  end

  ## Private Functions

  defp set_keys(entries) do
    assert :ok == Cache.put_all(entries)

    Enum.each(entries, fn {k, v} ->
      assert v == Cache.get(k)
    end)
  end
end
