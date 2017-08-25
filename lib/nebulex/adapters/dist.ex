defmodule Nebulex.Adapters.Dist do
  @moduledoc """
  Adapter module for distributed or partitioned cache.

  A distributed, or partitioned, cache is a clustered, fault-tolerant cache
  that has linear scalability. Data is partitioned among all the machines
  of the cluster. For fault-tolerance, partitioned caches can be configured
  to keep each piece of data on one or more unique machines within a cluster.
  This adapter in particular hasn't fault-tolerance built-in, each piece of
  data is kept in a single node/machine (sharding), therefore, if a node fails,
  the data kept by this node won't be available for the rest of the cluster.

  This adapter depends on a local cache adapter, it adds a thin layer
  on top of it in order to distribute requests across a group of nodes,
  where is supposed the local cache is running already.

  PG2 is used by the adapter to manage the cluster nodes. When the distributed
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

  # Inherit default transaction implementation
  use Nebulex.Adapter.Transaction

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
      alias Nebulex.Adapters.Local.Generation

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
        {res, _} = :rpc.multicall(nodes(), Generation, :new, [unquote(local), opts])
        res
      end

      def init(config) do
        :ok = :pg2.create(pg2_namespace())

        unless self() in :pg2.get_members(pg2_namespace()) do
          :ok = :pg2.join(pg2_namespace(), self())
        end

        {:ok, config}
      end

      defp pg2_namespace, do: {:nebulex, __MODULE__}
    end
  end

  ## Adapter Impl

  @doc false
  def children(_cache, _opts), do: []

  @doc false
  def get(cache, key, opts) do
    call(cache, :get, [key, opts])
  end

  @doc false
  def set(_cache, _key, nil, _opts),
    do: nil
  def set(cache, key, value, opts) do
    call(cache, :set, [key, value, opts])
  end

  @doc false
  def delete(cache, key, opts) do
    call(cache, :delete, [key, opts])
  end

  @doc false
  def has_key?(cache, key) do
    call(cache, :has_key?, [key])
  end

  @doc false
  def size(cache) do
    Enum.reduce(cache.nodes, 0, fn(node, acc) ->
      node
      |> rpc_call(cache.__local__, :size, [])
      |> Kernel.+(acc)
    end)
  end

  @doc false
  def flush(cache) do
    Enum.each(cache.nodes, fn(node) ->
      rpc_call(node, cache.__local__, :flush, [])
    end)
  end

  @doc false
  def keys(cache) do
    cache.nodes
    |> Enum.reduce([], fn(node, acc) -> rpc_call(node, cache.__local__, :keys, []) ++ acc end)
    |> :lists.usort()
  end

  @doc false
  def reduce(cache, acc_in, fun, opts) do
    Enum.reduce(cache.nodes, acc_in, fn(node, acc) ->
      rpc_call(node, cache.__local__, :reduce, [acc, fun, opts])
    end)
  end

  @doc false
  def to_map(cache, opts) do
    Enum.reduce(cache.nodes, %{}, fn(node, acc) ->
      node
      |> rpc_call(cache.__local__, :to_map, [opts])
      |> Map.merge(acc)
    end)
  end

  @doc false
  def pop(cache, key, opts) do
    call(cache, :pop, [key, opts])
  end

  @doc false
  def get_and_update(cache, key, fun, opts) when is_function(fun, 1) do
    call(cache, :get_and_update, [key, fun, opts])
  end

  @doc false
  def update(cache, key, initial, fun, opts) do
    call(cache, :update, [key, initial, fun, opts])
  end

  @doc false
  def update_counter(cache, key, incr, opts) do
    call(cache, :update_counter, [key, incr, opts])
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
      {:badrpc, {:EXIT, {remote_ex, _}}} ->
        raise remote_ex
      response ->
        response
    end
  end
end
