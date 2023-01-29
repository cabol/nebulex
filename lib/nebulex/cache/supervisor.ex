defmodule Nebulex.Cache.Supervisor do
  @moduledoc false
  use Supervisor

  import Nebulex.Helpers

  alias Nebulex.Telemetry

  @doc """
  Starts the cache manager supervisor.
  """
  @spec start_link(module, atom, module, keyword) :: Supervisor.on_start()
  def start_link(cache, otp_app, adapter, opts) do
    name = Keyword.get(opts, :name, cache)
    sup_opts = if name, do: [name: name], else: []

    Supervisor.start_link(__MODULE__, {name, cache, otp_app, adapter, opts}, sup_opts)
  end

  @doc """
  Retrieves the runtime configuration.
  """
  @spec runtime_config(module, atom, keyword) :: {:ok, keyword} | :ignore
  def runtime_config(cache, otp_app, opts) do
    config =
      otp_app
      |> Application.get_env(cache, [])
      |> Keyword.merge(opts)
      |> Keyword.put(:otp_app, otp_app)
      |> Keyword.put_new_lazy(:telemetry_prefix, fn -> telemetry_prefix(cache) end)
      |> Keyword.update(:telemetry, true, &(is_boolean(&1) && &1))

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
  @spec compile_config(keyword) :: {atom, module, [module]}
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
  def init({name, cache, otp_app, adapter, opts}) do
    # Normalize name to atom, ignore via/global names
    name = if is_atom(name), do: name, else: nil

    case runtime_config(cache, otp_app, opts) do
      {:ok, opts} ->
        # Dispatch Telemetry event notifying the cache is started
        :ok =
          Telemetry.execute(
            [:nebulex, :cache, :init],
            %{system_time: System.system_time()},
            %{name: name, cache: cache, opts: opts}
          )

        # Init the adapter
        {:ok, child, meta} = adapter.init([cache: cache] ++ opts)

        # Build child spec
        child_spec = wrap_child_spec(child, [name, cache, adapter, meta])

        # Init the cache supervisor
        Supervisor.init([child_spec], strategy: :one_for_one, max_restarts: 0)

      :ignore ->
        :ignore
    end
  end

  ## Helpers

  @doc false
  def start_child({mod, fun, args}, name, cache, adapter, meta) do
    case apply(mod, fun, args) do
      {:ok, pid} ->
        # Add the pid and the adapter to the meta
        meta = Map.merge(meta, %{pid: pid, cache: cache, adapter: adapter})

        # Register the started cache's pid
        :ok = Nebulex.Cache.Registry.register(self(), name, meta)

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
