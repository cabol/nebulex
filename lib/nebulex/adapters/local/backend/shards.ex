if Code.ensure_loaded?(:shards) do
  defmodule Nebulex.Adapters.Local.Backend.Shards do
    @moduledoc false
    use Nebulex.Adapters.Local.Backend

    alias Nebulex.Adapters.Local.Backend.Shards.DynamicSupervisor, as: ShardsDynamicSupervisor
    alias Nebulex.Adapters.Local.Metadata

    ## API

    @doc false
    def child_spec(opts) do
      partitions =
        get_option(
          opts,
          :partitions,
          &(is_integer(&1) and &1 > 0),
          System.schedulers_online()
        )

      sup_spec([
        {ShardsDynamicSupervisor, Keyword.fetch!(opts, :meta_tab)},
        generation_spec(parse_opts(opts, partitions: partitions))
      ])
    end

    @doc false
    def new(meta_tab, tab_opts) do
      {:ok, _pid, tab} =
        meta_tab
        |> Metadata.get(:shards_sup)
        |> DynamicSupervisor.start_child(table_spec(tab_opts))

      tab
    end

    @doc false
    def delete(meta_tab, gen_tab) do
      meta_tab
      |> Metadata.get(:shards_sup)
      |> DynamicSupervisor.terminate_child(:shards_meta.tab_pid(gen_tab))
    end

    @doc false
    def start_table(opts) do
      tab = :shards.new(__MODULE__, opts)
      pid = :shards_meta.tab_pid(tab)
      {:ok, pid, tab}
    end

    defp table_spec(opts) do
      %{
        id: __MODULE__,
        start: {__MODULE__, :start_table, [opts]},
        type: :supervisor
      }
    end
  end
end
