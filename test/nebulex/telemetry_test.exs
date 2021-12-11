defmodule Nebulex.TelemetryTest do
  use ExUnit.Case, async: true

  import Nebulex.CacheCase

  alias Nebulex.{Adapter, Telemetry}

  ## Shared cache

  defmodule Cache do
    use Nebulex.Cache,
      otp_app: :nebulex,
      adapter: Nebulex.Adapters.Multilevel

    defmodule L1 do
      use Nebulex.Cache,
        otp_app: :nebulex,
        adapter: Nebulex.Adapters.Local
    end

    defmodule L2 do
      use Nebulex.Cache,
        otp_app: :nebulex,
        adapter: Nebulex.Adapters.Replicated
    end

    defmodule L3 do
      use Nebulex.Cache,
        otp_app: :nebulex,
        adapter: Nebulex.Adapters.Partitioned
    end
  end

  ## Shared constants

  @prefix [:nebulex, :telemetry_test, :cache]

  @start @prefix ++ [:command, :start]
  @stop @prefix ++ [:command, :stop]

  @start_events [
    @prefix ++ [:command, :start],
    @prefix ++ [:l1, :command, :start],
    @prefix ++ [:l2, :command, :start],
    @prefix ++ [:l2, :primary, :command, :start],
    @prefix ++ [:l3, :command, :start],
    @prefix ++ [:l3, :primary, :command, :start]
  ]

  @stop_events [
    @prefix ++ [:command, :stop],
    @prefix ++ [:l1, :command, :stop],
    @prefix ++ [:l2, :command, :stop],
    @prefix ++ [:l2, :primary, :command, :stop],
    @prefix ++ [:l3, :command, :stop],
    @prefix ++ [:l3, :primary, :command, :stop]
  ]

  @exception_events [
    @prefix ++ [:command, :exception],
    @prefix ++ [:l1, :command, :exception],
    @prefix ++ [:l2, :command, :exception],
    @prefix ++ [:l2, :primary, :command, :exception],
    @prefix ++ [:l3, :command, :stop],
    @prefix ++ [:l3, :primary, :command, :exception]
  ]

  @caches [Cache, Cache.L1, Cache.L2, Cache.L2.Primary, Cache.L3, Cache.L3.Primary]

  @events Enum.zip([@caches, @start_events, @stop_events])

  @config [
    model: :inclusive,
    levels: [
      {Cache.L1, gc_interval: :timer.hours(1)},
      {Cache.L2, primary: [gc_interval: :timer.hours(1)]},
      {Cache.L3, primary: [gc_interval: :timer.hours(1)]}
    ]
  ]

  ## Tests

  describe "span/3" do
    setup_with_cache(Cache, @config)

    test "ok: emits start and stop events" do
      with_telemetry_handler(__MODULE__, @start_events ++ @stop_events, fn ->
        assert Cache.put("foo", "bar") == :ok

        for {cache, start, stop} <- @events do
          assert_receive {^start, measurements, %{function_name: :put} = metadata}
          assert measurements[:system_time] |> DateTime.from_unix!(:native)
          assert metadata[:adapter_meta][:cache] == cache
          assert metadata[:args] == ["foo", "bar", :infinity, :put, []]
          assert metadata[:telemetry_span_context] |> is_reference()

          assert_receive {^stop, measurements, %{function_name: :put} = metadata}
          assert measurements[:duration] > 0
          assert metadata[:adapter_meta][:cache] == cache
          assert metadata[:args] == ["foo", "bar", :infinity, :put, []]
          assert metadata[:result] == {:ok, true}
          assert metadata[:telemetry_span_context] |> is_reference()
        end
      end)
    end

    test "raise: emits start and exception events" do
      with_telemetry_handler(__MODULE__, @exception_events, fn ->
        Adapter.with_meta(Cache.L3.Primary, fn _, meta ->
          true = :ets.delete(meta.meta_tab)
        end)

        assert_raise ArgumentError, fn ->
          Cache.get("foo")
        end

        ex_events = [
          @prefix ++ [:command, :exception],
          @prefix ++ [:l3, :command, :exception],
          @prefix ++ [:l3, :primary, :command, :exception]
        ]

        for {cache, exception} <- ex_events do
          assert_receive {^exception, measurements, %{function_name: :get} = metadata}
          assert measurements[:duration] > 0
          assert metadata[:adapter_meta][:cache] == cache
          assert metadata[:args] == ["foo", []]
          assert metadata[:kind] == :error
          assert metadata[:reason] == :badarg
          assert metadata[:stacktrace]
          assert metadata[:telemetry_span_context] |> is_reference()
        end
      end)
    end

    test "ok: emits start and stop events with custom telemetry_span_context" do
      with_telemetry_handler(__MODULE__, [@start, @stop], fn ->
        event_prefix = [:nebulex, :telemetry_test, :cache, :command]

        Telemetry.span(event_prefix, %{telemetry_span_context: 1}, fn ->
          {"test", %{telemetry_span_context: 1}}
        end)

        assert_receive {@start, measurements, metadata}
        assert measurements[:system_time] |> DateTime.from_unix!(:native)
        assert metadata[:telemetry_span_context] == 1

        assert_receive {@stop, measurements, metadata}
        assert measurements[:duration] > 0
        assert metadata[:telemetry_span_context] == 1
      end)
    end
  end

  describe "span/3 bypassed" do
    setup_with_cache(Cache, Keyword.put(@config, :telemetry, false))

    test "telemetry set to false" do
      for cache <- @caches do
        Adapter.with_meta(cache, fn _, meta ->
          assert meta.telemetry == false
        end)
      end
    end

    test "ok: does not emit start and stop events" do
      with_telemetry_handler(__MODULE__, @start_events ++ @stop_events, fn ->
        commands = [
          put: ["foo", "bar"],
          put_all: [%{"foo foo" => "bar bar"}],
          get: ["foo"],
          get_all: [["foo", "foo foo"]],
          delete: ["unknown"],
          take: ["foo foo"],
          exists?: ["foo foo"],
          incr: [:counter],
          ttl: ["foo"],
          expire: ["foo", 60_000],
          touch: ["foo"],
          all: [],
          stream: [],
          transaction: [fn -> :ok end],
          in_transaction?: [],
          dump: ["/invalid/path"],
          load: ["wrong_file"],
          stats: []
        ]

        for {command, args} <- commands do
          _ = apply(Cache.L1, command, args)
          _ = apply(Cache.L2, command, args)
          _ = apply(Cache.L3, command, args)

          for {_cache, start, stop} <- @events do
            refute_received {^start, _, %{function_name: :command}}
            refute_received {^stop, _, %{function_name: :command}}
          end
        end

        for {command, args} <- Keyword.drop(commands, [:dump, :load]) do
          _ = apply(Cache, command, args)

          for {_cache, start, stop} <- @events do
            refute_received {^start, _, %{function_name: :command}}
            refute_received {^stop, _, %{function_name: :command}}
          end
        end
      end)
    end
  end
end
