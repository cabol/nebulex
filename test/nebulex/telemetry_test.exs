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

  @prefix Telemetry.default_event_prefix()
  @start @prefix ++ [:command, :start]
  @stop @prefix ++ [:command, :stop]
  @exception @prefix ++ [:command, :exception]
  @test_adapter_start [:nebulex, :test_adapter, :start]
  @events [@start, @stop, @exception, @test_adapter_start]

  ## Tests

  describe "span/3" do
    setup_with_cache Cache

    test "ok: emits start and stop events" do
      with_telemetry_handler @events, fn ->
        assert Cache.put("foo", "bar") == :ok

        assert_receive {@start, measurements, %{command: :put} = metadata}
        assert measurements[:system_time] |> DateTime.from_unix!(:native)
        assert metadata[:adapter_meta][:cache] == Cache
        assert metadata[:adapter_meta][:name] == Cache
        assert metadata[:args] == ["foo", "bar", :put, :infinity, false, []]
        assert metadata[:telemetry_span_context] |> is_reference()
        assert metadata[:extra_metadata] == %{}

        assert_receive {@stop, measurements, %{command: :put} = metadata}
        assert measurements[:duration] > 0
        assert metadata[:adapter_meta][:cache] == Cache
        assert metadata[:adapter_meta][:name] == Cache
        assert metadata[:args] == ["foo", "bar", :put, :infinity, false, []]
        assert metadata[:result] == {:ok, true}
        assert metadata[:telemetry_span_context] |> is_reference()
        assert metadata[:extra_metadata] == %{}
      end
    end

    test "raise: emits start and exception events" do
      with_telemetry_handler @events, fn ->
        key = {:eval, fn -> raise ArgumentError, "error" end}

        assert_raise ArgumentError, fn ->
          Cache.fetch(key)
        end

        assert_receive {@exception, measurements, %{command: :fetch} = metadata}
        assert measurements[:duration] > 0
        assert metadata[:adapter_meta][:cache] == Cache
        assert metadata[:adapter_meta][:name] == Cache
        assert metadata[:args] == [key, []]
        assert metadata[:kind] == :error
        assert metadata[:reason] == %ArgumentError{message: "error"}
        assert metadata[:stacktrace]
        assert metadata[:telemetry_span_context] |> is_reference()
        assert metadata[:extra_metadata] == %{}
      end
    end

    test "ok: emits start and stop events with custom telemetry_span_context" do
      with_telemetry_handler [@start, @stop], fn ->
        Telemetry.span(@prefix ++ [:command], %{telemetry_span_context: 1}, fn ->
          {"test", %{telemetry_span_context: 1}}
        end)

        assert_receive {@start, measurements, %{telemetry_span_context: 1}}
        assert measurements[:system_time] |> DateTime.from_unix!(:native)

        assert_receive {@stop, measurements, %{telemetry_span_context: 1}}
        assert measurements[:duration] > 0
      end
    end
  end

  describe "span/3 bypassed" do
    setup_with_cache Cache, telemetry: false

    test "telemetry set to false" do
      assert Adapter.lookup_meta(Cache).telemetry == false
    end

    test "ok: does not emit start and stop events" do
      with_telemetry_handler @events, fn ->
        commands = [
          put: ["foo", "bar"],
          put_all: [%{"foo foo" => "bar bar"}],
          get: ["foo"],
          delete: ["unknown"],
          take: ["foo foo"],
          has_key?: ["foo foo"],
          incr: [:counter],
          ttl: ["foo"],
          expire: ["foo", 60_000],
          touch: ["foo"],
          get_all: [[in: ["foo", "foo foo"]]],
          get_all: [],
          stream: [],
          transaction: [fn -> :ok end],
          in_transaction?: [],
          info: []
        ]

        for {command, args} <- commands do
          _ = apply(Cache, command, args)

          refute_received {@start, _, %{command: :command}}
          refute_received {@stop, _, %{command: :command}}
        end

        for {command, args} <- Keyword.drop(commands, [:dump, :load]) do
          _ = apply(Cache, command, args)

          refute_received {@start, _, %{command: :command}}
          refute_received {@stop, _, %{command: :command}}
        end
      end
    end
  end

  describe "span/3 with custom event and metadata" do
    @custom_prefix [:my, :custom, :event]
    @custom_start @custom_prefix ++ [:start]
    @custom_stop @custom_prefix ++ [:stop]
    @custom_exception @custom_prefix ++ [:exception]
    @custom_events [@custom_start, @custom_stop, @custom_exception]

    @custom_opts [
      telemetry_event: @custom_prefix,
      telemetry_metadata: %{foo: "bar"}
    ]

    setup_with_cache Cache

    test "ok: emits start and stop events" do
      with_telemetry_handler @custom_events, fn ->
        :ok = Cache.put("foo", "bar", @custom_opts)

        assert_receive {@custom_start, measurements, %{command: :put} = metadata}
        assert measurements[:system_time] |> DateTime.from_unix!(:native)
        assert metadata[:adapter_meta][:cache] == Cache
        assert metadata[:adapter_meta][:name] == Cache
        assert metadata[:args] == ["foo", "bar", :put, :infinity, false, @custom_opts]
        assert metadata[:telemetry_span_context] |> is_reference()
        assert metadata[:extra_metadata] == %{foo: "bar"}

        assert_receive {@custom_stop, measurements, %{command: :put} = metadata}
        assert measurements[:duration] > 0
        assert metadata[:adapter_meta][:cache] == Cache
        assert metadata[:adapter_meta][:name] == Cache
        assert metadata[:args] == ["foo", "bar", :put, :infinity, false, @custom_opts]
        assert metadata[:result] == {:ok, true}
        assert metadata[:telemetry_span_context] |> is_reference()
        assert metadata[:extra_metadata] == %{foo: "bar"}
      end
    end

    test "raise: emits start and exception events" do
      with_telemetry_handler @custom_events, fn ->
        key = {:eval, fn -> raise ArgumentError, "error" end}

        assert_raise ArgumentError, fn ->
          Cache.fetch(key, @custom_opts)
        end

        assert_receive {@custom_exception, measurements, %{command: :fetch} = metadata}
        assert measurements[:duration] > 0
        assert metadata[:adapter_meta][:cache] == Cache
        assert metadata[:adapter_meta][:name] == Cache
        assert metadata[:args] == [key, @custom_opts]
        assert metadata[:kind] == :error
        assert metadata[:reason] == %ArgumentError{message: "error"}
        assert metadata[:stacktrace]
        assert metadata[:telemetry_span_context] |> is_reference()
        assert metadata[:extra_metadata] == %{foo: "bar"}
      end
    end

    test "error: invalid telemetry_event" do
      assert_raise NimbleOptions.ValidationError, ~r"invalid value for :telemetry_event", fn ->
        Cache.fetch(:invalid, telemetry_event: :invalid)
      end
    end

    test "error: invalid telemetry_metadata" do
      assert_raise NimbleOptions.ValidationError, ~r"invalid value for :telemetry_metadata", fn ->
        Cache.fetch(:invalid, telemetry_metadata: :invalid)
      end
    end
  end
end
