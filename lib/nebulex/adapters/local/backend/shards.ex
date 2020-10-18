if Code.ensure_loaded?(:shards) do
  defmodule Nebulex.Adapters.Local.Backend.Shards do
    @moduledoc false
    use Nebulex.Adapters.Local.Backend

    ## API

    @doc false
    def child_spec(name, opts) do
      sup_name = normalize_module_name([name, ShardsSupervisor])

      partitions =
        get_option(
          opts,
          :partitions,
          &(is_integer(&1) and &1 > 0),
          System.schedulers_online()
        )

      sup_spec(name, [
        {DynamicSupervisor, strategy: :one_for_one, name: sup_name},
        generation_spec(name, parse_opts(opts, partitions: partitions))
      ])
    end

    @doc false
    def new(cache_name, tab_opts) do
      {:ok, _pid, tab} =
        cache_name
        |> dynamic_sup()
        |> DynamicSupervisor.start_child(table_spec(cache_name, tab_opts))

      tab
    end

    @doc false
    def delete(cache_name, tab) do
      cache_name
      |> dynamic_sup()
      |> DynamicSupervisor.terminate_child(:shards_meta.tab_pid(tab))
    end

    @doc false
    def start_table(name, opts) do
      tab = :shards.new(name, opts)
      pid = :shards_meta.tab_pid(tab)
      {:ok, pid, tab}
    end

    defp table_spec(name, opts) do
      %{
        id: name,
        start: {__MODULE__, :start_table, [name, opts]},
        type: :supervisor
      }
    end

    defp dynamic_sup(name), do: normalize_module_name([name, ShardsSupervisor])
  end
end
