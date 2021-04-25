defmodule Nebulex.Telemetry do
  @moduledoc """
  Telemetry wrapper.
  """

  @compile {:inline, execute: 3, span: 3}

  if Code.ensure_loaded?(:telemetry) do
    defdelegate execute(event, measurements, metadata), to: :telemetry

    @doc """
    Convenience functions based on `:telemetry.span/3` to be able to add other
    measurements to the Telemetry span events.
    """
    @spec span(
            :telemetry.event_prefix(),
            :telemetry.event_metadata(),
            :telemetry.span_function()
          ) :: :telemetry.span_result()
    def span(event_prefix, start_meta, span_fn) do
      start_time = System.monotonic_time()
      default_ctx = make_ref()

      :telemetry.execute(
        event_prefix ++ [:start],
        %{system_time: System.system_time(), count: 1},
        merge_ctx(start_meta, default_ctx)
      )

      try do
        {result, stop_meta} = span_fn.()

        :telemetry.execute(
          event_prefix ++ [:stop],
          %{
            system_time: System.system_time(),
            duration: System.monotonic_time() - start_time,
            count: 1
          },
          merge_ctx(stop_meta, default_ctx)
        )

        result
      catch
        class, reason ->
          :telemetry.execute(
            event_prefix ++ [:exception],
            %{
              system_time: System.system_time(),
              duration: System.monotonic_time() - start_time,
              count: 1
            },
            start_meta
            |> Map.merge(%{kind: class, reason: reason, stacktrace: __STACKTRACE__})
            |> merge_ctx(default_ctx)
          )

          :erlang.raise(class, reason, __STACKTRACE__)
      end
    end

    defp merge_ctx(%{telemetry_span_context: _} = meta, _ctx), do: meta
    defp merge_ctx(meta, ctx), do: Map.put_new(meta, :telemetry_span_context, ctx)
  else
    @doc false
    def execute(_event, _measurements, _metadata), do: :ok

    @doc false
    def span(_event_prefix, _start_meta, span_fn), do: elem(span_fn.(), 0)
  end
end
