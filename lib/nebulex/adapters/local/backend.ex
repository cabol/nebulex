defmodule Nebulex.Adapters.Local.Backend do
  @moduledoc false

  @doc false
  defmacro __using__(_opts) do
    quote do
      import Nebulex.Helpers

      alias Nebulex.Adapters.Local.Generation

      defp generation_spec(name, opts) do
        %{
          id: {name, Generation},
          start: {Generation, :start_link, [opts]}
        }
      end

      defp sup_spec(name, children) do
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

        backend_opts =
          [
            type,
            :public,
            {:keypos, 2},
            {:read_concurrency, get_option(opts, :read_concurrency, &is_boolean/1, true)},
            {:write_concurrency, get_option(opts, :write_concurrency, &is_boolean/1, true)},
            compressed,
            extra
          ]
          |> List.flatten()
          |> Enum.filter(&(&1 != :named_table))

        Keyword.put(opts, :backend_opts, backend_opts)
      end
    end
  end

  @doc """
  Helper function for returning the child spec for the given backend.
  """
  def child_spec(backend, name, opts) do
    backend
    |> get_mod()
    |> apply(:child_spec, [name, opts])
  end

  @doc """
  Helper function for creating a new table for the given backend.
  """
  def new(backend, cache_name, tab_opts) do
    backend
    |> get_mod()
    |> apply(:new, [cache_name, tab_opts])
  end

  @doc """
  Helper function for deleting a table for the given backend.
  """
  def delete(backend, cache_name, tab) do
    backend
    |> get_mod()
    |> apply(:delete, [cache_name, tab])
  end

  defp get_mod(:ets), do: Nebulex.Adapters.Local.Backend.ETS

  if Code.ensure_loaded?(:shards) do
    defp get_mod(:shards), do: Nebulex.Adapters.Local.Backend.Shards
  end
end
