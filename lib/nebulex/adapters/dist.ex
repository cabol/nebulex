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
    * Support for Sharding; handled by `Nebulex.Adapter.NodePicker`
    * Support for transactions via Erlang global name registration facility

  ## Options

  These options should be set in the config file and require
  recompilation in order to make an effect.

    * `:adapter` - The adapter name, in this case, `Nebulex.Adapters.Dist`.

    * `:local` - The Local Cache module. The value to this option should be
      `Nebulex.Adapters.Local`, unless you want to provide a custom local
      cache adapter.

    * `:node_picker` - The module that implements the node picker interface
      `Nebulex.Adapter.NodePicker`. If this option is not set, the default
      implementation provided by the interface is used.

  Additionally, this adapter supports the option `:in_parallel` for `mget`
  and `mset` commands. Check `Nebulex.Cache.mset/2` and `Nebulex.Cache.mget/2`.

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

  This function invokes `Nebulex.Adapter.NodePicker.pick_node/2` internally.

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
  use Nebulex.Adapter.NodePicker

  # Inherit default transaction implementation
  use Nebulex.Adapter.Transaction

  # Provide Cache Implementation
  @behaviour Nebulex.Adapter
  @behaviour Nebulex.Adapter.List

  alias Nebulex.Object

  ## Adapter Impl

  @impl true
  defmacro __before_compile__(env) do
    otp_app = Module.get_attribute(env.module, :otp_app)
    config = Module.get_attribute(env.module, :config)
    node_picker = Keyword.get(config, :node_picker, __MODULE__)

    unless local = Keyword.get(config, :local) do
      raise ArgumentError,
            "missing :local configuration in " <>
              "config #{inspect(otp_app)}, #{inspect(env.module)}"
    end

    quote do
      alias Nebulex.Adapters.Dist.PG2
      alias Nebulex.Adapters.Local.Generation

      def __local__, do: unquote(local)

      def nodes, do: PG2.get_nodes(__MODULE__)

      def pick_node(key) do
        unquote(node_picker).pick_node(nodes(), key)
      end

      def new_generation(opts \\ []) do
        {res, _} = :rpc.multicall(nodes(), Generation, :new, [unquote(local), opts])
        res
      end

      def init(config) do
        :ok = PG2.join(__MODULE__)
        {:ok, config}
      end
    end
  end

  ## Adapter

  @impl true
  def init(_cache, _opts), do: {:ok, []}

  @impl true
  def get(cache, key, opts) do
    call(cache, key, :get, [key, opts], opts)
  end

  @impl true
  def mget(cache, keys, opts) do
    map_reduce(keys, cache, :mget, opts, %{}, fn
      res, _, acc when is_map(res) ->
        Map.merge(acc, res)

      _, _, acc ->
        acc
    end)
  end

  @impl true
  def set(cache, object, opts) do
    call(cache, object.key, :set, [object, opts], opts)
  end

  @impl true
  def mset(cache, objects, opts) do
    objects
    |> map_reduce(cache, :mset, opts, [], fn
      :ok, _, acc ->
        acc

      {:error, err_keys}, _, acc ->
        err_keys ++ acc

      _, group, acc ->
        for(o <- group, do: o.key) ++ acc
    end)
    |> case do
      [] -> :ok
      acc -> {:error, acc}
    end
  end

  @impl true
  def add(cache, object, opts) do
    call(cache, object.key, :add, [object, opts], opts)
  end

  @impl true
  def delete(cache, key, opts) do
    call(cache, key, :delete, [key, opts], opts)
  end

  @impl true
  def take(cache, key, opts) do
    call(cache, key, :take, [key, opts], opts)
  end

  @impl true
  def has_key?(cache, key) do
    call(cache, key, :has_key?, [key])
  end

  @impl true
  def get_and_update(cache, key, fun, opts) do
    call(cache, key, :get_and_update, [key, fun, opts], opts)
  end

  @impl true
  def update(cache, key, initial, fun, opts) do
    call(cache, key, :update, [key, initial, fun, opts], opts)
  end

  @impl true
  def update_counter(cache, key, incr, opts) do
    call(cache, key, :update_counter, [key, incr, opts], opts)
  end

  @impl true
  def size(cache) do
    Enum.reduce(cache.nodes, 0, fn node, acc ->
      node
      |> rpc_call(cache.__local__.__adapter__, :size, [cache.__local__])
      |> Kernel.+(acc)
    end)
  end

  @impl true
  def flush(cache) do
    Enum.each(cache.nodes, fn node ->
      rpc_call(node, cache.__local__.__adapter__, :flush, [cache.__local__])
    end)
  end

  @impl true
  def keys(cache) do
    cache.nodes
    |> Enum.reduce([], fn node, acc ->
      rpc_call(node, cache.__local__.__adapter__, :keys, [cache.__local__]) ++ acc
    end)
    |> :lists.usort()
  end

  ## Lists

  @impl true
  def lpush(cache, key, value, opts) do
    call(cache, key, :lpush, [key, value, opts], opts)
  end

  @impl true
  def rpush(cache, key, value, opts) do
    call(cache, key, :rpush, [key, value, opts], opts)
  end

  @impl true
  def lpop(cache, key, opts) do
    call(cache, key, :lpop, [key, opts], opts)
  end

  @impl true
  def rpop(cache, key, opts) do
    call(cache, key, :rpop, [key, opts], opts)
  end

  @impl true
  def lrange(cache, key, offset, limit, opts) do
    call(cache, key, :lrange, [key, offset, limit, opts], opts)
  end

  ## Private Functions

  defp call(cache, key, fun, args, opts \\ []) do
    key
    |> cache.pick_node()
    |> rpc_call(cache.__local__.__adapter__, fun, [cache.__local__ | args], opts)
  end

  defp rpc_call(node, mod, fun, args, opts \\ []) do
    case :rpc.call(node, mod, fun, args, opts[:timeout] || :infinity) do
      {:badrpc, {:EXIT, {remote_ex, _}}} ->
        raise remote_ex

      {:badrpc, reason} ->
        raise Nebulex.RPCError, reason: reason

      response ->
        response
    end
  end

  defp group_keys_by_node(objs_or_keys, cache) do
    Enum.reduce(objs_or_keys, %{}, fn
      %Object{} = obj, acc ->
        node = cache.pick_node(obj.key)
        Map.put(acc, node, [obj | Map.get(acc, node, [])])

      key, acc ->
        node = cache.pick_node(key)
        Map.put(acc, node, [key | Map.get(acc, node, [])])
    end)
  end

  defp map_reduce(enum, cache, action, opts, reduce_acc, reduce_fun) do
    opts
    |> Keyword.get(:in_parallel)
    |> case do
      true ->
        parallel_map_reduce(enum, cache, action, opts, reduce_acc, reduce_fun)

      _ ->
        seq_map_reduce(enum, cache, action, opts, reduce_acc, reduce_fun)
    end
  end

  defp seq_map_reduce(enum, cache, action, opts, reduce_acc, reduce_fun) do
    enum
    |> group_keys_by_node(cache)
    |> Enum.reduce(reduce_acc, fn {node, group}, acc ->
      node
      |> rpc_call(cache.__local__.__adapter__, action, [cache.__local__, group, opts])
      |> reduce_fun.(group, acc)
    end)
  end

  defp parallel_map_reduce(enum, cache, action, opts, reduce_acc, reduce_fun) do
    groups = group_keys_by_node(enum, cache)

    tasks =
      for {node, group} <- groups do
        Task.async(fn ->
          rpc_call(
            node,
            cache.__local__.__adapter__,
            action,
            [cache.__local__, group, opts]
          )
        end)
      end

    tasks
    |> Task.yield_many(Keyword.get(opts, :timeout, 5000))
    |> :lists.zip(Map.values(groups))
    |> Enum.reduce(reduce_acc, fn
      {{_task, {:ok, res}}, group}, acc ->
        reduce_fun.(res, group, acc)

      {{_task, {:exit, _reason}}, group}, acc ->
        reduce_fun.(:exit, group, acc)

      {{task, nil}, group}, acc ->
        _ = Task.shutdown(task, :brutal_kill)
        reduce_fun.(nil, group, acc)
    end)
  end
end
