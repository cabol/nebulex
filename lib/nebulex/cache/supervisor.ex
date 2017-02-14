defmodule Nebulex.Cache.Supervisor do
  @moduledoc false
  use Supervisor

  @doc """
  Starts the cache manager supervisor.
  """
  def start_link(cache, otp_app, adapter, opts) do
    name = Keyword.get(opts, :name, cache)
    Supervisor.start_link(__MODULE__, {cache, otp_app, adapter, opts}, [name: name])
  end

  @doc """
  Retrieves the runtime configuration.
  """
  def runtime_config(cache, otp_app, custom) do
    if config = Application.get_env(otp_app, cache) do
      config = [otp_app: otp_app, cache: cache] ++ Keyword.merge(config, custom)
      cache_init(cache, config)
    else
      raise ArgumentError,
        "configuration for #{inspect cache} not specified in #{inspect otp_app} environment"
    end
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
    config  = Application.get_env(otp_app, cache, [])
    adapter = opts[:adapter] || config[:adapter]

    unless adapter do
      raise ArgumentError,
        "missing :adapter configuration in " <>
        "config #{inspect otp_app}, #{inspect cache}"
    end

    unless Code.ensure_loaded?(adapter) do
      raise ArgumentError,
        "adapter #{inspect adapter} was not compiled, " <>
        "ensure it is correct and it is included as a project dependency"
    end

    {otp_app, adapter, config}
  end

  ## Callbacks

  @doc false
  def init({cache, otp_app, adapter, opts}) do
    case runtime_config(cache, otp_app, opts) do
      {:ok, opts} ->
        children = adapter.children(cache, opts)
        supervise(children, strategy: :one_for_one)
      :ignore ->
        :ignore
    end
  end
end
