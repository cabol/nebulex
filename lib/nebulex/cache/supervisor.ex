defmodule Nebulex.Cache.Supervisor do
  @moduledoc false

  use Supervisor

  import Nebulex.Cache.Options
  import Nebulex.Utils

  alias Nebulex.Telemetry

  @doc """
  Starts the cache manager supervisor.
  """
  @spec start_link(module(), atom(), module(), keyword()) :: Supervisor.on_start()
  def start_link(cache, otp_app, adapter, opts) do
    name = Keyword.get(opts, :name, cache)
    sup_opts = if name, do: [name: name], else: []

    Supervisor.start_link(__MODULE__, {name, cache, otp_app, adapter, opts}, sup_opts)
  end

  @doc """
  Retrieves the runtime configuration.
  """
  @spec runtime_config(module(), atom(), keyword()) :: {:ok, keyword()} | :ignore
  def runtime_config(cache, otp_app, opts) do
    config =
      otp_app
      |> Application.get_env(cache, [])
      |> Keyword.merge(opts)
      |> Keyword.put(:otp_app, otp_app)
      |> validate_start_opts!()

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
  @spec compile_config(keyword()) :: {atom(), module(), [module()], keyword()}
  def compile_config(opts) do
    # Validate options
    opts = validate_compile_opts!(opts)

    otp_app = Keyword.fetch!(opts, :otp_app)
    adapter = Keyword.fetch!(opts, :adapter)
    behaviours = module_behaviours(adapter)

    {otp_app, adapter, behaviours, opts}
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

        # Check if bypass_mode is enabled to set the bypass adapter
        adapter = maybe_set_bypass_adapter(adapter, opts)

        # Init the adapter
        {:ok, child, meta} = adapter.init([cache: cache] ++ opts)

        # Add required keys to the metadata
        meta =
          Map.merge(meta, %{
            name: name,
            cache: cache,
            adapter: adapter,
            telemetry: Keyword.fetch!(opts, :telemetry),
            telemetry_prefix: Keyword.fetch!(opts, :telemetry_prefix),
            bypass_mode: Keyword.fetch!(opts, :bypass_mode)
          })

        # Build child spec
        child_spec = wrap_child_spec(child, [name, meta])

        # Init the cache supervisor
        Supervisor.init([child_spec], strategy: :one_for_one, max_restarts: 0)

      :ignore ->
        :ignore
    end
  end

  ## Helpers

  @doc false
  def start_child({mod, fun, args}, name, meta) do
    with {:ok, pid} <- apply(mod, fun, args) do
      # Add the PID to the metadata
      meta = Map.put(meta, :pid, pid)

      # Register the started cache's pid
      :ok = Nebulex.Cache.Registry.register(self(), name, meta)

      {:ok, pid}
    end
  end

  defp wrap_child_spec({id, start, restart, shutdown, type, mods}, args) do
    {id, {__MODULE__, :start_child, [start | args]}, restart, shutdown, type, mods}
  end

  defp wrap_child_spec(%{start: start} = spec, args) do
    %{spec | start: {__MODULE__, :start_child, [start | args]}}
  end

  defp maybe_set_bypass_adapter(adapter, opts) do
    case Keyword.fetch!(opts, :bypass_mode) do
      true -> Nebulex.Adapters.Nil
      false -> adapter
    end
  end
end
