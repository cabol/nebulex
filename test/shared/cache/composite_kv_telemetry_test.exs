defmodule Nebulex.Cache.CompositeKVTelemetryTest do
  @moduledoc """
  Covers the Telemetry command events emitted by the composite KV operations.

  Since composite operations are adapter commands, each one emits its own
  command span. The assertions on the primitive `fetch`, `put`, and `delete`
  spans describe the default implementation provided by
  `use Nebulex.Adapter.CompositeKV`, so an adapter overriding the callbacks
  should exclude this suite.
  """

  import Nebulex.CacheCase

  deftests do
    import Nebulex.CacheCase, only: [with_telemetry_handler: 2]

    describe "composite KV telemetry" do
      setup %{cache: cache} do
        # Scoped to the function so it cannot clash with the aliases of the
        # test module this suite is injected into.
        alias Nebulex.Adapter

        prefix =
          cache.get_dynamic_cache()
          |> Adapter.lookup_meta()
          |> Map.fetch!(:telemetry_prefix)

        {:ok, start: prefix ++ [:command, :start], stop: prefix ++ [:command, :stop]}
      end

      test "get_and_update/3 emits the composite and primitive spans", ctx do
        %{cache: cache, start: start, stop: stop} = ctx
        fun = &cache.get_and_update_fun/1

        with_telemetry_handler [start, stop], fn ->
          assert cache.get_and_update(:counter, fun) == {:ok, {nil, 1}}

          assert_receive {^start, _, %{command: :get_and_update} = meta}
          assert meta[:args] == [:counter, fun, :infinity, false, []]

          assert_receive {^stop, _, %{command: :get_and_update} = meta}
          assert meta[:result] == {:ok, {nil, 1}}

          assert_receive {^stop, _, %{command: :fetch, args: [:counter, []]}}

          assert_receive {^stop, _,
                          %{command: :put, args: [:counter, 1, :put, :infinity, false, []]}}
        end
      end

      test "get_and_update/3 emits a delete span when the function returns :pop", ctx do
        %{cache: cache, start: start, stop: stop} = ctx

        :ok = cache.put(:counter, 1)

        with_telemetry_handler [start, stop], fn ->
          assert cache.get_and_update(:counter, fn _ -> :pop end) == {:ok, {1, nil}}

          assert_receive {^start, _, %{command: :delete, args: [:counter, []]}}
          assert_receive {^stop, _, %{command: :delete, args: [:counter, []]}}

          # The missing key must not be deleted again
          assert cache.get_and_update(:counter, fn _ -> :pop end) == {:ok, {nil, nil}}

          refute_received {^start, _, %{command: :delete}}
        end
      end

      test "update/4 emits the composite and primitive spans", ctx do
        %{cache: cache, start: start, stop: stop} = ctx
        fun = &Integer.to_string/1

        with_telemetry_handler [start, stop], fn ->
          assert cache.update(:counter, 1, fun) == {:ok, 1}

          assert_receive {^stop, _, %{command: :update} = meta}
          assert meta[:args] == [:counter, 1, fun, :infinity, false, []]
          assert meta[:result] == {:ok, 1}

          assert_receive {^stop, _, %{command: :fetch, args: [:counter, []]}}

          assert_receive {^stop, _,
                          %{command: :put, args: [:counter, 1, :put, :infinity, false, []]}}
        end
      end

      test "fetch_or_store/3 emits the composite and primitive spans", ctx do
        %{cache: cache, start: start, stop: stop} = ctx
        fun = &cache.fetch_or_store_fun/0

        with_telemetry_handler [start, stop], fn ->
          assert cache.fetch_or_store(:key, fun) == {:ok, "value"}

          assert_receive {^stop, _, %{command: :fetch_or_store} = meta}
          assert meta[:args] == [:key, fun, :infinity, false, []]
          assert meta[:result] == {:ok, "value"}

          assert_receive {^stop, _, %{command: :fetch, args: [:key, []]}}

          assert_receive {^stop, _,
                          %{command: :put, args: [:key, "value", :put, :infinity, false, []]}}
        end
      end

      test "fetch_or_store/3 emits no write span when the function returns an error", ctx do
        %{cache: cache, start: start, stop: stop} = ctx

        with_telemetry_handler [start, stop], fn ->
          assert {:error, %Nebulex.Error{}} =
                   cache.fetch_or_store(:key, &cache.fetch_or_store_error_fun/0)

          assert_receive {^stop, _, %{command: :fetch_or_store, result: {:error, _}}}
          refute_received {^start, _, %{command: :put}}
        end
      end

      test "get_or_store/3 emits the composite and primitive spans", ctx do
        %{cache: cache, start: start, stop: stop} = ctx
        fun = &cache.get_or_store_fun/0

        with_telemetry_handler [start, stop], fn ->
          assert cache.get_or_store(:key, fun) == {:ok, "value"}

          assert_receive {^stop, _, %{command: :get_or_store} = meta}
          assert meta[:args] == [:key, fun, :infinity, false, []]
          assert meta[:result] == {:ok, "value"}

          assert_receive {^stop, _, %{command: :fetch, args: [:key, []]}}

          assert_receive {^stop, _,
                          %{command: :put, args: [:key, "value", :put, :infinity, false, []]}}
        end
      end

      test "forwards the :ttl and :keep_ttl options as arguments", ctx do
        %{cache: cache, start: start, stop: stop} = ctx
        fun = &cache.get_and_update_fun/1
        ttl = :timer.seconds(10)

        with_telemetry_handler [start, stop], fn ->
          assert cache.get_and_update!(:counter, fun, ttl: ttl, keep_ttl: true) == {nil, 1}

          assert_receive {^stop, _, %{command: :get_and_update} = meta}
          assert meta[:args] == [:counter, fun, ttl, true, []]

          assert_receive {^stop, _, %{command: :put, args: [:counter, 1, :put, ^ttl, true, []]}}
        end
      end

      test "propagates :telemetry_metadata to the composite and primitive spans", ctx do
        %{cache: cache, start: start, stop: stop} = ctx
        opts = [telemetry_metadata: %{foo: "bar"}]

        with_telemetry_handler [start, stop], fn ->
          assert cache.get_or_store(:key, &cache.get_or_store_fun/0, opts) == {:ok, "value"}

          assert_receive {^stop, _, %{command: :get_or_store, extra_metadata: %{foo: "bar"}}}
          assert_receive {^stop, _, %{command: :fetch, extra_metadata: %{foo: "bar"}}}
          assert_receive {^stop, _, %{command: :put, extra_metadata: %{foo: "bar"}}}
        end
      end

      test "honors telemetry: false for the composite and primitive spans", ctx do
        %{cache: cache, start: start, stop: stop} = ctx

        with_telemetry_handler [start, stop], fn ->
          assert cache.get_and_update!(:counter, &cache.get_and_update_fun/1, telemetry: false) ==
                   {nil, 1}

          refute_received {^start, _, _}
          refute_received {^stop, _, _}
        end
      end

      test "propagates :telemetry_event to the composite and primitive spans", ctx do
        %{cache: cache} = ctx
        event = [:nebulex, :composite_kv, :custom]
        stop = event ++ [:stop]

        with_telemetry_handler [stop], fn ->
          assert cache.get_and_update!(:counter, &cache.get_and_update_fun/1,
                   telemetry_event: event
                 ) == {nil, 1}

          assert_receive {^stop, _, %{command: :fetch}}
          assert_receive {^stop, _, %{command: :put}}
          assert_receive {^stop, _, %{command: :get_and_update}}
        end
      end
    end
  end
end
