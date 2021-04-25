if Code.ensure_loaded?(:shards) do
  defmodule Nebulex.Adapters.Local.Backend.Shards do
    @moduledoc false

    defmodule __MODULE__.DynamicSupervisor do
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

    use Nebulex.Adapters.Local.Backend

    alias Nebulex.Adapters.Local.Metadata

    ## API

    @doc false
    def child_spec(opts) do
      partitions =
        get_option(
          opts,
          :partitions,
          "an integer > 0",
          &(is_integer(&1) and &1 > 0),
          System.schedulers_online()
        )

      meta_tab =
        opts
        |> Keyword.fetch!(:adapter_meta)
        |> Map.fetch!(:meta_tab)

      sup_spec([
        {__MODULE__.DynamicSupervisor, meta_tab},
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
