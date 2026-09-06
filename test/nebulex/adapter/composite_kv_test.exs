defmodule Nebulex.Adapter.CompositeKVTest do
  use ExUnit.Case, async: true

  import Nebulex.CacheCase

  alias Nebulex.Adapter.CompositeKV

  ## Test adapters

  defmodule KVAdapter do
    @moduledoc false

    # Injects the `Nebulex.Adapter` and `Nebulex.Adapter.KV` behaviours,
    # delegating every callback to the adapter given in the `:to` option.
    defmacro __using__(opts) do
      target = Keyword.fetch!(opts, :to)

      quote do
        @behaviour Nebulex.Adapter
        @behaviour Nebulex.Adapter.KV

        @impl true
        defmacro __before_compile__(_env), do: :ok

        @impl true
        defdelegate init(opts), to: unquote(target)

        @impl true
        defdelegate fetch(adapter_meta, key, opts), to: unquote(target)

        @impl true
        defdelegate put(adapter_meta, key, value, on_write, ttl, keep_ttl?, opts),
          to: unquote(target)

        @impl true
        defdelegate put_all(adapter_meta, entries, on_write, ttl, opts), to: unquote(target)

        @impl true
        defdelegate delete(adapter_meta, key, opts), to: unquote(target)

        @impl true
        defdelegate take(adapter_meta, key, opts), to: unquote(target)

        @impl true
        defdelegate has_key?(adapter_meta, key, opts), to: unquote(target)

        @impl true
        defdelegate ttl(adapter_meta, key, opts), to: unquote(target)

        @impl true
        defdelegate expire(adapter_meta, key, ttl, opts), to: unquote(target)

        @impl true
        defdelegate touch(adapter_meta, key, opts), to: unquote(target)

        @impl true
        defdelegate update_counter(adapter_meta, key, amount, default, ttl, opts),
          to: unquote(target)
      end
    end
  end

  defmodule LegacyAdapter do
    @moduledoc false

    # KV adapter that does NOT implement `Nebulex.Adapter.CompositeKV`
    use KVAdapter, to: Nebulex.TestAdapter
  end

  defmodule OverridingAdapter do
    @moduledoc false

    use KVAdapter, to: Nebulex.TestAdapter
    use Nebulex.Adapter.CompositeKV

    @impl true
    def get_or_store(_adapter_meta, key, _fun, _ttl, _keep_ttl?, _opts) do
      {:ok, {:overridden, key}}
    end
  end

  defmodule ErrorAdapter do
    @moduledoc false

    use KVAdapter, to: Nebulex.FakeAdapter
    use Nebulex.Adapter.CompositeKV
  end

  ## Test caches

  defmodule LegacyCache do
    @moduledoc false

    use Nebulex.Cache,
      otp_app: :nebulex,
      adapter: LegacyAdapter
  end

  defmodule OverridingCache do
    @moduledoc false

    use Nebulex.Cache,
      otp_app: :nebulex,
      adapter: OverridingAdapter
  end

  defmodule ErrorCache do
    @moduledoc false

    use Nebulex.Cache,
      otp_app: :nebulex,
      adapter: ErrorAdapter
  end

  ## Shared constants

  # Key used by the composite operations under test
  @key "composite"

  # Value stored by the fallback functions
  @value "value"

  # TTL used to verify the `:ttl` option is honored
  @ttl :timer.seconds(1)

  # Error returned by every `Nebulex.FakeAdapter` command
  @error {:error, %Nebulex.Error{reason: :error}}

  # Composite KV callbacks with their arities
  @callbacks [get_and_update: 6, update: 7, fetch_or_store: 6, get_or_store: 6]

  # Composite KV cache functions with their arities
  @cache_functions [
    get_and_update: 3,
    get_and_update!: 3,
    update: 4,
    update!: 4,
    fetch_or_store: 3,
    fetch_or_store!: 3,
    get_or_store: 3,
    get_or_store!: 3
  ]

  # Telemetry prefix isolating the spans emitted by the caches under test
  @telemetry_prefix [:nebulex, :composite_kv_test]
  @start @telemetry_prefix ++ [:command, :start]
  @stop @telemetry_prefix ++ [:command, :stop]
  @events [@start, @stop]

  ## Tests

  describe "adapter without the behaviour" do
    test "the cache does not expose the composite functions" do
      for {fun, arity} <- @cache_functions do
        refute function_exported?(LegacyCache, fun, arity)
      end
    end
  end

  describe "default implementation (adapter using the behaviour)" do
    setup_with_dynamic_cache Nebulex.TestCache.Cache, __MODULE__,
      telemetry_prefix: @telemetry_prefix

    test "get_and_update/3 emits the composite and primitive spans", %{cache: cache} do
      fun = &get_and_update_fun/1

      with_telemetry_handler @events, fn ->
        assert cache.get_and_update(@key, fun) == {:ok, {nil, 1}}

        assert_composite_span(:get_and_update, [@key, fun, :infinity, false, []], {:ok, {nil, 1}})

        assert_receive {@start, _, %{command: :fetch, args: [@key, []]}}
        assert_receive {@stop, _, %{command: :fetch, args: [@key, []]}}
        assert_receive {@start, _, %{command: :put, args: [@key, 1, :put, :infinity, false, []]}}
        assert_receive {@stop, _, %{command: :put, args: [@key, 1, :put, :infinity, false, []]}}
      end
    end

    test "get_and_update/3 does not write when the function returns {get, nil}",
         %{cache: cache} do
      :ok = cache.put(@key, 1)

      with_telemetry_handler @events, fn ->
        assert cache.get_and_update!(@key, &{&1, nil}) == {1, 1}

        assert_receive {@stop, _, %{command: :get_and_update, result: {:ok, {1, 1}}}}
        assert_receive {@stop, _, %{command: :fetch}}
        refute_received {@start, _, %{command: :put}}
      end
    end

    test "get_and_update/3 deletes the key when the function returns :pop", %{cache: cache} do
      :ok = cache.put(@key, 1)

      with_telemetry_handler @events, fn ->
        assert cache.get_and_update(@key, fn _ -> :pop end) == {:ok, {1, nil}}
        assert cache.get_and_update(@key, fn _ -> :pop end) == {:ok, {nil, nil}}

        assert_receive {@stop, _, %{command: :get_and_update, result: {:ok, {1, nil}}}}
        assert_receive {@start, _, %{command: :delete, args: [@key, []]}}
        assert_receive {@stop, _, %{command: :delete, args: [@key, []]}}
        assert_receive {@stop, _, %{command: :get_and_update, result: {:ok, {nil, nil}}}}

        # The missing key must not be deleted again
        refute_received {@start, _, %{command: :delete}}
      end
    end

    test "update/4 emits the composite and primitive spans", %{cache: cache} do
      fun = &(&1 * 2)

      with_telemetry_handler @events, fn ->
        assert cache.update(@key, 1, fun) == {:ok, 1}
        assert cache.update!(@key, 1, fun) == 2

        assert_composite_span(:update, [@key, 1, fun, :infinity, false, []], {:ok, 1})
        assert_composite_span(:update, [@key, 1, fun, :infinity, false, []], {:ok, 2})

        assert_receive {@stop, _, %{command: :fetch, args: [@key, []]}}
        assert_receive {@stop, _, %{command: :put, args: [@key, 1, :put, :infinity, false, []]}}
        assert_receive {@stop, _, %{command: :put, args: [@key, 2, :put, :infinity, false, []]}}
      end
    end

    test "fetch_or_store/3 emits the composite and primitive spans", %{cache: cache} do
      fun = fn -> {:ok, @value} end

      with_telemetry_handler @events, fn ->
        assert cache.fetch_or_store(@key, fun) == {:ok, @value}
        assert cache.fetch_or_store!(@key, &must_not_be_called/0) == @value

        assert_composite_span(:fetch_or_store, [@key, fun, :infinity, false, []], {:ok, @value})

        assert_receive {@stop, _, %{command: :fetch, args: [@key, []]}}

        assert_receive {@stop, _,
                        %{command: :put, args: [@key, @value, :put, :infinity, false, []]}}
      end
    end

    test "fetch_or_store/3 does not write when the function returns an error", %{cache: cache} do
      with_telemetry_handler @events, fn ->
        assert {:error, %Nebulex.Error{reason: :not_found, metadata: metadata}} =
                 cache.fetch_or_store(@key, fn -> {:error, :not_found} end)

        assert Keyword.fetch!(metadata, :command) == :fetch_or_store
        assert Keyword.fetch!(metadata, :key) == @key
        assert cache.has_key?(@key) == {:ok, false}

        assert_receive {@stop, _, %{command: :fetch_or_store, result: {:error, _}}}
        refute_received {@start, _, %{command: :put}}
      end
    end

    test "get_or_store/3 emits the composite and primitive spans", %{cache: cache} do
      fun = fn -> @value end

      with_telemetry_handler @events, fn ->
        assert cache.get_or_store(@key, fun) == {:ok, @value}
        assert cache.get_or_store!(@key, &must_not_be_called/0) == @value

        assert_composite_span(:get_or_store, [@key, fun, :infinity, false, []], {:ok, @value})

        assert_receive {@stop, _, %{command: :fetch, args: [@key, []]}}

        assert_receive {@stop, _,
                        %{command: :put, args: [@key, @value, :put, :infinity, false, []]}}
      end
    end

    test "pops the :ttl and :keep_ttl options and forwards them as arguments", %{cache: cache} do
      fun = &get_and_update_fun/1

      with_telemetry_handler @events, fn ->
        assert cache.get_and_update!(@key, fun, ttl: @ttl, keep_ttl: true) == {nil, 1}

        assert_composite_span(:get_and_update, [@key, fun, @ttl, true, []], {:ok, {nil, 1}})
        assert_receive {@stop, _, %{command: :put, args: [@key, 1, :put, @ttl, true, []]}}
      end

      assert_expires(cache)
    end

    test "includes the :telemetry_metadata option in the composite span", %{cache: cache} do
      fun = fn -> @value end

      with_telemetry_handler @events, fn ->
        assert cache.get_or_store(@key, fun, telemetry_metadata: %{foo: "bar"}) == {:ok, @value}

        assert_receive {@start, _, %{command: :get_or_store} = metadata}
        assert metadata[:args] == [@key, fun, :infinity, false, []]
        assert metadata[:extra_metadata] == %{foo: "bar"}

        assert_receive {@stop, _, %{command: :get_or_store} = metadata}
        assert metadata[:args] == [@key, fun, :infinity, false, []]
        assert metadata[:extra_metadata] == %{foo: "bar"}
      end
    end
  end

  describe "overriding a callback" do
    setup_with_cache OverridingCache

    test "get_or_store/3 uses the adapter override", %{cache: cache} do
      assert cache.get_or_store(@key, &must_not_be_called/0) == {:ok, {:overridden, @key}}
      assert cache.get_or_store!(@key, &must_not_be_called/0) == {:overridden, @key}
      assert cache.has_key?(@key) == {:ok, false}
    end

    test "the other callbacks keep the default implementation", %{cache: cache} do
      assert cache.get_and_update!(@key, &get_and_update_fun/1) == {nil, 1}
      assert cache.update!(@key, 1, &(&1 * 2)) == 2
      assert cache.fetch_or_store!(@key, &must_not_be_called/0) == 2
      assert cache.fetch!(@key) == 2
    end
  end

  describe "errors" do
    setup_with_cache ErrorCache

    test "returns the adapter error", %{cache: cache} do
      assert cache.get_and_update(@key, &get_and_update_fun/1) == @error
      assert cache.update(@key, 1, &(&1 * 2)) == @error
      assert cache.fetch_or_store(@key, fn -> {:ok, @value} end) == @error
      assert cache.get_or_store(@key, fn -> @value end) == @error
    end

    test "bang functions raise the adapter error", %{cache: cache} do
      ops = [
        fn -> cache.get_and_update!(@key, &get_and_update_fun/1) end,
        fn -> cache.update!(@key, 1, &(&1 * 2)) end,
        fn -> cache.fetch_or_store!(@key, fn -> {:ok, @value} end) end,
        fn -> cache.get_or_store!(@key, fn -> @value end) end
      ]

      for op <- ops do
        assert_raise Nebulex.Error, ~r"command failed with reason: :error", op
      end
    end
  end

  describe "behaviour" do
    test "defines the composite KV callbacks" do
      callbacks = CompositeKV.behaviour_info(:callbacks)

      assert Enum.sort(callbacks) == Enum.sort(@callbacks)
    end

    test "use attaches the behaviour to the adapter" do
      assert CompositeKV in behaviours(OverridingAdapter)
      refute CompositeKV in behaviours(LegacyAdapter)
    end
  end

  ## Fixtures

  defp get_and_update_fun(nil), do: {nil, 1}
  defp get_and_update_fun(current), do: {current, current * 2}

  defp must_not_be_called do
    flunk("the function must not be called")
  end

  ## Helpers

  defp assert_expires(cache) do
    assert cache.has_key?(@key) == {:ok, true}

    _ = t_sleep(@ttl + 100)

    assert cache.has_key?(@key) == {:ok, false}
  end

  defp assert_composite_span(command, args, result) do
    assert_receive {@start, measurements, %{command: ^command, args: ^args} = metadata}
    assert measurements[:system_time] |> DateTime.from_unix!(:native)
    assert metadata[:telemetry_span_context] |> is_reference()
    assert metadata[:extra_metadata] == %{}

    assert_receive {@stop, measurements, %{command: ^command, args: ^args} = metadata}
    assert measurements[:duration] > 0
    assert metadata[:result] == result
    assert metadata[:telemetry_span_context] |> is_reference()
    assert metadata[:extra_metadata] == %{}
  end

  defp behaviours(module) do
    module.__info__(:attributes)
    |> Keyword.get_values(:behaviour)
    |> List.flatten()
  end
end
