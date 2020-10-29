defmodule Nebulex.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      List.flatten([
        Nebulex.Cache.Registry,
        pg_children()
      ])

    opts = [strategy: :one_for_one, name: Nebulex.Supervisor]
    Supervisor.start_link(children, opts)
  end

  if Code.ensure_loaded?(:pg) do
    defp pg_children do
      [%{id: :pg, start: {:pg, :start_link, [Nebulex.Cache.Cluster]}}]
    end
  else
    defp pg_children do
      []
    end
  end
end
