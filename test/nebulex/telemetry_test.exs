defmodule Nebulex.TelemetryTest do
  use ExUnit.Case, async: true

  import Nebulex.Adapter
  import Nebulex.CacheCase

  alias Nebulex.Telemetry

  defmodule Cache do
    use Nebulex.Cache,
      otp_app: :nebulex,
      adapter: Nebulex.Adapters.Local
  end

  describe "span/3" do
    @event_prefix [:nebulex, :telemetry_test, :cache, :command]
    @start @event_prefix ++ [:start]
    @stop @event_prefix ++ [:stop]
    @exception @event_prefix ++ [:exception]

    setup do
      {:ok, pid} = Cache.start_link()
      {adapter, adapter_meta} = Nebulex.Cache.Registry.lookup(pid)

      on_exit(fn ->
        :ok = Process.sleep(100)
        if Process.alive?(pid), do: Cache.stop()
      end)

      {:ok, adapter: adapter, adapter_meta: adapter_meta}
    end

    test "ok: emits start and stop events", %{adapter_meta: adapter_meta} do
      with_telemetry_handler(__MODULE__, [@start, @stop], fn ->
        assert with_span(adapter_meta, :test, fn -> "test" end) == "test"

        assert_receive {@start, measurements, metadata}
        assert measurements[:system_time] |> DateTime.from_unix!(:native)
        assert metadata[:action] == :test
        assert metadata[:cache] == Cache
        assert metadata[:telemetry_span_context] |> is_reference()

        assert_receive {@stop, measurements, metadata}
        assert measurements[:duration] > 0
        assert metadata[:action] == :test
        assert metadata[:cache] == Cache
        assert metadata[:result] == "test"
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

    test "raise: emits start and exception events", %{adapter_meta: adapter_meta} do
      with_telemetry_handler(__MODULE__, [@start, @exception], fn ->
        assert_raise RuntimeError, fn ->
          with_span(adapter_meta, :test, fn -> raise RuntimeError, "test" end)
        end

        assert_receive {@start, measurements, metadata}
        assert measurements[:system_time] |> DateTime.from_unix!(:native)
        assert metadata[:action] == :test
        assert metadata[:cache] == Cache
        assert metadata[:telemetry_span_context] |> is_reference()

        assert_receive {@exception, measurements, metadata}
        assert measurements[:duration] > 0
        assert metadata[:action] == :test
        assert metadata[:cache] == Cache
        assert metadata[:kind] == :error
        assert metadata[:reason] == %RuntimeError{message: "test"}
        assert metadata[:stacktrace]
        assert metadata[:telemetry_span_context] |> is_reference()
      end)
    end

    test "exit: emits start and exception events", %{adapter_meta: adapter_meta} do
      with_telemetry_handler(__MODULE__, [@start, @exception], fn ->
        assert catch_exit(with_span(adapter_meta, :test, fn -> exit("test") end)) == "test"

        assert_receive {@start, measurements, metadata}
        assert measurements[:system_time] |> DateTime.from_unix!(:native)
        assert metadata[:action] == :test
        assert metadata[:cache] == Cache
        assert metadata[:telemetry_span_context] |> is_reference()

        assert_receive {@exception, measurements, metadata}
        assert measurements[:duration] > 0
        assert metadata[:action] == :test
        assert metadata[:cache] == Cache
        assert metadata[:kind] == :exit
        assert metadata[:reason] == "test"
        assert metadata[:stacktrace]
        assert metadata[:telemetry_span_context] |> is_reference()
      end)
    end
  end

  describe "span/3 bypassed" do
    setup do
      {:ok, pid} = Cache.start_link(telemetry_prefix: nil)
      {adapter, adapter_meta} = Nebulex.Cache.Registry.lookup(pid)

      on_exit(fn ->
        :ok = Process.sleep(100)
        if Process.alive?(pid), do: Cache.stop()
      end)

      {:ok, adapter: adapter, adapter_meta: adapter_meta}
    end

    test "ok: does not emit start and stop events", %{adapter_meta: adapter_meta} do
      with_telemetry_handler(__MODULE__, [@start, @stop], fn ->
        assert with_span(adapter_meta, :test, fn -> "test" end) == "test"

        refute_receive {@start, _, _}
        refute_receive {@stop, _, _}
      end)
    end
  end
end
