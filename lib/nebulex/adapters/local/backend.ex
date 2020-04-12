defmodule Nebulex.Adapters.Local.Backend do
  @moduledoc false

  import Nebulex.Helpers

  alias Nebulex.Adapters.Local.Generation

  ## API

  @doc false
  def child_spec(cache, opts) do
    child_spec(cache.__backend__, cache, opts)
  end

  defp child_spec(:shards, cache, opts) do
    sup_name = Module.concat(cache, ShardsSupervisor)

    partitions =
      get_option(
        opts,
        :partitions,
        &(is_integer(&1) and &1 > 0),
        System.schedulers_online()
      )

    sup_spec(cache, [
      %{
        id: sup_name,
        start: {:shards_sup, :start_link, [sup_name]},
        type: :supervisor
      },
      generation_spec(cache, parse_opts(opts, sup_name: sup_name, n_shards: partitions))
    ])
  end

  defp child_spec(:ets, cache, opts) do
    sup_spec(cache, [generation_spec(cache, parse_opts(opts))])
  end

  defp generation_spec(cache, opts) do
    %{
      id: {cache, Generation},
      start: {Generation, :start_link, [cache, opts]}
    }
  end

  def sup_spec(cache, children) do
    Nebulex.Adapters.Supervisor.child_spec(
      name: Module.concat(cache, Supervisor),
      strategy: :one_for_all,
      children: children
    )
  end

  defp parse_opts(opts, extra \\ []) do
    type = get_option(opts, :backend_type, &is_atom/1, :set)

    compressed =
      case get_option(opts, :compressed, &is_boolean/1, false) do
        true -> [:compressed]
        false -> []
      end

    Keyword.put(
      opts,
      :backend_opts,
      List.flatten([
        type,
        :named_table,
        :public,
        {:keypos, 2},
        {:read_concurrency, get_option(opts, :read_concurrency, &is_boolean/1, true)},
        {:write_concurrency, get_option(opts, :write_concurrency, &is_boolean/1, true)},
        compressed,
        extra
      ])
    )
  end
end
