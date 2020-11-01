if Code.ensure_loaded?(:shards) do
  defmodule Nebulex.Adapters.Local.Backend.Shards.DynamicSupervisor do
    @moduledoc false
    use DynamicSupervisor

    alias Nebulex.Adapters.Local.Metadata

    ## API

    @doc false
    def start_link(tab) do
      DynamicSupervisor.start_link(__MODULE__, tab)
    end

    ## DynamicSupervisor Callbacks

    @impl true
    def init(meta_tab) do
      :ok = Metadata.put(meta_tab, :shards_sup, self())
      DynamicSupervisor.init(strategy: :one_for_one)
    end
  end
end
