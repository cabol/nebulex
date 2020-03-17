defmodule Nebulex.Cache.Supervisor do
  @moduledoc false
  use Supervisor

  import Nebulex.Helpers

  @doc """
  Starts the cache manager supervisor.
  """
  def start_link(cache, otp_app, adapter, opts) do
    sup_opts = if name = Keyword.get(opts, :name, cache), do: [name: name], else: []
    Supervisor.start_link(__MODULE__, {cache, otp_app, adapter, opts}, sup_opts)
  end

  @doc """
  Retrieves the runtime configuration.
  """
  def runtime_config(cache, otp_app, opts) do
    config = Application.get_env(otp_app, cache, [])
    config = [otp_app: otp_app] ++ Keyword.merge(config, opts)
    cache_init(cache, config)
  end

  defp cache_init(cache, config) do
    if Code.ensure_loaded?(cache) and function_exported?(cache, :init, 1) do
      cache.init(config)
    else
      {:ok, config}
    end
  end

  @doc """
  Retrieves the compile time configuration.
  """
  def compile_config(opts) do
    otp_app = opts[:otp_app] || raise ArgumentError, "expected otp_app: to be given as argument"
    adapter = opts[:adapter] || raise ArgumentError, "expected adapter: to be given as argument"

    behaviours = module_behaviours(adapter, "adapter")

    unless Nebulex.Adapter in behaviours do
      raise ArgumentError,
            "expected :adapter option given to Nebulex.Cache to list Nebulex.Adapter as a behaviour"
    end

    {otp_app, adapter, behaviours}
  end

  ## Callbacks

  @doc false
  def init({cache, otp_app, adapter, opts}) do
    case runtime_config(cache, otp_app, opts) do
      {:ok, opts} ->
        cache
        |> init_adapter(adapter, opts)
        |> Supervisor.init(strategy: :one_for_one, max_restarts: 0)

      :ignore ->
        :ignore
    end
  end

  defp init_adapter(cache, adapter, opts) do
    case adapter.init([cache: cache] ++ opts) do
      {:ok, nil} -> []
      {:ok, child_spec} -> [child_spec]
    end
  end
end
