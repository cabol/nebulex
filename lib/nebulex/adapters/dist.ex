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
    * Support for Sharding; handled by `Nebulex.Adapter.NodeSelector`
    * Support for transactions via Erlang global name registration facility

  ## Options

  These options should be set in the config file and require
  recompilation in order to make an effect.

    * `:adapter` - The adapter name, in this case, `Nebulex.Adapters.Dist`.

    * `:local` - The Local Cache module. The value to this option should be
      `Nebulex.Adapters.Local`, unless you want to provide a custom local
      cache adapter.

    * `:node_selector` - The module that implements the node picker interface
      `Nebulex.Adapter.NodeSelector`. If this option is not set, the default
      implementation provided by the interface is used.

  ## Runtime options

  These options apply to all adapter's functions.

    * `:timeout` - The time-out value in milliseconds for the command that
      will be executed. If the timeout is exceeded, then the current process
      will exit. This adapter uses `Task.await/2` internally, therefore,
      check the function documentation to learn more about it. For commands
      like `set_many` and `get_many`, if the timeout is exceeded, the task
      is shutted down but the current process doesn't exit, only the result
      associated to that task is just skipped in the reduce phase.

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

  ### `__local__`

  Returns the local cache adapter (the local backend).

  ### `get_node/1`

  This function invokes `Nebulex.Adapter.NodeSelector.get_node/2` internally.

      MyCache.get_node("mykey")

  ### `get_nodes/0`

  Returns the nodes that belongs to the caller Cache.

      MyCache.get_nodes()

  ## Limitations

  This adapter has a limitation for two functions: `get_and_update/4` and
  `update/5`. They both have a parameter that is the anonymous function,
  and the anonymous function is compiled into the module where it is created,
  which means it necessarily doesn't exists on remote nodes. To ensure they
  work as expected, you must provide functions from modules existing in all
  nodes of the group.
  """

  # Inherit default node selector function
  use Nebulex.Adapter.NodeSelector

  # Inherit default transaction implementation
  use Nebulex.Adapter.Transaction

  # Provide Cache Implementation
  @behaviour Nebulex.Adapter
  @behaviour Nebulex.Adapter.Queryable

  alias Nebulex.Adapters.Dist.RPC
  alias Nebulex.Object

  ## Adapter Impl

  @impl true
  defmacro __before_compile__(env) do
    otp_app = Module.get_attribute(env.module, :otp_app)
    config = Module.get_attribute(env.module, :config)
    node_selector = Keyword.get(config, :node_selector, __MODULE__)
    task_supervisor = Module.concat([env.module, TaskSupervisor])

    unless local = Keyword.get(config, :local) do
      raise ArgumentError,
            "missing :local configuration in " <>
              "config #{inspect(otp_app)}, #{inspect(env.module)}"
    end

    quote do
      alias Nebulex.Adapters.Dist.Cluster
      alias Nebulex.Adapters.Local.Generation

      def __local__, do: unquote(local)

      def __task_sup__, do: unquote(task_supervisor)

      def get_nodes do
        Cluster.get_nodes(__MODULE__)
      end

      def get_node(key) do
        unquote(node_selector).get_node(get_nodes(), key)
      end

      def init(config) do
        :ok = Cluster.join(__MODULE__)
        {:ok, config}
      end
    end
  end

  ## Adapter

  @impl true
  def init(opts) do
    cache = Keyword.fetch!(opts, :cache)
    {:ok, [{Task.Supervisor, name: cache.__task_sup__}]}
  end

  @impl true
  def get(cache, key, opts) do
    call(cache, key, :get, [key, opts], opts)
  end

  @impl true
  def get_many(cache, keys, opts) do
    map_reduce(keys, cache, :get_many, opts, %{}, fn
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
  def set_many(cache, objects, opts) do
    objects
    |> map_reduce(cache, :set_many, opts, [], fn
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
  def update_counter(cache, key, incr, opts) do
    call(cache, key, :update_counter, [key, incr, opts], opts)
  end

  @impl true
  def size(cache) do
    Enum.reduce(cache.get_nodes(), 0, fn node, acc ->
      node
      |> rpc_call(cache, :size, [])
      |> Kernel.+(acc)
    end)
  end

  @impl true
  def flush(cache) do
    Enum.each(cache.get_nodes(), fn node ->
      rpc_call(node, cache, :flush, [])
    end)
  end

  ## Queryable

  @impl true
  def all(cache, query, opts) do
    for node <- cache.get_nodes(),
        elems <- rpc_call(node, cache, :all, [query, opts], opts),
        do: elems
  end

  @impl true
  def stream(cache, query, opts) do
    Stream.resource(
      fn ->
        cache.get_nodes()
      end,
      fn
        [] ->
          {:halt, []}

        [node | nodes] ->
          elements =
            rpc_call(
              node,
              __MODULE__,
              :eval_local_stream,
              [cache, query, opts],
              cache.__task_sup__,
              opts
            )

          {elements, nodes}
      end,
      & &1
    )
  end

  @doc """
  Helper to perform `stream/3` locally.
  """
  def eval_local_stream(cache, query, opts) do
    cache.__local__
    |> cache.__local__.__adapter__.stream(query, opts)
    |> Enum.to_list()
  end

  ## Private Functions

  defp call(cache, key, fun, args, opts \\ []) do
    key
    |> cache.get_node()
    |> rpc_call(cache, fun, args, opts)
  end

  defp rpc_call(node, cache, fun, args, opts \\ []) do
    rpc_call(
      node,
      cache.__local__.__adapter__,
      fun,
      [cache.__local__ | args],
      cache.__task_sup__,
      opts
    )
  end

  defp rpc_call(node, mod, fun, args, supervisor, opts) do
    node
    |> RPC.call(mod, fun, args, supervisor, Keyword.get(opts, :timeout, 5000))
    |> case do
      {:badrpc, remote_ex} -> raise remote_ex
      response -> response
    end
  end

  defp group_keys_by_node(objs_or_keys, cache) do
    Enum.reduce(objs_or_keys, %{}, fn
      %Object{} = obj, acc ->
        node = cache.get_node(obj.key)
        Map.put(acc, node, [obj | Map.get(acc, node, [])])

      key, acc ->
        node = cache.get_node(key)
        Map.put(acc, node, [key | Map.get(acc, node, [])])
    end)
  end

  defp map_reduce(enum, cache, action, opts, reduce_acc, reduce_fun) do
    groups = group_keys_by_node(enum, cache)

    tasks =
      for {node, group} <- groups do
        Task.Supervisor.async(
          {cache.__task_sup__, node},
          cache.__local__.__adapter__,
          action,
          [cache.__local__, group, opts]
        )
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
