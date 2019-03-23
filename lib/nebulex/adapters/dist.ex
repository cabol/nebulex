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

  These options can be set through the config file:

    * `:local` - The Local Cache module. The value to this option should be
      `Nebulex.Adapters.Local`, unless you want to provide a custom local
      cache adapter.

    * `:hash_slot` - The module that implements `Nebulex.Adapter.Hash`
      behaviour. Defaults to `Nebulex.Adapter.Hash.keyslot/2`.

  ## Runtime options

  These options apply to all adapter's functions.

    * `:timeout` - The time-out value in milliseconds for the command that
      will be executed. If the timeout is exceeded, then the current process
      will exit. This adapter uses `Task.await/2` internally, therefore,
      check the function documentation to learn more about it. For commands
      like `set_many` and `get_many`, if the timeout is exceeded, the task
      is shutted down but the current process doesn't exit, only the result
      associated to that task is just skipped in the reduce phase.

    * `task_supervisor_opts` - Defines the options passed to
      `Task.Supervisor.start_link/1` when the adapter is initialized.

  ## Example

  `Nebulex.Cache` is the wrapper around the cache. We can define the local
  and distributed cache as follows:

      defmodule MyApp.LocalCache do
        use Nebulex.Cache,
          otp_app: :my_app,
          adapter: Nebulex.Adapters.Local
      end

      defmodule MyApp.DistCache do
        use Nebulex.Cache,
          otp_app: :my_app,
          adapter: Nebulex.Adapters.Dist
      end

  Where the configuration for the cache must be in your application environment,
  usually defined in your `config/config.exs`:

      config :my_app, MyApp.LocalCache,
        n_shards: 2,
        gc_interval: 3600

      config :my_app, MyApp.DistCache,
        local: MyApp.LocalCache

  For more information about the usage, check out `Nebulex.Cache`.

  ## Extended API

  This adapter provides some additional functions to the `Nebulex.Cache` API.

  ### `__local__`

  Returns the local cache adapter (the local backend).

  ### `__task_sup__`

  Returns the task supervisor module that manages RPC calls.

  ### `__nodes__`

  Returns the nodes that belongs to the caller Cache.

  ### `get_node/1`

  This function invokes `c:Nebulex.Adapter.NodeSelector.get_node/2` internally.

      MyCache.get_node("mykey")

  ## Limitations

  This adapter has a limitation for two functions: `get_and_update/4` and
  `update/5`. They both have a parameter that is the anonymous function,
  and the anonymous function is compiled into the module where it is created,
  which means it necessarily doesn't exists on remote nodes. To ensure they
  work as expected, you must provide functions from modules existing in all
  nodes of the group.
  """

  # Inherit default transaction implementation
  use Nebulex.Adapter.Transaction

  # Provide Cache Implementation
  @behaviour Nebulex.Adapter
  @behaviour Nebulex.Adapter.Queryable

  alias Nebulex.{Object, RPC}

  ## Adapter

  @impl true
  defmacro __before_compile__(env) do
    otp_app = Module.get_attribute(env.module, :otp_app)
    config = Module.get_attribute(env.module, :config)
    hash_slot = Keyword.get(config, :hash_slot)
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

      def __nodes__, do: Cluster.get_nodes(__MODULE__)

      def get_node(key) do
        Cluster.get_node(__MODULE__, key, unquote(hash_slot))
      end

      def init(config) do
        :ok = Cluster.join(__MODULE__)
        {:ok, config}
      end
    end
  end

  @impl true
  def init(opts) do
    cache = Keyword.fetch!(opts, :cache)
    task_sup_opts = Keyword.get(opts, :task_supervisor_opts, [])
    {:ok, [{Task.Supervisor, [name: cache.__task_sup__] ++ task_sup_opts}]}
  end

  @impl true
  def get(cache, key, opts) do
    call(cache, key, :get, [key, opts], opts)
  end

  @impl true
  def get_many(cache, keys, opts) do
    map_reduce(
      keys,
      cache,
      :get_many,
      Keyword.put(opts, :reducer, {
        %{},
        fn
          {:ok, res}, _, acc when is_map(res) ->
            Map.merge(acc, res)

          _, _, acc ->
            acc
        end
      })
    )
  end

  @impl true
  def set(cache, object, opts) do
    call(cache, object.key, :set, [object, opts], opts)
  end

  @impl true
  def set_many(cache, objects, opts) do
    reducer = {
      [],
      fn
        {:ok, :ok}, _, acc ->
          acc

        {:ok, {:error, err_keys}}, _, acc ->
          err_keys ++ acc

        {:error, _}, {_, {_, _, [_, objs, _]}}, acc ->
          for(obj <- objs, do: obj.key) ++ acc
      end
    }

    objects
    |> map_reduce(cache, :set_many, Keyword.put(opts, :reducer, reducer))
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
  def object_info(cache, key, attr) do
    call(cache, key, :object_info, [key, attr])
  end

  @impl true
  def expire(cache, key, ttl) do
    call(cache, key, :expire, [key, ttl])
  end

  @impl true
  def update_counter(cache, key, incr, opts) do
    call(cache, key, :update_counter, [key, incr, opts], opts)
  end

  @impl true
  def size(cache) do
    cache.__task_sup__
    |> RPC.multi_call(
      cache.__nodes__,
      cache.__local__.__adapter__,
      :size,
      [cache.__local__]
    )
    |> handle_rpc_multi_call(:size, &Enum.sum/1)
  end

  @impl true
  def flush(cache) do
    _ =
      RPC.multi_call(
        cache.__task_sup__,
        cache.__nodes__,
        cache.__local__.__adapter__,
        :flush,
        [cache.__local__]
      )

    :ok
  end

  ## Queryable

  @impl true
  def all(cache, query, opts) do
    cache.__task_sup__
    |> RPC.multi_call(
      cache.__nodes__,
      cache.__local__.__adapter__,
      :all,
      [cache.__local__, query, opts],
      opts
    )
    |> handle_rpc_multi_call(:all, &List.flatten/1)
  end

  @impl true
  def stream(cache, query, opts) do
    Stream.resource(
      fn ->
        cache.__nodes__
      end,
      fn
        [] ->
          {:halt, []}

        [node | nodes] ->
          elements =
            rpc_call(
              cache.__task_sup__,
              node,
              __MODULE__,
              :eval_local_stream,
              [cache, query, opts],
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

  defp rpc_call(node, cache, fun, args, opts) do
    rpc_call(
      cache.__task_sup__,
      node,
      cache.__local__.__adapter__,
      fun,
      [cache.__local__ | args],
      opts
    )
  end

  defp rpc_call(supervisor, node, mod, fun, args, opts) do
    opts
    |> Keyword.get(:timeout)
    |> case do
      nil -> RPC.call(supervisor, node, mod, fun, args)
      val -> RPC.call(supervisor, node, mod, fun, args, val)
    end
    |> case do
      {:badrpc, remote_ex} ->
        raise remote_ex

      response ->
        response
    end
  end

  defp group_keys_by_node(enum, cache) do
    Enum.reduce(enum, %{}, fn
      %Object{key: key} = object, acc ->
        node = cache.get_node(key)
        Map.put(acc, node, [object | Map.get(acc, node, [])])

      key, acc ->
        node = cache.get_node(key)
        Map.put(acc, node, [key | Map.get(acc, node, [])])
    end)
  end

  defp map_reduce(enum, cache, action, opts) do
    groups =
      enum
      |> group_keys_by_node(cache)
      |> Enum.map(fn {node, group} ->
        {node, {cache.__local__.__adapter__, action, [cache.__local__, group, opts]}}
      end)

    RPC.multi_call(cache.__task_sup__, groups, opts)
  end

  defp handle_rpc_multi_call({res, []}, _action, fun) do
    fun.(res)
  end

  defp handle_rpc_multi_call({_, errors}, action, _) do
    raise Nebulex.RPCMultiCallError, action: action, errors: errors
  end
end
