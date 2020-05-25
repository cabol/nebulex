defmodule Nebulex.Adapters.Local.Backend do
  @moduledoc false

  import Nebulex.Helpers

  alias Nebulex.Adapters.Local.Generation

  ## API

  @doc false
  def child_spec(:shards, name, opts) do
    sup_name = normalize_module_name([name, ShardsSupervisor])

    partitions =
      get_option(
        opts,
        :partitions,
        &(is_integer(&1) and &1 > 0),
        System.schedulers_online()
      )

    sup_spec(name, [
      %{
        id: sup_name,
        start: {:shards_sup, :start_link, [sup_name]},
        type: :supervisor
      },
      generation_spec(name, parse_opts(opts, sup_name: sup_name, n_shards: partitions))
    ])
  end

  def child_spec(:ets, name, opts) do
    sup_spec(name, [generation_spec(name, parse_opts(opts))])
  end

  defp generation_spec(name, opts) do
    %{
      id: {name, Generation},
      start: {Generation, :start_link, [opts]}
    }
  end

  def sup_spec(name, children) do
    Nebulex.Adapters.Supervisor.child_spec(
      name: normalize_module_name([name, Supervisor]),
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
