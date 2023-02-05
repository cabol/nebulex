defmodule Nebulex.TelemetryTest do
  use ExUnit.Case, async: true

  import Nebulex.CacheCase

  alias Nebulex.{Adapter, Telemetry}

  ## Shared cache

  defmodule Cache do
    use Nebulex.Cache,
      otp_app: :nebulex,
      adapter: Nebulex.TestAdapter
  end

  ## Shared constants

  @prefix [:nebulex, :telemetry_test, :cache]
  @start @prefix ++ [:command, :start]
  @stop @prefix ++ [:command, :stop]
  @exception @prefix ++ [:command, :exception]
  @test_adapter_start [:nebulex, :test_adapter, :start]
  @events [@start, @stop, @exception, @test_adapter_start]

  ## Tests

  describe "span/3" do
    setup_with_cache Cache

    test "ok: emits start and stop events" do
      with_telemetry_handler(__MODULE__, @events, fn ->
        assert Cache.put("foo", "bar") == :ok

        assert_receive {@start, measurements, %{function_name: :put} = metadata}
        assert measurements[:system_time] |> DateTime.from_unix!(:native)
        assert metadata[:adapter_meta][:cache] == Cache
        assert metadata[:args] == ["foo", "bar", :infinity, :put, []]
        assert metadata[:telemetry_span_context] |> is_reference()

        assert_receive {@stop, measurements, %{function_name: :put} = metadata}
        assert measurements[:duration] > 0
        assert metadata[:adapter_meta][:cache] == Cache
        assert metadata[:args] == ["foo", "bar", :infinity, :put, []]
        assert metadata[:result] == {:ok, true}
        assert metadata[:telemetry_span_context] |> is_reference()
      end)
    end

    test "raise: emits start and exception events" do
      with_telemetry_handler(__MODULE__, @events, fn ->
        key = {:eval, fn -> raise ArgumentError, "error" end}

        assert_raise ArgumentError, fn ->
          Cache.fetch(key)
        end

        assert_receive {@exception, measurements, %{function_name: :fetch} = metadata}
        assert measurements[:duration] > 0
        assert metadata[:adapter_meta][:cache] == Cache
        assert metadata[:args] == [key, []]
        assert metadata[:kind] == :error
        assert metadata[:reason] == %ArgumentError{message: "error"}
        assert metadata[:stacktrace]
        assert metadata[:telemetry_span_context] |> is_reference()
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
    setup_with_cache Cache, telemetry: false

    test "telemetry set to false" do
      Adapter.with_meta(Cache, fn meta ->
        assert meta.telemetry == false
      end)
    end

    test "ok: does not emit start and stop events" do
      with_telemetry_handler(__MODULE__, @events, fn ->
        commands = [
          put: ["foo", "bar"],
          put_all: [%{"foo foo" => "bar bar"}],
          get: ["foo"],
          get_all: [["foo", "foo foo"]],
          delete: ["unknown"],
          take: ["foo foo"],
          has_key?: ["foo foo"],
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
          _ = apply(Cache, command, args)

          refute_received {@start, _, %{function_name: :command}}
          refute_received {@stop, _, %{function_name: :command}}
        end

        for {command, args} <- Keyword.drop(commands, [:dump, :load]) do
          _ = apply(Cache, command, args)

          refute_received {@start, _, %{function_name: :command}}
          refute_received {@stop, _, %{function_name: :command}}
        end
      end)
    end
  end
end
