defmodule Nebulex.Telemetry do
  @moduledoc """
  Telemetry wrapper.
  """

  # Inline common instructions
  @compile {:inline, execute: 3, span: 3}

  if Code.ensure_loaded?(:telemetry) do
    defdelegate execute(event, measurements, metadata), to: :telemetry

    defdelegate span(event_prefix, start_meta, span_fn), to: :telemetry
  else
    @doc false
    def execute(_event, _measurements, _metadata), do: :ok

    @doc false
    def span(_event_prefix, _start_meta, span_fn), do: elem(span_fn.(), 0)
  end
end
