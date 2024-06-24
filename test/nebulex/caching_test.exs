defmodule Nebulex.CachingTest do
  use ExUnit.Case, async: true

  defmodule Cache do
    @moduledoc false
    use Nebulex.Cache,
      otp_app: :nebulex,
      adapter: Nebulex.TestAdapter
  end

  use Nebulex.Caching, cache: Cache

  import Nebulex.CacheCase

  defmodule YetAnotherCache do
    @moduledoc false
    use Nebulex.Cache,
      otp_app: :nebulex,
      adapter: Nebulex.TestAdapter
  end

  defmodule Meta do
    @moduledoc false

    @type t :: %__MODULE__{}

    defstruct [:id, :count]
  end

  ## Tests

  setup_with_cache Cache

  describe "caching definition" do
    test "ok: valid :default_key_generator option" do
      defmodule ValidCompileOptsTest do
        use Nebulex.Caching, default_key_generator: Nebulex.Caching.SimpleKeyGenerator
      end
    end

    test "error: :default_key_generator module was not compiled" do
      msg =
        "invalid value for :default_key_generator option: " <>
          "the module NotCompiledKeyGenerator was not compiled"

      assert_raise NimbleOptions.ValidationError, ~r|#{msg}|, fn ->
        defmodule InvalidCompileOptsTest do
          use Nebulex.Caching, default_key_generator: NotCompiledKeyGenerator
        end
      end
    end

    test "error: :default_key_generator module doesn't implement the behaviour" do
      msg =
        "invalid value for :default_key_generator option: Nebulex.Caching " <>
          "expects the option value Nebulex.CachingTest.InvalidKeyGenerator " <>
          "to list Nebulex.Caching.KeyGenerator as a behaviour"

      defmodule InvalidKeyGenerator do
        @moduledoc false
      end

      assert_raise NimbleOptions.ValidationError, msg, fn ->
        defmodule InvalidCompileOptsTest do
          use Nebulex.Caching, default_key_generator: InvalidKeyGenerator
        end
      end
    end
  end

  describe "decorator" do
    test "cacheable fails because missing cache" do
      assert_raise ArgumentError, ~r|expected :cache option to be found within the decorator|, fn ->
        defmodule MissingCacheTest do
          use Nebulex.Caching

          @decorate cacheable(a: 1)
          def t(a, b) do
            {a, b}
          end
        end

        MissingCacheTest.t(1, 2)
      end
    end

    test "cacheable fails because invalid :on_error option value" do
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

    test "cache_evict fails because invalid :keys option value" do
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
      assert get_by_xy("x") == nil
      assert Cache.fetch!("x") == nil

      assert get_by_xy(1, 11) == 11
      assert Cache.get!(1) == 11

      assert get_by_xy(2, {:ok, 22}) == {:ok, 22}
      assert Cache.get!(2) == {:ok, 22}

      assert get_by_xy(3, :error) == :error
      refute Cache.get!(3)

      assert get_by_xy(4, {:error, 4}) == {:error, 4}
      refute Cache.get!(4)

      refute Cache.get!({:xy, 2})
      assert multiply_xy(:xy, 2) == {:xy, 4}
      assert Cache.get!({:xy, 2}) == {:xy, 4}

      assert Cache.fetch!("x") == nil
      assert Cache.get!(1) == 11
      assert Cache.get!(2) == {:ok, 22}
      refute Cache.get!(3)
      refute Cache.get!(4)
      assert Cache.get!({:xy, 2}) == {:xy, 4}
    end

    test "with opts" do
      refute Cache.get!("x")
      assert get_with_opts(1) == 1
      assert Cache.get!(1) == 1

      _ = t_sleep(1100)

      refute Cache.get!(1)
    end

    test "with match function" do
      refute Cache.get!(:x)
      assert get_with_match(:x) == :x
      refute Cache.get!(:x)

      refute Cache.get!(:y)
      assert get_with_match(:y) == :y
      assert Cache.get!(:y)

      refute Cache.get!(true)
      assert get_with_match_fun(true) == {:ok, "true"}
      assert Cache.get!(true) == {:ok, "true"}

      refute Cache.get!(1)
      assert get_with_match_fun(1) == {:ok, "1"}
      assert Cache.get!(1) == "1"

      refute Cache.get!({:ok, "hello"})
      assert get_with_match_fun({:ok, "hello"}) == :error
      refute Cache.get!({:ok, "hello"})
    end

    test "with match function and context" do
      refute Cache.get!(:x)
      assert get_with_match_fun_and_ctx(:x) == {:ok, "x"}
      assert_receive %{module: __MODULE__, function_name: :get_with_match_fun_and_ctx, args: [:x]}
      assert Cache.get!(:x) == "x"

      refute Cache.get!(true)
      assert get_with_match_fun_and_ctx(true) == {:ok, "true"}
      assert_receive %{module: __MODULE__, function_name: :get_with_match_fun_and_ctx, args: [true]}
      assert Cache.get!(true) == {:ok, "true"}
    end

    test "with match function and custom opts" do
      refute Cache.get!(300)
      assert get_with_custom_ttl(300) == {:ok, %{ttl: 300}}
      assert Cache.get!(300) == {:ok, %{ttl: 300}}

      _ = t_sleep(400)

      refute Cache.get!(300)
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

  describe "cachable with references" do
    setup_with_cache YetAnotherCache

    test "returns referenced key" do
      # Expected values
      referenced_key = keyref "referenced_id"
      result = %{id: "referenced_id", name: "referenced_name"}

      assert_common_references_flow("referenced_id", referenced_key, result, &get_with_keyref/1)
    end

    test "returns referenced key by calling function with context" do
      # Expected values
      key = :erlang.phash2({"referenced_id", ["referenced_name"]})
      referenced_key = keyref key
      result = %{id: "referenced_id", name: "referenced_name"}

      assert_common_references_flow(key, referenced_key, result, &get_with_keyref_fn_ctx/1)
    end

    test "returns referenced key by calling referenced cache" do
      # Expected values
      referenced_key = keyref "referenced_id", cache: YetAnotherCache, ttl: 5000
      result = %{id: "referenced_id", name: "referenced_name"}

      assert_common_references_flow(
        YetAnotherCache,
        "referenced_id",
        referenced_key,
        result,
        &get_with_keyref_cache/1
      )
    end

    test "returns referenced key from the args" do
      # Expected values
      referenced_key = keyref "id"
      result = %{attrs: %{id: "id"}, name: "name"}

      # Nothing is cached yet
      refute Cache.get!("id")
      refute Cache.get!("name")

      # First run: the function block is executed and its result is cached under
      # the referenced key, and the referenced key is cached under the given key
      assert get_with_keyref_from_args("name", %{id: "id"}) == result

      # Assert the key points to the referenced key
      assert Cache.get!("name") == referenced_key

      # Assert the referenced key points to the cached value
      assert Cache.get!("id") == result

      # Next run: the value should come from the cache
      assert get_with_keyref_from_args("name", %{id: "id"}) == result
    end

    test "returns fixed referenced key" do
      # Expected values
      referenced_key = keyref "fixed_id"
      result = %{id: "fixed_id", name: "name"}

      # Nothing is cached yet
      refute Cache.get!("fixed_id")
      refute Cache.get!("name")

      # First run: the function block is executed and its result is cached under
      # the referenced key, and the referenced key is cached under the given key
      assert get_with_fixed_keyref("name") == result

      # Assert the key points to the referenced key
      assert Cache.get!("name") == referenced_key

      # Assert the referenced key points to the cached value
      assert Cache.get!("fixed_id") == result

      # Next run: the value should come from the cache
      assert get_with_fixed_keyref("name") == result
    end

    test "removes the reference's parent key due to the value was updated, causing a mismatch" do
      # Expected values
      referenced_key = keyref "referenced_id"
      result = %{id: "referenced_id", name: "referenced_name"}

      # Nothing is cached yet
      refute Cache.get!("referenced_id")
      refute Cache.get!("referenced_name")

      # First time: everything works as usual
      assert get_with_keyref_and_match("referenced_name", result) == result

      # Assert the key points to the referenced key
      assert Cache.get!("referenced_name") == referenced_key

      # Assert the referenced key points to the cached value
      assert Cache.get!("referenced_id") == result

      # Update the cached value
      another_result = %{result | name: "another_referenced_name"}

      # Replace cached value with the updated result
      :ok = Cache.put("referenced_id", another_result)

      # Assert the cached value
      assert Cache.get!("referenced_id") == another_result

      # Next run: Since the cached value was intentionally modified, there will
      # be a mismatch with the given key, hence, the reference is removed from
      # the cache and the function block is executed
      assert get_with_keyref_and_match("referenced_name", another_result) == another_result

      # Refute the key does exist in the cache
      refute Cache.get!("referenced_name")

      # The referenced key points to the updated value
      assert Cache.get!("referenced_id") == another_result

      # Next run: works as usual since there isn't a mismatch this time
      assert get_with_keyref_and_match("another_referenced_name", another_result) == another_result

      # Assert the key points to the referenced key
      assert Cache.get!("another_referenced_name") == referenced_key

      # Assert the referenced key points to the cached value
      assert Cache.get!("referenced_id") == another_result
    end

    test "removes the reference's parent key due to the value was deleted, causing a mismatch" do
      # Expected values
      referenced_key = keyref "referenced_id"
      result = %{id: "referenced_id", name: "referenced_name"}

      # Nothing is cached yet
      refute Cache.get!("referenced_id")
      refute Cache.get!("referenced_name")

      # First time: everything works as usual
      assert get_with_keyref_and_match("referenced_name", result) == result

      # Assert the key points to the referenced key
      assert Cache.get!("referenced_name") == referenced_key

      # Assert the referenced key points to the cached value
      assert Cache.get!("referenced_id") == result

      # Delete the referenced key
      :ok = Cache.delete("referenced_id")

      # Assert the cached value
      refute Cache.get!("referenced_id")

      # Update the cached value
      another_result = %{result | name: "another_referenced_name"}

      # Next run: Since the cached value was intentionally deleted, there will
      # be a mismatch with the given new result, hence, the reference is removed
      # from the cache and the function block is executed
      assert get_with_keyref_and_match("referenced_name", another_result) == another_result

      # Refute the key does exist in the cache
      refute Cache.get!("referenced_name")

      # Refute the referenced key does exist in the cache
      refute Cache.get!("referenced_id")
    end

    ## Private functions

    defp assert_common_references_flow(ref_cache \\ nil, key, referenced_key, result, fun) do
      # Resolve ref cache if any
      ref_cache = ref_cache || Cache

      # Nothing is cached yet
      refute Cache.get!("referenced_id")
      refute Cache.get!("referenced_name")

      # First run: the function block is executed and its result is cached under
      # the referenced key, and the referenced key is cached under the given key
      assert fun.("referenced_name") == result

      # Assert the key points to the referenced key
      assert Cache.get!("referenced_name") == referenced_key

      # Assert the referenced key points to the cached value
      assert ref_cache.get!(key) == result

      # Next run: the value should come from the cache
      assert fun.("referenced_name") == result

      # Simulate a cache eviction for the referenced key
      :ok = ref_cache.delete!(key)

      # The value under the referenced key should not longer exist
      refute ref_cache.get!(key)

      # Assert the key still points to the referenced key
      assert Cache.get!("referenced_name") == referenced_key

      # Next run: the key does exist but the referenced key doesn't, then the
      # function block is executed and the result is cached under the referenced
      # key back again
      assert fun.("referenced_name") == result

      # Assert the key points to the referenced key
      assert Cache.get!("referenced_name") == referenced_key

      # Assert the referenced key points to the cached value
      assert ref_cache.get!(key) == result

      # Simulate the referenced key is overridden
      :ok = Cache.put!("referenced_name", "overridden")

      # The referenced key is overridden
      assert fun.("referenced_name") == "overridden"

      # Assert the previously referenced key remains the same
      assert ref_cache.get!(key) == result
    end
  end

  describe "cache_put" do
    test "with default opts" do
      assert update_fun(1) == nil
      refute Cache.get!(1)

      assert update_fun(1, :error) == :error
      refute Cache.get!(1)

      assert update_fun(1, {:error, :error}) == {:error, :error}
      refute Cache.get!(1)

      assert set_keys(x: 1, y: 2, z: 3) == :ok

      assert update_fun(:x, 2) == 2
      assert update_fun(:y, {:ok, 4}) == {:ok, 4}

      assert Cache.get!(:x) == 2
      assert Cache.get!(:y) == {:ok, 4}
      assert Cache.get!(:z) == 3

      _ = t_sleep(1100)

      assert Cache.get!(:x) == 2
      assert Cache.get!(:y) == {:ok, 4}
      assert Cache.get!(:z) == 3
    end

    test "with opts" do
      assert set_keys(x: 1, y: 2, z: 3) == :ok
      assert update_with_opts(:x) == :x
      assert update_with_opts(:y) == :y

      _ = t_sleep(1100)

      refute Cache.get!(:x)
      refute Cache.get!(:y)
    end

    test "with match function" do
      assert update_with_match(:x) == {:ok, "x"}
      assert Cache.get!(:x) == "x"

      assert update_with_match(true) == {:ok, "true"}
      assert Cache.get!(true) == {:ok, "true"}

      assert update_with_match({:z, 1}) == :error
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

      _ = t_sleep(1100)

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

  describe "option :key with custom key generator on" do
    test "cacheable annotation" do
      key = default_hash(:cacheable, :get_with_keygen, 2, [1, 2])

      refute Cache.get!(key)
      assert get_with_keygen(1, 2) == {1, 2}
      assert Cache.get!(key) == {1, 2}
    end

    test "cacheable annotation with multiple function clauses and pattern-matching " do
      key = default_hash(:cacheable, :get_with_keygen2, 3, [1, 2])

      refute Cache.get!(key)
      assert get_with_keygen2(1, 2, %{a: {1, 2}}) == {1, 2}
      assert Cache.get!(key) == {1, 2}

      key = default_hash(:cacheable, :get_with_keygen2, 3, [1, 2, %{b: 3}])

      refute Cache.get!(key)
      assert get_with_keygen2(1, 2, %{b: 3}) == {1, 2, %{b: 3}}
      assert Cache.get!(key) == {1, 2, %{b: 3}}
    end

    test "cacheable annotation with ignored arguments" do
      key = default_hash(:cacheable, :get_with_keygen3, 7, [1, %{b: 2}])

      refute Cache.get!(key)
      assert get_with_keygen3(1, 2, 3, {1, 2}, [1], %{a: 1}, %{b: 2}) == {1, %{b: 2}}
      assert Cache.get!(key) == {1, %{b: 2}}
    end

    test "cacheable annotation with custom key" do
      key = {:a, :b, 1, 2}

      refute Cache.get!(key)
      assert get_with_keygen4(1, 2) == {1, 2}
      assert Cache.get!(key) == {1, 2}
    end

    test "cache_evict annotation" do
      key = default_hash(:cache_evict, :evict_with_keygen, 2, ["foo", "bar"])

      :ok = Cache.put(key, {"foo", "bar"})
      assert Cache.get!(key) == {"foo", "bar"}

      assert evict_with_keygen("foo", "bar") == {"foo", "bar"}
      refute Cache.get!(key)
    end

    test "cache_evict annotation with custom key" do
      key = {"foo", "bar"}

      :ok = Cache.put(key, {"foo", "bar"})
      assert Cache.get!(key) == {"foo", "bar"}

      assert evict_with_keygen2("foo", "bar") == {"foo", "bar"}
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

    test "cache_put annotation with custom key" do
      key = {:tuple, 2}

      assert Cache.put(key, 2) == :ok
      assert Cache.get!(key) == 2

      assert put_with_keygen2(2, 4) == 8
      assert Cache.get!(key) == 8

      assert put_with_keygen2(2, 8) == 16
      assert Cache.get!(key) == 16
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

  describe "option :cache with anonymous function on" do
    test "cacheable annotation" do
      refute Cache.get!("foo")

      assert get_fn_cache("foo") == "foo"
      assert_receive %{module: __MODULE__, function_name: :get_fn_cache, args: ["foo"]}
      assert Cache.get!("foo") == "foo"
    end

    test "cache_put annotation" do
      :ok = Cache.put("foo", "bar")

      assert update_fn_cache("bar bar") == "bar bar"
      assert_receive %{module: __MODULE__, function_name: :update_fn_cache, args: ["bar bar"]}
      assert Cache.get!("foo") == "bar bar"
    end

    test "cache_evict annotation" do
      :ok = Cache.put("foo", "bar")

      assert delete_fn_cache("bar bar") == "bar bar"
      assert_receive %{module: __MODULE__, function_name: :delete_fn_cache, args: ["bar bar"]}
      refute Cache.get!("foo")
    end
  end

  describe "option :cache raises an exception" do
    test "due to invalid cache value" do
      assert_raise ArgumentError, ~r|invalid value for :cache option|, fn ->
        defmodule RuntimeCacheTest do
          use Nebulex.Caching

          @decorate cacheable(cache: 123, key: {a, b})
          def t(a, b), do: {a, b}
        end

        RuntimeCacheTest.t(1, 2)
      end
    end
  end

  ## Annotated Functions

  @cache Cache

  @decorate cacheable(cache: @cache)
  def get_without_args, do: "hello"

  @decorate cacheable(cache: @cache, key: x)
  def get_by_xy(x, y \\ nil) do
    with _ when not is_nil(x) <- x,
         _ when not is_nil(y) <- y do
      y
    end
  end

  @decorate cacheable(key: {x, y})
  def multiply_xy(x, y) do
    {x, y * 2}
  end

  @decorate cacheable(cache: Cache, opts: [ttl: 1000])
  def get_with_opts(x) do
    x
  end

  @decorate cacheable()
  def get_false_with_side_effect(v) do
    _ = Cache.update!("side-effect", 1, &(&1 + 1))

    v
  end

  @decorate cacheable(match: &(&1 != :x))
  def get_with_match(x) do
    x
  end

  @decorate cacheable(cache: dynamic_cache(Cache, Cache), match: &match_fun/1)
  def get_with_match_fun(x) do
    {:ok, to_string(x)}
  rescue
    _ -> :error
  end

  @decorate cacheable(cache: dynamic_cache(Cache, Cache), match: &match_fun_with_ctx/2)
  def get_with_match_fun_and_ctx(x) do
    {:ok, to_string(x)}
  rescue
    _ -> :error
  end

  @decorate cacheable(key: ttl, match: &match_fun/1)
  def get_with_custom_ttl(ttl) do
    {:ok, %{ttl: ttl}}
  end

  @decorate cacheable()
  def get_with_default_key(x, y) do
    _ = {x, y}

    :ok
  end

  @decorate cacheable(key: {Meta, meta.id})
  def get_meta(%Meta{} = meta) do
    meta
  end

  @decorate cacheable(key: map[:id])
  def get_map(map) do
    map
  end

  @decorate cache_put()
  def update_without_args, do: "hello"

  @decorate cache_put(cache: Cache, key: x)
  def update_fun(x, y \\ nil) do
    with _ when not is_nil(x) <- x,
         _ when not is_nil(y) <- y do
      y
    end
  end

  @decorate cache_put(cache: dynamic_cache(Cache, Cache), keys: [x], opts: [ttl: 1000])
  def update_with_opts(x) do
    x
  end

  @decorate cache_put(cache: dynamic_cache(Cache, Cache), key: x, match: &match_fun/1)
  def update_with_match(x) do
    {:ok, to_string(x)}
  rescue
    _ -> :error
  end

  @decorate cache_put(keys: [x, y], match: &match_fun/1, opts: [ttl: 1000])
  def update_with_multiple_keys(x, y) do
    {:ok, {to_string(x), to_string(y)}}
  rescue
    _ -> :error
  end

  @decorate cache_evict(cache: dynamic_cache(Cache, Cache))
  def evict_without_args, do: "hello"

  @decorate cache_evict(cache: Cache, key: x)
  def evict_fun(x) do
    x
  end

  @decorate cache_evict(keys: [x, y])
  def evict_keys_fun(x, y) do
    {x, y}
  end

  @decorate cache_evict(all_entries: true, before_invocation: true)
  def evict_all_fun(x) do
    x
  end

  @decorate cacheable(key: x)
  def multiple_clauses(x, y \\ 0)

  def multiple_clauses(x, y) when is_integer(x) and is_integer(y) do
    x * y
  end

  def multiple_clauses(x, y) do
    {x, y}
  end

  ## Custom key generation

  @decorate cacheable(key: &:erlang.phash2/1)
  def get_with_keygen(x, y) do
    {x, y}
  end

  @decorate cacheable(key: &:erlang.phash2/1)
  def get_with_keygen2(x, y, z \\ %{})

  def get_with_keygen2(x, y, %{a: {_x1, _y1}}) do
    {x, y}
  end

  def get_with_keygen2(x, y, %{b: _} = z) do
    {x, y, z}
  end

  @decorate cacheable(key: &:erlang.phash2/1)
  def get_with_keygen3(x, _y, _, {_, _}, [_], %{}, %{} = z) do
    {x, z}
  end

  @decorate cacheable(key: &:erlang.list_to_tuple([:a, :b | &1.args]))
  def get_with_keygen4(x, y) do
    {x, y}
  end

  @decorate cache_evict(key: &:erlang.phash2/1)
  def evict_with_keygen(x, y) do
    {x, y}
  end

  @decorate cache_evict(key: &:erlang.list_to_tuple(&1.args))
  def evict_with_keygen2(x, y) do
    {x, y}
  end

  @decorate cache_put(key: &hd(&1.args))
  def put_with_keygen(x, y) do
    x * y
  end

  @decorate cache_put(key: &{:tuple, hd(&1.args)})
  def put_with_keygen2(x, y) do
    x * y
  end

  ## on_error

  @decorate cacheable(cache: YetAnotherCache, key: x, on_error: :raise)
  def get_and_raise_exception(x) do
    x
  end

  @decorate cache_put(cache: YetAnotherCache, key: x, on_error: :raise)
  def update_and_raise_exception(x) do
    x
  end

  @decorate cache_evict(cache: YetAnotherCache, key: x, on_error: :raise)
  def evict_and_raise_exception(x) do
    x
  end

  @decorate cacheable(cache: YetAnotherCache, key: x)
  def get_ignoring_exception(x) do
    x
  end

  @decorate cache_put(cache: YetAnotherCache, key: x)
  def update_ignoring_exception(x) do
    x
  end

  @decorate cache_evict(cache: YetAnotherCache, key: x)
  def evict_ignoring_exception(x) do
    x
  end

  ## Runtime target cache

  @decorate cacheable(cache: &target_cache/1, key: var)
  def get_fn_cache(var) do
    var
  end

  @decorate cache_put(cache: &target_cache/1, key: "foo")
  def update_fn_cache(var) do
    var
  end

  @decorate cache_evict(cache: &target_cache/1, key: "foo")
  def delete_fn_cache(var) do
    var
  end

  ## Key references

  @decorate cacheable(key: name, references: & &1.id)
  def get_with_keyref(name) do
    %{id: "referenced_id", name: name}
  end

  @decorate cacheable(key: name, references: &:erlang.phash2({&1.id, &2.args}))
  def get_with_keyref_fn_ctx(name) do
    %{id: "referenced_id", name: name}
  end

  @decorate cacheable(
              key: name,
              references:
                &keyref(&1.id,
                  cache: YetAnotherCache,
                  ttl: __MODULE__.default_ttl()
                )
            )
  def get_with_keyref_cache(name) do
    %{id: "referenced_id", name: name}
  end

  @decorate cacheable(cache: dynamic_cache(Cache, Cache), key: name, references: attrs.id)
  def get_with_keyref_from_args(name, attrs) do
    %{attrs: attrs, name: name}
  end

  @decorate cacheable(key: name, references: "fixed_id")
  def get_with_fixed_keyref(name) do
    %{id: "fixed_id", name: name}
  end

  @decorate cacheable(key: name, references: & &1.id, match: &(&1[:name] == name))
  def get_with_keyref_and_match(name, value) do
    _ = name

    value
  end

  ## Helpers

  # Custom key-generator function
  def generate_key(arg), do: arg

  def target_cache(arg) do
    _ = send(self(), arg)

    Cache
  end

  def default_ttl, do: 5000

  ## Private Functions

  defp match_fun({:ok, "true"}), do: true
  defp match_fun({:ok, %{ttl: ttl}} = ok), do: {true, ok, [ttl: ttl]}
  defp match_fun({:ok, val}), do: {true, val}
  defp match_fun(_), do: false

  defp match_fun_with_ctx(result, ctx) do
    _ = send(self(), ctx)

    match_fun(result)
  end

  defp set_keys(entries) do
    assert :ok == Cache.put_all(entries)

    Enum.each(entries, fn {k, v} ->
      assert v == Cache.get!(k)
    end)
  end

  defp default_hash(decorator, fun, arity, args) do
    %Nebulex.Caching.Decorators.Context{
      decorator: decorator,
      module: __MODULE__,
      function_name: fun,
      arity: arity,
      args: args
    }
    |> :erlang.phash2()
  end
end
