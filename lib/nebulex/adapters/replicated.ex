defmodule Nebulex.Adapters.Replicated do
  @moduledoc ~S"""
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

  We can define a replicated cache as follows:

      defmodule MyApp.ReplicatedCache do
        use Nebulex.Cache,
          otp_app: :my_app,
          adapter: Nebulex.Adapters.Replicated
      end

  Where the configuration for the cache must be in your application environment,
  usually defined in your `config/config.exs`:

      config :my_app, MyApp.ReplicatedCache,
        primary: [
          adapter: Nebulex.Adapters.Local,
          gc_interval: 86_400_000,
          backend: :shards,
          partitions: System.schedulers_online()
        ]

  For more information about the usage, see `Nebulex.Cache` documentation.

  ## Options

  This adapter supports the following options and all of them can be given via
  the cache configuration:

    * `:primary` - The options that will be passed to the adapter associated
      with the local primary store. These options depend on the adapter to use,
      except for the shared option `adapter:` (see shared primary options
      below).

    * `task_supervisor_opts` - Start-time options passed to
      `Task.Supervisor.start_link/1` when the adapter is initialized.

    * `:bootstrap_timeout` - a timeout in milliseconds that bootstrap process
      will wait after the cache supervision tree is started so the data can be
      imported from remote nodes. Defaults to `1000`.

  ## Shared Primary Options

    * `:adapter` - The adapter to be used for the replicated cache as the
      local primary store. Defaults to `Nebulex.Adapters.Local`.

  **The rest of the options depend on the adapter to use.**

  ## Runtime options

  These options apply to all adapter's functions.

    * `:timeout` - The time-out value in milliseconds for the command that
      will be executed. If the timeout is exceeded, then the current process
      will exit. For executing a command on remote nodes, this adapter uses
      `Task.await/2` internally for receiving the result, so this option tells
      how much time the adapter should wait for it. If the timeout is exceeded,
      the task is shut down but the current process doesn't exit, only the
      result associated with that task is skipped in the reduce phase.

  ## Extended API

  This adapter provides one additional convenience function for retrieving
  the cluster nodes associated with the given cache `name`:

      MyCache.nodes()
      MyCache.nodes(:cache_name)
  """

  # Provide Cache Implementation
  @behaviour Nebulex.Adapter
  @behaviour Nebulex.Adapter.Queryable

  # Inherit default transaction implementation
  use Nebulex.Adapter.Transaction

  # Inherit default persistence implementation
  use Nebulex.Adapter.Persistence

  import Nebulex.Helpers

  alias Nebulex.Cache.Cluster
  alias Nebulex.RPC

  ## Adapter

  @impl true
  defmacro __before_compile__(_env) do
    quote do
      @doc """
      A convenience function for getting the cluster nodes.
      """
      def nodes(name \\ __MODULE__), do: Cluster.get_nodes(name)
    end
  end

  @impl true
  def init(opts) do
    # required cache module and name
    cache = Keyword.fetch!(opts, :cache)
    name = opts[:name] || cache

    # set up the primary cache store
    primary = Keyword.get(opts, :primary, [])
    {primary_adapter, primary} = Keyword.pop(primary, :adapter, Nebulex.Adapters.Local)
    primary_adapter = assert_behaviour(primary_adapter, Nebulex.Adapter, "adapter")
    primary = [name: normalize_module_name([name, Primary])] ++ primary
    {:ok, primary_child_spec, primary_meta} = primary_adapter.init(primary)

    # task supervisor to execute parallel and/or remote commands
    task_sup_name = normalize_module_name([name, TaskSupervisor])
    task_sup_opts = Keyword.get(opts, :task_supervisor_opts, [])

    # bootstrap timeout in milliseconds
    bootstrap_timeout = Keyword.get(opts, :bootstrap_timeout, 1000)

    meta = %{
      name: name,
      cache: cache,
      primary: primary_adapter,
      primary_meta: primary_meta,
      task_sup: task_sup_name,
      bootstrap_timeout: bootstrap_timeout
    }

    child_spec =
      Nebulex.Adapters.Supervisor.child_spec(
        name: normalize_module_name([name, Supervisor]),
        strategy: :rest_for_one,
        children: [
          primary_child_spec,
          {Nebulex.Adapters.Replicated.Bootstrap, meta},
          {Task.Supervisor, [name: task_sup_name] ++ task_sup_opts}
        ]
      )

    # join the cache to the cluster
    :ok = Cluster.join(name)

    {:ok, child_spec, meta}
  rescue
    e in ArgumentError ->
      reraise RuntimeError, e.message, __STACKTRACE__
  end

  @impl true
  def get(%{primary: primary, primary_meta: primary_meta}, key, opts) do
    primary.get(primary_meta, key, opts)
  end

  @impl true
  def get_all(%{primary: primary, primary_meta: primary_meta}, keys, opts) do
    primary.get_all(primary_meta, keys, opts)
  end

  @impl true
  def put(adapter_meta, key, value, ttl, on_write, opts) do
    with_transaction(adapter_meta, :put, [key], [key, value, ttl, on_write, opts], opts)
  end

  @impl true
  def put_all(adapter_meta, entries, ttl, on_write, opts) do
    keys = for {k, _} <- entries, do: k
    with_transaction(adapter_meta, :put_all, keys, [entries, ttl, on_write, opts], opts)
  end

  @impl true
  def delete(adapter_meta, key, opts) do
    with_transaction(adapter_meta, :delete, [key], [key, opts], opts)
  end

  @impl true
  def take(adapter_meta, key, opts) do
    with_transaction(adapter_meta, :take, [key], [key, opts], opts)
  end

  @impl true
  def incr(adapter_meta, key, incr, ttl, opts) do
    with_transaction(adapter_meta, :incr, [key], [key, incr, ttl, opts], opts)
  end

  @impl true
  def has_key?(%{primary: primary, primary_meta: primary_meta}, key) do
    primary.has_key?(primary_meta, key)
  end

  @impl true
  def ttl(%{primary: primary, primary_meta: primary_meta}, key) do
    primary.ttl(primary_meta, key)
  end

  @impl true
  def expire(adapter_meta, key, ttl) do
    with_transaction(adapter_meta, :expire, [key], [key, ttl])
  end

  @impl true
  def touch(adapter_meta, key) do
    with_transaction(adapter_meta, :touch, [key], [key])
  end

  @impl true
  def size(%{primary: primary, primary_meta: primary_meta}) do
    primary.size(primary_meta)
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
  def all(%{primary: primary, primary_meta: primary_meta}, query, opts) do
    primary.all(primary_meta, query, opts)
  end

  @impl true
  def stream(%{primary: primary, primary_meta: primary_meta}, query, opts) do
    primary.stream(primary_meta, query, opts)
  end

  ## Private Functions

  defp with_transaction(
         %{name: name} = adapter_meta,
         action,
         keys \\ [:"$global_lock"],
         args \\ [],
         opts \\ []
       ) do
    # Encapsulation is being broken here since we are accessing to the internal
    # table `:global_locks` managed by `:global`, but thus far, it was the
    # simplest and fastest way to block all write-like operations when the
    # `flush` action is performed or a new node is joined and the entries are
    # being imported to it from another node. Perhaps find a better way for
    # addressing these scenarios.
    case :ets.lookup(:global_locks, {name, :"$global_lock"}) do
      [_] ->
        :ok = Process.sleep(1)
        with_transaction(adapter_meta, action, keys, args, opts)

      [] ->
        transaction(
          adapter_meta,
          [keys: keys, nodes: Cluster.get_nodes(name)],
          fn ->
            multi_call(adapter_meta, action, args, opts)
          end
        )
    end
  end

  defp multi_call(
         %{name: name, task_sup: task_sup, primary: primary, primary_meta: primary_meta},
         action,
         args,
         opts
       ) do
    task_sup
    |> RPC.multi_call(
      Cluster.get_nodes(name),
      primary,
      action,
      [primary_meta | args],
      opts
    )
    |> handle_rpc_multi_call(action)
  end

  defp handle_rpc_multi_call({res, []}, _action), do: hd(res)

  defp handle_rpc_multi_call({_, errors}, action) do
    raise Nebulex.RPCMultiCallError, action: action, errors: errors
  end
