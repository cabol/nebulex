defmodule Nebulex.Adapter do
  @moduledoc """
  Specifies the minimal API required from adapters.
  """

  alias Nebulex.Telemetry

  @type t :: module

  @typedoc """
  The metadata returned by the adapter `c:init/1`.

  It must be a map and Nebulex itself will always inject two keys into
  the meta:

    * `:cache` - The cache module.
    * `:pid` - The PID returned by the child spec returned in `c:init/1`

  """
  @type adapter_meta :: %{optional(atom) => term}

  @doc """
  The callback invoked in case the adapter needs to inject code.
  """
  @macrocallback __before_compile__(env :: Macro.Env.t()) :: Macro.t()

  @doc """
  Initializes the adapter supervision tree by returning the children.
  """
  @callback init(config :: Keyword.t()) :: {:ok, :supervisor.child_spec(), adapter_meta}

  @doc """
  Executes the function `fun` passing as parameters the adapter and metadata
  (from the `c:init/1` callback) associated with the given cache `name_or_pid`.

  It expects a name or a PID representing the cache.
  """
  @spec with_meta(atom | pid, (module, adapter_meta -> term)) :: term
  def with_meta(name_or_pid, fun) do
    {adapter, adapter_meta} = Nebulex.Cache.Registry.lookup(name_or_pid)
    fun.(adapter, adapter_meta)
  end

  @doc """
  Helper function for the adapters so they can execute a cache command
  given by `fun` with Telemetry span events.
  """
  @spec with_span(adapter_meta, atom, fun) :: {term, %{optional(atom) => term}} | term
  def with_span(adapter_meta, action, fun)

  def with_span(%{telemetry_prefix: nil}, _action, fun) do
    fun.()
  end

  def with_span(adapter_meta, action, fun) do
    cache = adapter_meta[:name] || adapter_meta.cache

    Telemetry.span(
      adapter_meta.telemetry_prefix ++ [:command],
      %{cache: cache, action: action},
      fn ->
        result = fun.()
        {result, %{cache: cache, action: action, result: result}}
      end
    )
  end
end
