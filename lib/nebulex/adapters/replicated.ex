defmodule Nebulex.Adapters.Replicated do
  @moduledoc """
  Built-in adapter for replicated cache topology.

  The replicated cache excels in its ability to handle data replication,
  concurrency control and failover in a cluster, all while delivering
  in-memory data access speeds. A clustered replicated cache is exactly
  what it says it is: a cache that replicates its data to all cluster nodes.

  There are several challenges to building a reliably replicated cache. The
  first is how to get it to scale and perform well. Updates to the cache have
  to be sent to all cluster nodes, and all cluster nodes have to end up with
  the same data, even if multiple updates to the same piece of data occur at
  the same time. Also, if a cluster node requests a lock, ideally it should
  not have to get all cluster nodes to agree on the lock or at least do it in
  a very efficient way (`:global` is used for this), otherwise it will scale
  extremely poorly; yet in the case of a cluster node failure, all of the data
  and lock information must be kept safely.

  The best part of a replicated cache is its access speed. Since the data is
  replicated to each cluster node, it is available for use without any waiting.
  This is referred to as "zero latency access," and is perfect for situations
  in which an application requires the highest possible speed in its data
  access.

  However, there are some limitations:

    * <ins>Cost Per Update</ins> - Updating a replicated cache requires pushing
      the new version of the data to all other cluster members, which will limit
      scalability if there is a high frequency of updates per member.

    * <ins>Cost Per Entry</ins> - The data is replicated to every cluster
      member, so Memory Heap space is used on each member, which will impact
      performance for large caches.

  > Based on **"Distributed Caching Essential Lessons"** by **Cameron Purdy**.

  ## Options

  These options can be set through the config file:

    * `:primary` - The module for the primary storage. The value must be a
      valid local cache adapter so that the partitioned adapter can store
      the data in there. For example, you can set the `Nebulex.Adapters.Local`
      as value, unless you want to provide another one.

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
  and replicated cache as follows:

      defmodule MyApp.ReplicatedCache do
        use Nebulex.Cache,
          otp_app: :my_app,
          adapter: Nebulex.Adapters.Replicated

        defmodule Primary do
          use Nebulex.Cache,
            otp_app: :my_app,
            adapter: Nebulex.Adapters.Local
        end
      end

  Where the configuration for the cache must be in your application environment,
  usually defined in your `config/config.exs`:

      config :my_app, MyApp.ReplicatedCache.Primary,
        n_shards: 2,
        gc_interval: 3600

      config :my_app, MyApp.ReplicatedCache,
        primary: MyApp.ReplicatedCache.Primary

  For more information about the usage, check out `Nebulex.Cache`.

  ## Extended API

  This adapter provides some additional functions to the `Nebulex.Cache` API.

  ### `__primary__`

  Returns the local cache adapter (the local backend).

  ### `__task_sup__`

  Returns the task supervisor module that manages RPC calls.

  ### `__nodes__`

  Returns the nodes that belongs to the caller Cache.
  """

  # Inherit default transaction implementation
  use Nebulex.Adapter.Transaction

  # Provide Cache Implementation
  @behaviour Nebulex.Adapter
  @behaviour Nebulex.Adapter.Queryable

  alias Nebulex.RPC

  ## Adapter

  @impl true
  defmacro __before_compile__(env) do
    otp_app = Module.get_attribute(env.module, :otp_app)
    config = Module.get_attribute(env.module, :config)
    task_supervisor = Module.concat([env.module, TaskSupervisor])

    unless primary = Keyword.get(config, :primary) do
      raise ArgumentError,
            "missing :primary configuration in " <>
              "config #{inspect(otp_app)}, #{inspect(env.module)}"
    end

    quote do
      alias Nebulex.Adapters.Local.Generation
      alias Nebulex.Cache.Cluster

      def __primary__, do: unquote(primary)

      def __task_sup__, do: unquote(task_supervisor)

      def __nodes__, do: Cluster.get_nodes(__MODULE__)

      def init(config) do
        :ok = Cluster.join(__MODULE__)
        {:ok, config}
      end

      def import do
        cluster_nodes = Cluster.get_nodes(__MODULE__)

        case cluster_nodes -- [node()] do
          [] ->
            :ok

          nodes ->
            transaction(
              fn ->
                nodes
                |> Enum.reduce_while([], &stream_entries/2)
                |> unquote(primary).set_many()
              end,
              keys: [:"$global_lock"],
              nodes: cluster_nodes
            )
        end
      end

      defp stream_entries(node, acc) do
        stream_fun = fn ->
          nil
          |> __MODULE__.stream(return: :object, page_size: 100)
          |> Enum.to_list()
        end

        case :rpc.call(node, Kernel, :apply, [stream_fun, []]) do
          {:badrpc, _} -> {:cont, acc}
          entries -> {:halt, entries}
        end
      end
    end
  end

  @impl true
  def init(opts) do
    cache = Keyword.fetch!(opts, :cache)
    task_sup_opts = Keyword.get(opts, :task_supervisor_opts, [])

    # import all cached entries from another node
    :ok = cache.import()

    {:ok, [{Task.Supervisor, [name: cache.__task_sup__] ++ task_sup_opts}]}
  end

  @impl true
  def get(cache, key, opts) do
    cache.__primary__.__adapter__.get(cache.__primary__, key, opts)
  end

  @impl true
  def get_many(cache, keys, opts) do
    cache.__primary__.__adapter__.get_many(cache.__primary__, keys, opts)
  end

  @impl true
  def set(cache, object, opts) do
    with_transaction(cache, :set, [object.key], [object, opts], opts)
  end

  @impl true
  def set_many(cache, objects, opts) do
    keys = for obj <- objects, do: obj.key
    with_transaction(cache, :set_many, keys, [objects, opts], opts)
  end

  @impl true
  def delete(cache, key, opts) do
    with_transaction(cache, :delete, [key], [key, opts], opts)
  end

  @impl true
  def take(cache, key, opts) do
    with_transaction(cache, :take, [key], [key, opts], opts)
  end

  @impl true
  def has_key?(cache, key) do
    cache.__primary__.__adapter__.has_key?(cache.__primary__, key)
  end

  @impl true
  def object_info(cache, key, attr) do
    cache.__primary__.__adapter__.object_info(cache.__primary__, key, attr)
  end

  @impl true
  def expire(cache, key, ttl) do
    cache.__primary__.__adapter__.expire(cache.__primary__, key, ttl)
  end

  @impl true
  def update_counter(cache, key, incr, opts) do
    with_transaction(cache, :update_counter, [key], [key, incr, opts], opts)
  end

  @impl true
  def size(cache) do
    cache.__primary__.__adapter__.size(cache.__primary__)
  end

  @impl true
  def flush(cache) do
    # This operation locks all later write-like operations, but not the ones
    # taking place at the moment the flush is performed, this may yield to
    # inconsistency issues. Come up with a better solution.
    with_transaction(cache, :flush)
  end

  ## Queryable

  @impl true
  def all(cache, query, opts) do
    cache.__primary__.__adapter__.all(cache.__primary__, query, opts)
  end

  @impl true
  def stream(cache, query, opts) do
    cache.__primary__.__adapter__.stream(cache.__primary__, query, opts)
  end

  ## Private Functions

  defp with_transaction(cache, action, keys \\ [:"$global_lock"], args \\ [], opts \\ []) do
    # Encapsulation is being broken here since we are accessing to the internal
    # table `:global_locks` managed by `:global`, but thus far, it was the
    # simplest and fastest way to block all write-like operations when the
    # `flush` action is performed or a new node is joined and the entries are
    # being imported to it from another node. Perhaps find a better way to
    # address these scenarios.
    case :ets.lookup(:global_locks, {cache, :"$global_lock"}) do
      [_] ->
        :ok = Process.sleep(1)
        with_transaction(cache, action, keys, args, opts)

      [] ->
        transaction(
          cache,
          fn ->
            multi_call(cache, action, args, opts)
          end,
          keys: keys,
          nodes: cache.__nodes__
        )
    end
  end

  defp multi_call(cache, action, args, opts) do
    cache.__task_sup__
    |> RPC.multi_call(
      cache.__nodes__,
      cache.__primary__.__adapter__,
      action,
      [cache.__primary__ | args],
      opts
    )
    |> handle_rpc_multi_call(action)
  end

  defp handle_rpc_multi_call({res, []}, _action), do: hd(res)

  defp handle_rpc_multi_call({_, errors}, action) do
    raise Nebulex.RPCMultiCallError, action: action, errors: errors
  end
end
