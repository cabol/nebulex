defmodule Nebulex.Cache.Supervisor do
  @moduledoc false
  use Supervisor

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
  def compile_config(cache, opts) do
    otp_app = opts[:otp_app] || raise ArgumentError, "expected otp_app: to be given as argument"
    adapter = opts[:adapter] || raise ArgumentError, "expected adapter: to be given as argument"

    if Code.ensure_compiled(adapter) != {:module, adapter} do
      raise ArgumentError,
            "adapter #{inspect(adapter)} was not compiled, " <>
              "ensure it is correct and it is included as a project dependency"
    end

    behaviours =
      for {:behaviour, behaviours} <- adapter.__info__(:attributes),
          behaviour <- behaviours,
          do: behaviour

    unless Nebulex.Adapter in behaviours do
      raise ArgumentError,
            "expected :adapter option given to Nebulex.Cache to list Nebulex.Adapter as a behaviour"
    end

    config =
      otp_app
      |> Application.get_env(cache, [])
      |> Keyword.merge(opts)

    {otp_app, adapter, behaviours, config}
  end

  ## Callbacks

  @doc false
  def init({cache, otp_app, adapter, opts}) do
    case runtime_config(cache, otp_app, opts) do
      {:ok, opts} ->
        {:ok, children} = adapter.init([cache: cache] ++ opts)
        children = maybe_add_stats(opts[:stats], cache, children)
        Supervisor.init(children, strategy: :one_for_one)

      :ignore ->
        :ignore
    end
  end

  defp maybe_add_stats(true, cache, children), do: [{Nebulex.Cache.Stats, cache} | children]
  defp maybe_add_stats(_, _cache, children), do: children
end
