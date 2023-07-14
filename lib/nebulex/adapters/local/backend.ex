defmodule Nebulex.Adapters.Local.Backend do
  @moduledoc false

  @doc false
  defmacro __using__(_opts) do
    quote do
      import Nebulex.Helpers

      alias Nebulex.Adapters.Local.Generation

      defp generation_spec(opts) do
        %{
          id: Module.concat([__MODULE__, GC]),
          start: {Generation, :start_link, [opts]}
        }
      end

      defp sup_spec(children) do
        %{
          id: Module.concat([__MODULE__, Supervisor]),
          start: {Supervisor, :start_link, [children, [strategy: :one_for_all]]},
          type: :supervisor
        }
      end

      defp parse_opts(opts, extra \\ []) do
        type = get_option(opts, :backend_type, "an atom", &is_atom/1, :set)

        compressed =
          case get_option(opts, :compressed, "boolean", &is_boolean/1, false) do
            true -> [:compressed]
            false -> []
          end

        backend_opts =
          [
            type,
            :public,
            {:keypos, 2},
            {:read_concurrency,
             get_option(opts, :read_concurrency, "boolean", &is_boolean/1, true)},
            {:write_concurrency,
             get_option(opts, :write_concurrency, "boolean", &is_boolean/1, true)},
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
  def child_spec(backend, opts) do
    get_mod(backend).child_spec(opts)
  end

  @doc """
  Helper function for creating a new table for the given backend.
  """
  def new(backend, meta_tab, tab_opts) do
    get_mod(backend).new(meta_tab, tab_opts)
  end

  @doc """
  Helper function for deleting a table for the given backend.
  """
  def delete(backend, meta_tab, gen_tab) do
    get_mod(backend).delete(meta_tab, gen_tab)
  end

  defp get_mod(:ets), do: Nebulex.Adapters.Local.Backend.ETS

  if Code.ensure_loaded?(:shards) do
    defp get_mod(:shards), do: Nebulex.Adapters.Local.Backend.Shards
  end
end
