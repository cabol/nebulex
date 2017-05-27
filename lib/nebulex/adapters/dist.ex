defmodule Nebulex.Adapters.Dist do
  @moduledoc """
  Adapter module for Distributed Cache.

  This adapter depends on a local cache adapter, it adds a thin layer
  on top of it in order to distribute requests across a group of nodes,
  where is supposed the local cache is running too.

  This adapter uses PG2 to manage the cluster nodes. When the distributed
  cache is started in a node, it creates a PG2 group and joins it (the cache
  supervisor PID is joined to the group). Then, when a function is invoked,
  the adapter picks a node from the node list (using the PG2 group members),
  and then the function is executed on that node. In the same way, when the
  supervisor process of the distributed cache dies, the PID of that process
  is automatically removed from the PG2 group; this is why it's recommended
  to use a distributed hashing algorithm for the node picker.

  ## Features

    * Support for Distributed Cache
    * Support for Sharding; handled by `Nebulex.Adapters.Dist.NodePicker`
    * Support for transactions via Erlang global name registration facility

  ## Options

  These options should be set in the config file and require
  recompilation in order to make an effect.

    * `:adapter` - The adapter name, in this case, `Nebulex.Adapters.Dist`.

    * `:local` - The Local Cache module. The value to this option should be
      `Nebulex.Adapters.Local`, unless you want to provide a custom local
      cache adapter.

    * `:node_picker` - The module that implements the node picker interface
      `Nebulex.Adapters.Dist.NodePicker`. If this option is not set, the
      default implementation provided by the interface is used.

  ## Example

  `Nebulex.Cache` is the wrapper around the Cache. We can define the
  local and distributed cache as follows:

      defmodule MyApp.LocalCache do
        use Nebulex.Cache, otp_app: :my_app, adapter: Nebulex.Adapters.Local
      end

      defmodule MyApp.DistCache do
        use Nebulex.Cache, otp_app: :my_app, adapter: Nebulex.Adapters.Dist
      end

  Where the configuration for the Cache must be in your application
  environment, usually defined in your `config/config.exs`:

      config :my_app, MyApp.LocalCache,
        n_shards: 2,
        gc_interval: 3600

      config :my_app, MyApp.DistCache,
        local: MyApp.LocalCache

  For more information about the usage, check `Nebulex.Cache`.

  ## Extended API

  This adapter provides some additional functions to the `Nebulex.Cache` API.

  ### `pick_node/1`

  This function invokes `Nebulex.Adapters.Dist.NodePicker.pick_node/2`
  internally.

      MyCache.pick_node("mykey")

  ### `nodes/0`

  Returns the nodes that belongs to the caller Cache.

      MyCache.nodes()

  ### `new_generation/1`

  Creates a new generation in all nodes that belongs to the caller Cache.

      MyCache.new_generation()

  ## Limitations

  This adapter has some limitation for two functions: `get_and_update/4` and
  `update/5`. They both have a parameter that is an anonymous function, and
  the anonymous function is compiled into the module where it was created,
  which means it necessarily doesn't exists on remote nodes. To ensure they
  work as expected, you must provide functions from modules existing in all
  nodes of the group.
  """

  # Inherit default node picker function
  use Nebulex.Adapters.Dist.NodePicker

  # Provide Cache Implementation
  @behaviour Nebulex.Adapter

  ## Adapter Impl

  @doc false
  defmacro __before_compile__(env) do
    otp_app = Module.get_attribute(env.module, :otp_app)
    config = Module.get_attribute(env.module, :config)
    node_picker = Keyword.get(config, :node_picker, __MODULE__)

    unless local = Keyword.get(config, :local) do
      raise ArgumentError,
        "missing :local configuration in " <>
        "config #{inspect otp_app}, #{inspect env.module}"
    end

    quote do
      def __local__, do: unquote(local)

      def pick_node(key) do
        nodes()
        |> unquote(node_picker).pick_node(key)
      end

      def nodes do
        pg2_namespace()
        |> :pg2.get_members()
        |> Enum.map(&node(&1))
        |> :lists.usort
      end

      def new_generation(opts \\ []) do
        generations_handler = Nebulex.Adapters.Local.Generation
        {res, _} = :rpc.multicall(nodes(), generations_handler, :new, [unquote(local), opts])
        res
      end

      def init(config) do
        :ok = :pg2.create(pg2_namespace())
        :ok = :pg2.join(pg2_namespace(), self())
        {:ok, config}
      end

      defp pg2_namespace, do: {:nebulex, __MODULE__}
    end
  end

  ## Adapter Impl

  @doc false
  def children(_cache, _opts), do: []

  @doc false
  def get(cache, key, opts \\ []) do
    call(cache, :get, [key, opts])
  end

  @doc false
  def set(cache, key, value, opts \\ []) do
    call(cache, :set, [key, value, opts])
  end

  @doc false
  def delete(cache, key, opts \\ []) do
    call(cache, :delete, [key, opts])
  end

  @doc false
  def has_key?(cache, key) do
    call(cache, :has_key?, [key])
  end

  @doc false
  def all(cache, opts \\ []) do
    cache.nodes
    |> Enum.reduce([], fn(node, acc) ->
      rpc_call(node, cache.__local__, :all, [opts]) ++ acc
    end)
    |> :lists.usort()
  end

  @doc false
  def pop(cache, key, opts \\ []) do
    call(cache, :pop, [key, opts])
  end

  @doc false
  def get_and_update(cache, key, fun, opts \\ []) when is_function(fun, 1) do
    call(cache, :get_and_update, [key, fun, opts])
  end

  @doc false
  def update(cache, key, initial, fun, opts \\ []) do
    call(cache, :update, [key, initial, fun, opts])
  end

  @doc false
  def transaction(cache, key \\ nil, fun) do
    :global.trans({{cache, key}, self()}, fun, cache.nodes)
  end

  ## Private Functions

  defp call(cache, fun, [key | _] = args) do
    call(cache, key, fun, args)
  end

  defp call(cache, key, fun, args) do
    key
    |> cache.pick_node()
    |> rpc_call(cache.__local__, fun, args)
  end

  defp rpc_call(node, mod, fun, args) do
    case :rpc.call(node, mod, fun, args) do
      {:badrpc, ex} -> raise Nebulex.RemoteProcedureCallError, exception: ex
      response      -> response
    end
  end
end
