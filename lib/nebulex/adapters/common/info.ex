defmodule Nebulex.Adapters.Common.Info do
  @moduledoc """
  A simple/default implementation for `Nebulex.Adapter.Info` behaviour.

  The implementation defines the following information specifications:

    * `:server` - A map with general information about the cache server.
      Includes the following keys:

      * `:nbx_version` - The Nebulex version.
      * `:cache_module` - The defined cache module.
      * `:cache_adapter` - The cache adapter.
      * `:cache_name` - The cache name.
      * `:cache_pid` - The cache PID.

    * `:stats` - A map with the cache statistics keys, as specified by
      `Nebulex.Adapters.Common.Info.Stats`.

  The info data will look like this:

      %{
        server: %{
          nbx_version: "3.0.0",
          cache_module: "MyCache",
          cache_adapter: "Nebulex.Adapters.Local",
          cache_name: "MyCache",
          cache_pid: #PID<0.111.0>
        },
        stats: %{
          deletions: 0,
          evictions: 0,
          expirations: 0,
          hits: 0,
          misses: 0,
          updates: 0,
          writes: 0
        }
      }

  """

  @doc false
  defmacro __using__(_opts) do
    quote do
      @behaviour Nebulex.Adapter.Info

      alias Nebulex.Adapters.Common.Info

      @impl true
      def info(adapter_meta, path, _opts) do
        {:ok, Info.info(adapter_meta, path)}
      end

      defoverridable info: 3
    end
  end

  alias __MODULE__.Stats

  @doc false
  def info(adapter_meta, spec)

  def info(adapter_meta, spec) when is_list(spec) do
    for i <- spec, into: %{} do
      {i, do_info!(adapter_meta, i)}
    end
  end

  def info(adapter_meta, spec) do
    do_info!(adapter_meta, spec)
  end

  defp do_info!(adapter_meta, :all) do
    %{
      server: server_info(adapter_meta),
      stats: stats(adapter_meta)
    }
  end

  defp do_info!(adapter_meta, :server) do
    server_info(adapter_meta)
  end

  defp do_info!(adapter_meta, :stats) do
    stats(adapter_meta)
  end

  defp do_info!(_adapter_meta, spec) do
    raise ArgumentError, "invalid information specification key #{inspect(spec)}"
  end

  ## Helpers

  defp server_info(adapter_meta) do
    %{
      nbx_version: Nebulex.vsn(),
      cache_module: adapter_meta[:cache],
      cache_adapter: adapter_meta[:adapter],
      cache_name: adapter_meta[:name],
      cache_pid: adapter_meta[:pid]
    }
  end

  defp stats(%{stats_counter: ref}) when not is_nil(ref) do
    Stats.count(ref)
  end

  defp stats(_adapter_meta) do
    Stats.new()
  end
end
