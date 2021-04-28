defmodule Nebulex.Cache.Supervisor do
  @moduledoc false
  use Supervisor

  import Nebulex.Helpers

  alias Nebulex.Telemetry

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
    config = Keyword.put_new_lazy(config, :telemetry_prefix, fn -> telemetry_prefix(cache) end)

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

  ## Supervisor Callbacks

  @impl true
  def init({cache, otp_app, adapter, opts}) do
    case runtime_config(cache, otp_app, opts) do
      {:ok, opts} ->
        Telemetry.execute(
          [:nebulex, :cache, :init],
          %{system_time: System.system_time()},
          %{cache: cache, opts: opts}
        )

        {:ok, child, meta} = adapter.init([cache: cache] ++ opts)
        meta = Map.put(meta, :cache, cache)
        child_spec = wrap_child_spec(child, [adapter, meta])
        Supervisor.init([child_spec], strategy: :one_for_one, max_restarts: 0)

      other ->
        other
    end
  end

  ## Helpers

  @doc false
  def start_child({mod, fun, args}, adapter, meta) do
    case apply(mod, fun, args) do
      {:ok, pid} ->
        meta = Map.put(meta, :pid, pid)
        :ok = Nebulex.Cache.Registry.register(self(), {adapter, meta})
        {:ok, pid}

      other ->
        other
    end
  end

  defp wrap_child_spec({id, start, restart, shutdown, type, mods}, args) do
    {id, {__MODULE__, :start_child, [start | args]}, restart, shutdown, type, mods}
  end

  defp wrap_child_spec(%{start: start} = spec, args) do
    %{spec | start: {__MODULE__, :start_child, [start | args]}}
  end

  # sobelow_skip ["DOS.StringToAtom"]
  defp telemetry_prefix(cache) do
    cache
    |> Module.split()
    |> Enum.map(&(&1 |> Macro.underscore() |> String.to_atom()))
  end
end
