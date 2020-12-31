defmodule Nebulex.Adapter do
  @moduledoc """
  Specifies the minimal API required from adapters.
  """

  @type t :: module

  @typedoc """
  The metadata returned by the adapter `c:init/1`.

  It must be a map and Nebulex itself will always inject two keys into the meta:

    * `:cache` - The cache module.
    * `:pid` - The PID returned by the child spec returned in `c:init/1`

  """
  @type adapter_meta :: %{optional(atom) => term}

  @typedoc "Proxy type to the options"
  @type opts :: Nebulex.Cache.opts()

  @doc """
  The callback invoked in case the adapter needs to inject code.
  """
  @macrocallback __before_compile__(env :: Macro.Env.t()) :: Macro.t()

  @doc """
  Initializes the adapter supervision tree by returning the children.
  """
  @callback init(opts) :: {:ok, child_spec, adapter_meta}
            when child_spec:
                   :supervisor.child_spec()
                   | {module(), term()}
                   | module()
                   | nil

  @doc """
  RExecutes the function `fun` passing as parameters the adapter and metadata
  (from the `c:init/1` callback) associated with the given cache `name_or_pid`.

  It expects a name or a PID representing the cache.
  """
  @spec with_meta(atom | pid, (module, adapter_meta -> term)) :: term
  def with_meta(name_or_pid, fun) do
    {adapter, adapter_meta} = Nebulex.Cache.Registry.lookup(name_or_pid)
    fun.(adapter, adapter_meta)
  end
end