end

defmodule Nebulex.Adapters.Replicated.Bootstrap do
  @moduledoc false
  use GenServer

  import Nebulex.Helpers

  alias Nebulex.Cache.Cluster
  alias Nebulex.Entry

  @doc false
  def start_link(%{name: name} = adapter_meta) do
    GenServer.start_link(
      __MODULE__,
      adapter_meta,
      name: normalize_module_name([name, Bootstrap])
    )
  end

  @impl true
  def init(%{bootstrap_timeout: timeout} = adapter_meta) do
    timer_ref = Process.send_after(self(), :import, timeout)
    {:ok, %{timer_ref: timer_ref, adapter_meta: adapter_meta}}
  end

  @impl true
  def handle_info(:import, %{timer_ref: timer_ref, adapter_meta: adapter_meta} = state) do
    _ = Process.cancel_timer(timer_ref)
    :ok = import_from_nodes(adapter_meta)
    {:noreply, state}
  end

  defp import_from_nodes(%{name: name, cache: cache, primary: primary, primary_meta: primary_meta}) do
    cluster_nodes = Cluster.get_nodes(name)

    case cluster_nodes -- [node()] do
      [] ->
        :ok

      nodes ->
        cache.transaction(
          [
            keys: [:"$global_lock"],
            nodes: cluster_nodes
          ],
          fn ->
            nodes
            |> Enum.reduce_while([], &stream_entries(cache, &1, &2))
            |> Enum.each(&primary.put(primary_meta, &1.key, &1.value, Entry.ttl(&1), :put, []))
          end
        )
    end
  end

  defp stream_entries(cache, node, acc) do
    # coveralls-ignore-start
    stream_fun = fn ->
      :unexpired
      |> cache.stream(return: :entry, page_size: 10)
      |> Stream.map(& &1)
      |> Enum.to_list()
    end

    # coveralls-ignore-stop

    case :rpc.call(node, Kernel, :apply, [stream_fun, []]) do
      {:badrpc, _} -> {:cont, acc}
      entries -> {:halt, entries}
    end
  end
end
