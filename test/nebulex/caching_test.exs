defmodule Nebulex.CachingTest do
  use ExUnit.Case, async: true
  use Nebulex.Caching

  @behaviour Nebulex.Caching.KeyGenerator

  defmodule Cache do
    use Nebulex.Cache,
      otp_app: :nebulex,
      adapter: Nebulex.Adapters.Local
  end

  defmodule CacheWithDefaultKeyGenerator do
    use Nebulex.Cache,
      otp_app: :nebulex,
      adapter: Nebulex.Adapters.Local,
      default_key_generator: __MODULE__

    @behaviour Nebulex.Caching.KeyGenerator

    @impl true
    def generate(mod, fun, args), do: :erlang.phash2({mod, fun, args})
  end

  defmodule ErrorCache do
    use Nebulex.Cache,
      otp_app: :nebulex,
      adapter: Nebulex.Adapters.Local
  end

  defmodule Meta do
    defstruct [:id, :count]
    @type t :: %__MODULE__{}
  end

  defmodule TestKeyGenerator do
    @behaviour Nebulex.Caching.KeyGenerator

    @impl true
    def generate(_, :put_with_keygen, [arg1, _arg2]) do
      arg1
    end

    def generate(mod, fun, args) do
      :erlang.phash2({mod, fun, args})
    end
  end

  import Nebulex.CacheCase

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

    test "cacheable fails invalid option :on_error" do
      msg = "expected on_error: to be :raise or :nothing, got: :invalid"

      assert_raise ArgumentError, msg, fn ->
        defmodule Test do
          use Nebulex.Caching

          @decorate cacheable(cache: Cache, on_error: :invalid)
          def t(a, b) do
            {a, b}
          end
        end
      end
    end

    test "cache_evict fails invalid option :keys" do
      msg = "expected keys: to be a list with at least one element, got: []"

      assert_raise ArgumentError, msg, fn ->
        defmodule Test do
          use Nebulex.Caching

          @decorate cache_evict(cache: Cache, keys: [])
          def t(a, b) do
            {a, b}
          end
        end
      end
    end
  end

  describe "cacheable" do
    test "with default opts" do
      refute Cache.get!("x")
      assert get_by_x("x") == {"x", "y"}
      assert Cache.get!("x") == {"x", "y"}
      refute get_by_x("nil")
      refute Cache.get!("nil")

      refute Cache.get!({2, 2})
      assert get_by_xy(2, 2) == {2, 4}
      assert Cache.get!({2, 2}) == {2, 4}

      :ok = Process.sleep(1100)
      assert Cache.get!("x") == {"x", "y"}
      assert Cache.get!({2, 2}) == {2, 4}
    end

    test "with opts" do
      refute Cache.get!("x")
      assert get_with_opts(1) == 1
      assert Cache.get!(1) == 1

      :ok = Process.sleep(1100)
      refute Cache.get!(1)
    end

    test "with match function" do
      refute Cache.get!(:x)
      assert get_with_match(:x) == :x
      refute Cache.get!(:x)

      refute Cache.get!(:y)
      assert get_with_match(:y) == :y
      assert Cache.get!(:y)

      refute Cache.get!("true")
      assert get_with_match_fun("true") == {:ok, "true"}
      assert Cache.get!("true") == {:ok, "true"}

      refute Cache.get!(1)
      assert get_with_match_fun(1) == {:ok, "1"}
      assert Cache.get!(1) == "1"

      refute Cache.get!({:ok, "hello"})
      assert get_with_match_fun({:ok, "hello"}) == :error
      refute Cache.get!({:ok, "hello"})
    end

    test "with default key" do
      assert get_with_default_key(123, {:foo, "bar"}) == :ok
      assert [123, {:foo, "bar"}] |> :erlang.phash2() |> Cache.get!() == :ok
      assert get_with_default_key(:foo, "bar") == :ok
      assert [:foo, "bar"] |> :erlang.phash2() |> Cache.get!() == :ok
    end

    test "defining keys using structs and maps" do
      refute Cache.get!("x")
      assert get_meta(%Meta{id: 1, count: 1}) == %Meta{id: 1, count: 1}
      assert Cache.get!({Meta, 1}) == %Meta{id: 1, count: 1}

      refute Cache.get!("y")
      assert get_map(%{id: 1}) == %{id: 1}
      assert Cache.get!(1) == %{id: 1}
    end

    test "with multiple clauses" do
      refute Cache.get!(2)
      assert multiple_clauses(2, 2) == 4
      assert Cache.get!(2) == 4

      refute Cache.get!("foo")
      assert multiple_clauses("foo", "bar") == {"foo", "bar"}
      assert Cache.get!("foo") == {"foo", "bar"}
    end

    test "without args" do
      refute Cache.get!(0)
      assert get_without_args() == "hello"
      assert Cache.get!(0) == "hello"
    end

    test "with side effects and returning false (issue #111)" do
      refute Cache.get!("side-effect")
      assert get_false_with_side_effect(false) == false
      assert Cache.get!("side-effect") == 1
      assert get_false_with_side_effect(false) == false
      assert Cache.get!("side-effect") == 1
    end
  end

  describe "cache_put" do
    test "with default opts" do
      assert set_keys(x: 1, y: 2, z: 3) == :ok
      assert update_fun(:x) == :x
      assert update_fun(:y) == :y
      assert Cache.get!(:x) == :x
      assert Cache.get!(:y) == :y
      assert Cache.get!(:z) == 3

      :ok = Process.sleep(1100)
      assert Cache.get!(:x) == :x
      assert Cache.get!(:y) == :y
      assert Cache.get!(:z) == 3
    end

    test "with opts" do
      assert set_keys(x: 1, y: 2, z: 3) == :ok
      assert update_with_opts(:x) == :x
      assert update_with_opts(:y) == :y

      :ok = Process.sleep(1100)
      refute Cache.get!(:x)
      refute Cache.get!(:y)
    end

    test "with match function" do
      assert update_with_match(:x) == {:ok, "x"}
      assert update_with_match(true) == {:ok, "true"}
      assert update_with_match({:z, 1}) == :error
      assert Cache.get!(:x) == "x"
      assert Cache.get!(true) == {:ok, "true"}
      refute Cache.get!({:z, 1})
    end

    test "without args" do
      refute Cache.get!(0)
      assert update_without_args() == "hello"
      assert Cache.get!(0) == "hello"
    end

    test "with multiple keys and ttl" do
      assert set_keys(x: 1, y: 2, z: 3) == :ok

      assert update_with_multiple_keys(:x, :y) == {:ok, {"x", "y"}}
      assert Cache.get!(:x) == {"x", "y"}
      assert Cache.get!(:y) == {"x", "y"}
      assert Cache.get!(:z) == 3

      :ok = Process.sleep(1100)
      refute Cache.get!(:x)
      refute Cache.get!(:y)
      assert Cache.get!(:z) == 3
    end
  end

  describe "cache_evict" do
    test "with single key" do
      assert set_keys(x: 1, y: 2, z: 3) == :ok

      assert evict_fun(:x) == :x
      refute Cache.get!(:x)
      assert Cache.get!(:y) == 2
      assert Cache.get!(:z) == 3

      assert evict_fun(:y) == :y
      refute Cache.get!(:x)
      refute Cache.get!(:y)
      assert Cache.get!(:z) == 3
    end

    test "with multiple keys" do
      assert set_keys(x: 1, y: 2, z: 3) == :ok
      assert evict_keys_fun(:x, :y) == {:x, :y}
      refute Cache.get!(:x)
      refute Cache.get!(:y)
      assert Cache.get!(:z) == 3
    end

    test "all entries" do
      assert set_keys(x: 1, y: 2, z: 3) == :ok
      assert evict_all_fun("hello") == "hello"
      refute Cache.get!(:x)
      refute Cache.get!(:y)
      refute Cache.get!(:z)
    end

    test "without args" do
      refute Cache.get!(0)
      assert get_without_args() == "hello"
      assert Cache.get!(0) == "hello"

      assert evict_without_args() == "hello"
      refute Cache.get!(0)
    end
  end

  describe "option :key_generator on" do
    test "cacheable annotation" do
      key = TestKeyGenerator.generate(__MODULE__, :get_with_keygen, [1, 2])

      refute Cache.get!(key)
      assert get_with_keygen(1, 2) == {1, 2}
      assert Cache.get!(key) == {1, 2}
    end

    test "cache_evict annotation" do
      key = TestKeyGenerator.generate(__MODULE__, :evict_with_keygen, ["foo", "bar"])

      :ok = Cache.put(key, {"foo", "bar"})
      assert Cache.get!(key) == {"foo", "bar"}

      assert evict_with_keygen("foo", "bar") == {"foo", "bar"}
      refute Cache.get!(key)
    end

    test "cache_put annotation" do
      assert multiple_clauses(2, 2) == 4
      assert Cache.get!(2) == 4

      assert put_with_keygen(2, 4) == 8
      assert multiple_clauses(2, 2) == 8
      assert Cache.get!(2) == 8

      assert put_with_keygen(2, 8) == 16
      assert multiple_clauses(2, 2) == 16
      assert Cache.get!(2) == 16
    end

    test "cacheable annotation with multiple function clauses and pattern-matching " do
      key = TestKeyGenerator.generate(__MODULE__, :get_with_keygen2, [1, 2])

      refute Cache.get!(key)
      assert get_with_keygen2(1, 2, %{a: {1, 2}}) == {1, 2}
      assert Cache.get!(key) == {1, 2}

      key = TestKeyGenerator.generate(__MODULE__, :get_with_keygen2, [1, 2, %{b: 3}])

      refute Cache.get!(key)
      assert get_with_keygen2(1, 2, %{b: 3}) == {1, 2, %{b: 3}}
      assert Cache.get!(key) == {1, 2, %{b: 3}}
    end

    test "cacheable annotation with ignored arguments" do
      key = TestKeyGenerator.generate(__MODULE__, :get_with_keygen3, [1, %{b: 2}])

      refute Cache.get!(key)
      assert get_with_keygen3(1, 2, 3, {1, 2}, [1], %{a: 1}, %{b: 2}) == {1, %{b: 2}}
      assert Cache.get!(key) == {1, %{b: 2}}
    end
  end

  describe "default key generator on" do
    setup_with_cache(CacheWithDefaultKeyGenerator)

    test "cacheable annotation" do
      key = CacheWithDefaultKeyGenerator.generate(__MODULE__, :get_with_default_key_generator, [1])

      refute CacheWithDefaultKeyGenerator.get!(key)
      assert get_with_default_key_generator(1) == 1
      assert CacheWithDefaultKeyGenerator.get!(key) == 1
    end

    test "cache_evict annotation" do
      key = CacheWithDefaultKeyGenerator.generate(__MODULE__, :del_with_default_key_generator, [1])

      :ok = CacheWithDefaultKeyGenerator.put(key, 1)
      assert CacheWithDefaultKeyGenerator.get!(key) == 1

      assert del_with_default_key_generator(1) == 1
      refute CacheWithDefaultKeyGenerator.get!(key)
    end
  end

  describe "key-generator tuple on" do
    test "cacheable annotation" do
      key = generate_key({1, 2})

      refute Cache.get!(key)
      assert get_with_tuple_keygen(1, 2) == {1, 2}
      assert Cache.get!(key) == {1, 2}
    end

    test "cacheable annotation (with key-generator: TestKeyGenerator)" do
      key = TestKeyGenerator.generate(:a, :b, [1])

      refute Cache.get!(key)
      assert get_with_tuple_keygen2(1, 2) == {1, 2}
      assert Cache.get!(key) == {1, 2}
    end

    test "cache_evict annotation" do
      key = generate_key({"foo", "bar"})

      :ok = Cache.put(key, {"foo", "bar"})
      assert Cache.get!(key) == {"foo", "bar"}

      assert evict_with_tuple_keygen("foo", "bar") == {"foo", "bar"}
      refute Cache.get!(key)
    end

    test "cache_put annotation" do
      assert multiple_clauses(2, 2) == 4
      assert Cache.get!(2) == 4

      assert put_with_tuple_keygen(2, 4) == 8
      assert multiple_clauses(2, 2) == 8
      assert Cache.get!(2) == 8

      assert put_with_tuple_keygen(2, 8) == 16
      assert multiple_clauses(2, 2) == 16
      assert Cache.get!(2) == 16
    end
  end

  describe "key-generator with shorthand tuple on" do
    test "cacheable annotation" do
      key = TestKeyGenerator.generate(__MODULE__, :get_with_shorthand_tuple_keygen, [1])

      refute Cache.get!(key)
      assert get_with_shorthand_tuple_keygen(1, 2, 3) == {1, 2}
      assert Cache.get!(key) == {1, 2}
    end

    test "cacheable annotation (with key-generator: __MODULE__)" do
      key = generate(__MODULE__, :get_with_shorthand_tuple_keygen2, [1])

      refute Cache.get!(key)
      assert get_with_shorthand_tuple_keygen2(1, 2) == {1, 2}
      assert Cache.get!(key) == {1, 2}
    end

    test "cache_evict annotation" do
      key = TestKeyGenerator.generate(__MODULE__, :evict_with_shorthand_tuple_keygen, ["foo"])

      :ok = Cache.put(key, {"foo", "bar"})
      assert Cache.get!(key) == {"foo", "bar"}

      assert evict_with_shorthand_tuple_keygen("foo", "bar") == {"foo", "bar"}
      refute Cache.get!(key)
    end

    test "cache_put annotation" do
      key = TestKeyGenerator.generate(__MODULE__, :put_with_shorthand_tuple_keygen, ["foo"])

      refute Cache.get!(key)
      assert put_with_shorthand_tuple_keygen("foo", "bar") == {"foo", "bar"}
      assert Cache.get!(key) == {"foo", "bar"}
    end
  end

  describe "option :on_error on" do
    test "cacheable annotation raises a cache error" do
      assert_raise Nebulex.Error, ~r"could not lookup", fn ->
        get_and_raise_exception(:raise)
      end
    end

    test "cacheable annotation ignores the exception" do
      assert get_ignoring_exception("foo") == "foo"
    end

    test "cache_put annotation raises a cache error" do
      assert_raise Nebulex.Error, ~r"could not lookup", fn ->
        update_and_raise_exception(:raise)
      end
    end

    test "cache_put annotation ignores the exception" do
      assert update_ignoring_exception("foo") == "foo"
    end

    test "cache_evict annotation raises a cache error" do
      assert_raise Nebulex.Error, ~r"could not lookup", fn ->
        evict_and_raise_exception(:raise)
      end
    end

    test "cache_evict annotation ignores the exception" do
      assert evict_ignoring_exception("foo") == "foo"
    end
  end

  ## Annotated Functions

  @decorate cacheable(cache: Cache)
  def get_without_args, do: "hello"

  @decorate cacheable(cache: Cache, key: x)
  def get_by_x(x, y \\ "y") do
    case x do
      "nil" -> nil
      _ -> {x, y}
    end
  end

  @decorate cacheable(cache: Cache, opts: [ttl: 1000])
  def get_with_opts(x) do
    x
  end

  @decorate cacheable(cache: Cache)
  def get_false_with_side_effect(v) do
    _ = Cache.update!("side-effect", 1, &(&1 + 1))
    v
  end

  @decorate cacheable(cache: Cache, match: fn x -> x != :x end)
  def get_with_match(x) do
    x
  end

  @decorate cacheable(cache: Cache, match: &match_fun/1)
  def get_with_match_fun(x) do
    {:ok, to_string(x)}
  rescue
    _ -> :error
  end

  @decorate cacheable(cache: Cache, key: {x, y})
  def get_by_xy(x, y) do
    {x, y * 2}
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

  @decorate cache_put(cache: Cache)
  def update_without_args, do: "hello"

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

  @decorate cache_put(cache: Cache, keys: [x, y], match: &match_fun/1, opts: [ttl: 1000])
  def update_with_multiple_keys(x, y) do
    {:ok, {to_string(x), to_string(y)}}
  rescue
    _ -> :error
  end

  @decorate cache_evict(cache: Cache)
  def evict_without_args, do: "hello"

  @decorate cache_evict(cache: Cache, key: x)
  def evict_fun(x) do
    x
  end

  @decorate cache_evict(cache: Cache, keys: [x, y])
  def evict_keys_fun(x, y) do
    {x, y}
  end

  @decorate cache_evict(cache: Cache, all_entries: true, before_invocation: true)
  def evict_all_fun(x) do
    x
  end

  @decorate cacheable(cache: Cache, key: x)
  def multiple_clauses(x, y \\ 0)

  def multiple_clauses(x, y) when is_integer(x) and is_integer(y) do
    x * y
  end

  def multiple_clauses(x, y) do
    {x, y}
  end

  @decorate cacheable(cache: Cache, key_generator: TestKeyGenerator)
  def get_with_keygen(x, y) do
    {x, y}
  end

  @decorate cacheable(cache: Cache, key_generator: TestKeyGenerator)
  def get_with_keygen2(x, y, z)

  def get_with_keygen2(x, y, %{a: {_x, _y}}) do
    {x, y}
  end

  def get_with_keygen2(x, y, %{b: _} = z) do
    {x, y, z}
  end

  @decorate cacheable(cache: Cache, key_generator: TestKeyGenerator)
  def get_with_keygen3(x, _y, _, {_, _}, [_], %{}, %{} = z) do
    {x, z}
  end

  @decorate cache_evict(cache: Cache, key_generator: TestKeyGenerator)
  def evict_with_keygen(x, y) do
    {x, y}
  end

  @decorate cache_put(cache: Cache, key_generator: TestKeyGenerator)
  def put_with_keygen(x, y) do
    x * y
  end

  @decorate cacheable(cache: CacheWithDefaultKeyGenerator)
  def get_with_default_key_generator(id), do: id

  @decorate cache_evict(cache: CacheWithDefaultKeyGenerator)
  def del_with_default_key_generator(id), do: id

  @decorate cacheable(cache: Cache, key_generator: {TestKeyGenerator, [x]})
  def get_with_shorthand_tuple_keygen(x, y, _z) do
    {x, y}
  end

  @decorate cacheable(cache: Cache, key_generator: {__MODULE__, [x]})
  def get_with_shorthand_tuple_keygen2(x, y) do
    {x, y}
  end

  @decorate cache_evict(cache: Cache, key_generator: {TestKeyGenerator, [x]})
  def evict_with_shorthand_tuple_keygen(x, y) do
    {x, y}
  end

  @decorate cache_put(cache: Cache, key_generator: {TestKeyGenerator, [x]})
  def put_with_shorthand_tuple_keygen(x, y) do
    {x, y}
  end

  @decorate cacheable(cache: Cache, key_generator: {__MODULE__, :generate_key, [{x, y}]})
  def get_with_tuple_keygen(x, y) do
    {x, y}
  end

  @decorate cacheable(cache: Cache, key_generator: {TestKeyGenerator, :generate, [:a, :b, [x]]})
  def get_with_tuple_keygen2(x, y) do
    {x, y}
  end

  @decorate cache_evict(cache: Cache, key_generator: {__MODULE__, :generate_key, [{x, y}]})
  def evict_with_tuple_keygen(x, y) do
    {x, y}
  end

  @decorate cache_put(cache: Cache, key_generator: {__MODULE__, :generate_key, [x]})
  def put_with_tuple_keygen(x, y) do
    x * y
  end

  @decorate cacheable(cache: ErrorCache, key: x)
  def get_and_raise_exception(x) do
    x
  end

  @decorate cache_put(cache: ErrorCache, key: x)
  def update_and_raise_exception(x) do
    x
  end

  @decorate cache_evict(cache: ErrorCache, key: x)
  def evict_and_raise_exception(x) do
    x
  end

  @decorate cacheable(cache: ErrorCache, key: x, on_error: :nothing)
  def get_ignoring_exception(x) do
    x
  end

  @decorate cache_put(cache: ErrorCache, key: x, on_error: :nothing)
  def update_ignoring_exception(x) do
    x
  end

  @decorate cache_evict(cache: ErrorCache, key: x, on_error: :nothing)
  def evict_ignoring_exception(x) do
    x
  end

  # Custom key-generator function
  def generate_key(arg), do: arg

  @impl Nebulex.Caching.KeyGenerator
  def generate(module, function_name, args) do
    :erlang.phash2({module, function_name, args})
  end

  ## Private Functions

  defp match_fun({:ok, "true"}), do: true
  defp match_fun({:ok, val}), do: {true, val}
  defp match_fun(_), do: false

  defp set_keys(entries) do
    assert :ok == Cache.put_all(entries)

    Enum.each(entries, fn {k, v} ->
      assert v == Cache.get!(k)
    end)
  end
end
