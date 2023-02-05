defmodule Nebulex.Cache.Stats do
  @moduledoc false

  import Nebulex.Helpers

  alias Nebulex.Adapter

  ## API

  @doc """
  Implementation for `c:Nebulex.Cache.stats/1`.
  """
  def stats(name) do
    Adapter.with_meta(name, & &1.adapter.stats(&1))
  end

  @doc """
  Implementation for `c:Nebulex.Cache.stats!/0`.
  """
  def stats!(name) do
    unwrap_or_raise stats(name)
  end

  if Code.ensure_loaded?(:telemetry) do
    @doc """
    Implementation for `c:Nebulex.Cache.dispatch_stats/1`.
    """
    def dispatch_stats(name, opts \\ []) do
      Adapter.with_meta(name, fn %{adapter: adapter} = meta ->
        with {:ok, %Nebulex.Stats{} = info} <- adapter.stats(meta) do
          :telemetry.execute(
            meta.telemetry_prefix ++ [:stats],
            info.measurements,
            Map.merge(info.metadata, opts[:metadata] || %{})
          )
        end
      end)
    end
  else
    @doc """
    Implementation for `c:Nebulex.Cache.dispatch_stats/1`.
    """
    def dispatch_stats(_name, _opts \\ []), do: :ok
  end
end
