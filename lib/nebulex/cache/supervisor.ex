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
    otp_app = Keyword.fetch!(opts, :otp_app)
    adapter = Keyword.get(opts, :adapter)

    unless adapter do
      raise ArgumentError, "missing :adapter option on use Nebulex.Cache"
    end

    unless Code.ensure_loaded?(adapter) do
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
      |> Keyword.put(:otp_app, otp_app)

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
