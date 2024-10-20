defmodule Nebulex.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Nebulex.Cache.Registry
    ]

    opts = [strategy: :one_for_one, name: Nebulex.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
