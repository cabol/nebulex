defmodule Nebulex.Cache.Stats do
  @moduledoc false

  alias Nebulex.Adapter

  ## API

  @doc """
  Implementation for `c:Nebulex.Cache.stats_info/0`.
  """
  def stats_info(name) do
    Adapter.with_meta(name, & &1.stats_info(&2))
  end

  @doc """
  Implementation for `c:Nebulex.Cache.stats_info/1`.
  """
  def stats_info(name, stat_name) do
    if info = stats_info(name) do
      Map.fetch!(info, stat_name)
    end
  end

  if Code.ensure_loaded?(:telemetry) do
    @doc """
    Implementation for `c:Nebulex.Cache.dispatch_stats/1`.
    """
    def dispatch_stats(name, opts \\ []) do
      Adapter.with_meta(name, fn adapter, meta ->
        if info = adapter.stats_info(meta) do
          :telemetry.execute(
            Keyword.get(opts, :event_prefix, [:nebulex, :cache]) ++ [:stats],
            Map.from_struct(info),
            opts |> Keyword.get(:metadata, %{}) |> Map.put(:cache, name)
          )
        else
          :ok
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
