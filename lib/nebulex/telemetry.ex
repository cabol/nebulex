defmodule Nebulex.Telemetry do
  @moduledoc """
  Telemetry wrapper.
  """

  # Inline common instructions
  @compile {:inline, execute: 3, span: 3, attach_many: 4, detach: 1}

  if Code.ensure_loaded?(:telemetry) do
    @doc false
    defdelegate execute(event, measurements, metadata), to: :telemetry

    @doc false
    defdelegate span(event_prefix, start_meta, span_fn), to: :telemetry

    @doc false
    defdelegate attach_many(handler_id, events, fun, config), to: :telemetry

    @doc false
    defdelegate detach(handler_id), to: :telemetry
  else
    @doc false
    def execute(_event, _measurements, _metadata), do: :ok

    @doc false
    def span(_event_prefix, _start_meta, span_fn), do: elem(span_fn.(), 0)

    @doc false
    def attach_many(_handler_id, _events, _fun, _config), do: :ok

    @doc false
    def detach(_handler_id), do: :ok
  end
end
