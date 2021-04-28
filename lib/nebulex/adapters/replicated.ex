defmodule Nebulex.Adapters.Replicated do
  @moduledoc ~S"""
  Built-in adapter for replicated cache topology.

  ## Overall features

    * Replicated cache topology.
    * Configurable primary storage adapter.
    * Cache-level locking when deleting all entries or adding new nodes.
    * Key-level (or entry-level) locking for key-based write-like operations.
    * Support for transactions via Erlang global name registration facility.
    * Stats support rely on the primary storage adapter.

  ## Replicated Cache Topology

  A replicated cache is a clustered, fault tolerant cache where data is fully
  replicated to every member in the cluster. This cache offers the fastest read
  performance with linear performance scalability for reads but poor scalability
  for writes (as writes must be processed by every member in the cluster).
  Because data is replicated to all servers, adding servers does not increase
  aggregate cache capacity.

  There are several challenges to building a reliably replicated cache. The
  first is how to get it to scale and perform well. Updates to the cache have
  to be sent to all cluster nodes, and all cluster nodes have to end up with
  the same data, even if multiple updates to the same piece of data occur at
  the same time. Also, if a cluster node requests a lock, ideally it should
  not have to get all cluster nodes to agree on the lock or at least do it in
  a very efficient way (`:global` is used here), otherwise it will scale
  extremely poorly; yet in the case of a cluster node failure, all of the data
  and lock information must be kept safely.

  The best part of a replicated cache is its access speed. Since the data is
  replicated to each cluster node, it is available for use without any waiting.
  This is referred to as "zero latency access," and is perfect for situations
  in which an application requires the highest possible speed in its data
  access.

  However, there are some limitations:

    * _**Cost Per Update**_ - Updating a replicated cache requires pushing
      the new version of the data to all other cluster members, which will
      limit scalability if there is a high frequency of updates per member.

    * _**Cost Per Entry**_ - The data is replicated to every cluster member,
      so Memory Heap space is used on each member, which will impact
      performance for large caches.

  > Based on **"Distributed Caching Essential Lessons"** by **Cameron Purdy**.

  ## Usage

  When used, the Cache expects the `:otp_app` and `:adapter` as options.
  The `:otp_app` should point to an OTP application that has the cache
  configuration. For example:

      defmodule MyApp.ReplicatedCache do
        use Nebulex.Cache,
          otp_app: :my_app,
          adapter: Nebulex.Adapters.Replicated
      end

  Optionally, you can configure the desired primary storage adapter with the
  option `:primary_storage_adapter`; defaults to `Nebulex.Adapters.Local`.

      defmodule MyApp.ReplicatedCache do
        use Nebulex.Cache,
          otp_app: :my_app,
          adapter: Nebulex.Adapters.Replicated,
          primary_storage_adapter: Nebulex.Adapters.Local
      end

  The configuration for the cache must be in your application environment,
  usually defined in your `config/config.exs`:

      config :my_app, MyApp.ReplicatedCache,
        primary: [
          gc_interval: 3_600_000,
          backend: :shards
        ]

  If your application was generated with a supervisor (by passing `--sup`
  to `mix new`) you will have a `lib/my_app/application.ex` file containing
  the application start callback that defines and starts your supervisor.
  You just need to edit the `start/2` function to start the cache as a
  supervisor on your application's supervisor:

      def start(_type, _args) do
        children = [
          {MyApp.ReplicatedCache, []},
          ...
        ]

  See `Nebulex.Cache` for more information.

  ## Options

  This adapter supports the following options and all of them can be given via
  the cache configuration:

    * `:primary` - The options that will be passed to the adapter associated
      with the local primary storage. These options will depend on the local
      adapter to use.

    * `:task_supervisor_opts` - Start-time options passed to
      `Task.Supervisor.start_link/1` when the adapter is initialized.

  ## Shared options

  Almost all of the cache functions outlined in `Nebulex.Cache` module
  accept the following options:

    * `:timeout` - The time-out value in milliseconds for the command that
      will be executed. If the timeout is exceeded, then the current process
      will exit. For executing a command on remote nodes, this adapter uses
      `Task.await/2` internally for receiving the result, so this option tells
      how much time the adapter should wait for it. If the timeout is exceeded,
      the task is shut down but the current process doesn't exit, only the
      result associated with that task is skipped in the reduce phase.

  ## Stats

  This adapter depends on the primary storage adapter for the stats support.
  Therefore, it is important to ensure the underlying primary storage adapter
  does support stats, otherwise, you may get unexpected errors.

  ## Extended API

  This adapter provides some additional convenience functions to the
  `Nebulex.Cache` API.

  Retrieving the primary storage or local cache module:

      MyCache.__primary__()

  Retrieving the cluster nodes associated with the given cache name:

      MyCache.nodes()

  Joining the cache to the cluster:

      MyCache.join_cluster()

  Leaving the cluster (removes the cache from the cluster):

      MyCache.leave_cluster()

  ## Telemetry events

  This adapter exposes following Telemetry events:

    * `telemetry_prefix ++ [:replication]` - Dispatched by the adapter
      when a replication error occurs due to a write-like operation
      under-the-hood.

      * Measurements: `%{rpc_errors: non_neg_integer}`
      * Metadata:

        ```
        %{
          action: atom,
          cache: module,
          name: atom,
          rpc_errors: [{node, error :: term}]
        }
        ```

    * `telemetry_prefix ++ [:bootstrap]` - Dispatched by the adapter at start
      time when there are errors while synching up with the cluster nodes.

      * Measurements:

        ```
        %{
          failed_nodes: non_neg_integer,
          remote_errors: non_neg_integer
        }
        ```

      * Metadata:

        ```
        %{
          cache: module,
          name: atom,
          failed_nodes: [node],
          remote_errors: [term]
        }
        ```

  ## Caveats of replicated adapter

  As it is explained in the beginning, a replicated topology not only brings
  with advantages (mostly for reads) but also with some limitations and
  challenges.

  This adapter uses global locks (via `:global`) for all operation that modify
  or alter the cache somehow to ensure as much consistency as possible across
  all members of the cluster. These locks may be per key or for the entire cache
  depending on the operation taking place. For that reason, it is very important
  to be aware about those operation that can potentally lead to performance and
  scalability issues, so that you can do a better usage of the replicated
  adapter. The following is with the operations and aspects you should pay
  attention to:

    * Starting and joining a new replicated node to the cluster is the most
      expensive action, because all write-like operations across all members of
      the cluster are blocked until the new node completes the synchronization
      process, which involves copying cached data from any of the existing
      cluster nodes into the new node, and this could be very expensive
      depending on the number of caches entries. For that reason, adding new
      nodes is considered an expensive operation that should happen only from
      time to time.

    * Deleting all entries. When `c:Nebulex.Cache.delete_all/2` action is
      executed, like in the previous case, all write-like operations in all
      members of the cluster are blocked until the deletion action is completed
      (this implies deleting all cached data from all cluster nodes). Therefore,
      deleting all entries from cache is also considered an expensive operation
      that should happen only from time to time.

    * Write-like operations based on a key only block operations related to
      that key across all members of the cluster. This is not as critical as
      the previous two cases but it is something to keep in mind anyway because
      if there is a highly demanded key in terms of writes, that could be also
      a potential bottleneck.

  Summing up, the replicated cache topology along with this adapter should
  be used mainly when the the reads clearly dominate over the writes (e.g.:
  Reads 80% and Writes 20% or less). Besides, operations like deleting all
  entries from cache or adding new nodes must be executed only once in a while
  to avoid performance issues, since they are very expensive.
  """

  # Provide Cache Implementation
  @behaviour Nebulex.Adapter
  @behaviour Nebulex.Adapter.Entry
  @behaviour Nebulex.Adapter.Queryable
  @behaviour Nebulex.Adapter.Stats

  # Inherit default transaction implementation
  use Nebulex.Adapter.Transaction

  # Inherit default persistence implementation
  use Nebulex.Adapter.Persistence

  import Nebulex.Adapter
  import Nebulex.Helpers

  alias Nebulex.Cache.Cluster
  alias Nebulex.{RPC, Telemetry}

  ## Nebulex.Adapter

  @impl true
  defmacro __before_compile__(env) do
    otp_app = Module.get_attribute(env.module, :otp_app)
    opts = Module.get_attribute(env.module, :opts)
    primary = Keyword.get(opts, :primary_storage_adapter, Nebulex.Adapters.Local)

    quote do
      defmodule Primary do
        @moduledoc """
        This is the cache for the primary storage.
        """
        use Nebulex.Cache,
          otp_app: unquote(otp_app),
          adapter: unquote(primary)
      end

      @doc """
      A convenience function for getting the primary storage cache.
      """
      def __primary__, do: Primary

      @doc """
      A convenience function for getting the cluster nodes.
      """
      def nodes do
        Cluster.get_nodes(get_dynamic_cache())
      end

      @doc """
      A convenience function for joining the cache to the cluster.
      """
      def join_cluster do
        Cluster.join(get_dynamic_cache())
      end

      @doc """
      A convenience function for removing the cache from the cluster.
      """
      def leave_cluster do
        Cluster.leave(get_dynamic_cache())
      end
    end
  end

  @impl true
  def init(opts) do
    # Required options
    telemetry_prefix = Keyword.fetch!(opts, :telemetry_prefix)
    cache = Keyword.fetch!(opts, :cache)
    name = opts[:name] || cache

    # Maybe use stats
    stats = get_boolean_option(opts, :stats)

    # Primary cache options
    primary_opts =
      opts
      |> Keyword.get(:primary, [])
      |> Keyword.put(:telemetry_prefix, telemetry_prefix)
      |> Keyword.put_new(:stats, stats)

    # Maybe put a name to primary storage
    primary_opts =
      if opts[:name],
        do: [name: normalize_module_name([name, Primary])] ++ primary_opts,
        else: primary_opts

    # Maybe task supervisor for distributed tasks
    {task_sup_name, children} = sup_child_spec(name, opts)

    # Prepare metadata
    meta = %{
      telemetry_prefix: telemetry_prefix,
      name: name,
      primary_name: primary_opts[:name],
      task_sup: task_sup_name,
      stats: stats
    }

    # Prepare child_spec
    child_spec =
      Nebulex.Adapters.Supervisor.child_spec(
        name: normalize_module_name([name, Supervisor]),
        strategy: :rest_for_one,
        children: [
          {cache.__primary__, primary_opts},
          {__MODULE__.Bootstrap, Map.put(meta, :cache, cache)}
          | children
        ]
      )

    {:ok, child_spec, meta}
  end

  if Code.ensure_loaded?(:erpc) do
    defp sup_child_spec(_name, _opts) do
      {nil, []}
    end
  else
    defp sup_child_spec(name, opts) do
      # Task supervisor to execute parallel and/or remote commands
      task_sup_name = normalize_module_name([name, TaskSupervisor])
      task_sup_opts = Keyword.get(opts, :task_supervisor_opts, [])

      children = [
        {Task.Supervisor, [name: task_sup_name] ++ task_sup_opts}
      ]

      {task_sup_name, children}
    end
  end

  ## Nebulex.Adapter.Entry

  @impl true
  def get(adapter_meta, key, opts) do
    with_span(adapter_meta, :get, fn ->
      with_dynamic_cache(adapter_meta, :get, [key, opts])
    end)
  end

  @impl true
  def get_all(adapter_meta, keys, opts) do
    with_span(adapter_meta, :get_all, fn ->
      with_dynamic_cache(adapter_meta, :get_all, [keys, opts])
    end)
  end

  @impl true
  def put(adapter_meta, key, value, _ttl, :put, opts) do
    :ok = with_transaction(adapter_meta, :put, [key], [key, value, opts], opts)
    true
  end

  def put(adapter_meta, key, value, _ttl, :put_new, opts) do
    with_transaction(adapter_meta, :put_new, [key], [key, value, opts], opts)
  end

  def put(adapter_meta, key, value, _ttl, :replace, opts) do
    with_transaction(adapter_meta, :replace, [key], [key, value, opts], opts)
  end

  @impl true
  def put_all(adapter_meta, entries, _ttl, on_write, opts) do
    action = if on_write == :put_new, do: :put_new_all, else: :put_all
    keys = for {k, _} <- entries, do: k

    with_transaction(adapter_meta, action, keys, [entries, opts], opts) || action == :put_all
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
  def update_counter(adapter_meta, key, amount, _ttl, _default, opts) do
    with_transaction(adapter_meta, :incr, [key], [key, amount, opts], opts)
  end

  @impl true
  def has_key?(adapter_meta, key) do
    with_dynamic_cache(adapter_meta, :has_key?, [key])
  end

  @impl true
  def ttl(adapter_meta, key) do
    with_span(adapter_meta, :ttl, fn ->
      with_dynamic_cache(adapter_meta, :ttl, [key])
    end)
  end

  @impl true
  def expire(adapter_meta, key, ttl) do
    with_transaction(adapter_meta, :expire, [key], [key, ttl])
  end

  @impl true
  def touch(adapter_meta, key) do
    with_transaction(adapter_meta, :touch, [key], [key])
  end

  ## Nebulex.Adapter.Queryable

  @impl true
  def execute(adapter_meta, operation, query, opts) do
    with_span(adapter_meta, operation, fn ->
      do_execute(adapter_meta, operation, query, opts)
    end)
  end

  defp do_execute(%{name: name} = adapter_meta, :delete_all, query, opts) do
    # It is blocked until ongoing write operations finish (if there is any).
    # Similarly, while it is executed, all later write-like operations are
    # blocked until it finishes.
    :global.trans(
      {name, self()},
      fn ->
        multi_call(adapter_meta, :delete_all, [query, opts], opts)
      end,
      Cluster.get_nodes(name)
    )
  end

  defp do_execute(adapter_meta, operation, query, opts) do
    with_dynamic_cache(adapter_meta, operation, [query, opts])
  end

  @impl true
  def stream(adapter_meta, query, opts) do
    with_span(adapter_meta, :stream, fn ->
      with_dynamic_cache(adapter_meta, :stream, [query, opts])
    end)
  end

  ## Nebulex.Adapter.Persistence

  @impl true
  def dump(adapter_meta, path, opts) do
    with_span(adapter_meta, :dump, fn ->
      super(adapter_meta, path, opts)
    end)
  end

  @impl true
  def load(adapter_meta, path, opts) do
    with_span(adapter_meta, :load, fn ->
      super(adapter_meta, path, opts)
    end)
  end

  ## Nebulex.Adapter.Transaction

  @impl true
  def transaction(%{name: name} = adapter_meta, opts, fun) do
    with_span(adapter_meta, :transaction, fn ->
      super(adapter_meta, Keyword.put(opts, :nodes, Cluster.get_nodes(name)), fun)
    end)
  end

  @impl true
  def in_transaction?(adapter_meta) do
    with_span(adapter_meta, :in_transaction?, fn ->
      super(adapter_meta)
    end)
  end

  ## Nebulex.Adapter.Stats

  @impl true
  def stats(adapter_meta) do
    with_span(adapter_meta, :stats, fn ->
      with_dynamic_cache(adapter_meta, :stats, [])
    end)
  end

  ## Helpers

  @doc """
  Helper function to use dynamic cache for internal primary cache storage
  when needed.
  """
  def with_dynamic_cache(%{cache: cache, primary_name: nil}, action, args) do
    apply(cache.__primary__, action, args)
  end

  def with_dynamic_cache(%{cache: cache, primary_name: primary_name}, action, args) do
    cache.__primary__.with_dynamic_cache(primary_name, fn ->
      apply(cache.__primary__, action, args)
    end)
  end

  ## Private Functions

  defp with_transaction(
         %{pid: pid, name: name} = adapter_meta,
         action,
         keys,
         args,
         opts \\ []
       ) do
    multi_call = fn -> multi_call(adapter_meta, action, args, opts) end

    with_span(adapter_meta, action, fn ->
      nodes = Cluster.get_nodes(name)

      # Ensure it waits until ongoing delete_all or sync operations finish,
      # if there's any.
      :global.trans(
        {name, pid},
        fn ->
          # Write-like operation must be wrapped within a transaction
          # to ensure proper replication
          transaction(adapter_meta, [keys: keys, nodes: nodes], multi_call)
        end,
        nodes
      )
    end)
  end

  defp multi_call(%{name: name, task_sup: task_sup} = meta, action, args, opts) do
    task_sup
    |> RPC.multi_call(
      Cluster.get_nodes(name),
      __MODULE__,
      :with_dynamic_cache,
      [meta, action, args],
      opts
    )
    |> handle_rpc_multi_call(Map.put(meta, :action, action))
  end

  defp handle_rpc_multi_call({res, []}, _meta), do: hd(res)

  defp handle_rpc_multi_call({res, {:sanitized, {[], rep_errors}}}, meta) do
    dispatch_replication_error(meta, rep_errors)
    hd(res)
  end

  defp handle_rpc_multi_call(
         {responses, {:sanitized, {errors, rep_errors}}},
         %{action: action} = meta
       ) do
    dispatch_replication_error(meta, rep_errors)
    raise Nebulex.RPCMultiCallError, action: action, responses: responses, errors: errors
  end

  defp handle_rpc_multi_call({responses, errors}, meta) do
    handle_rpc_multi_call({responses, {:sanitized, sanitize_errors(errors)}}, meta)
  end

  defp sanitize_errors(errors) do
    Enum.reduce(errors, {[], []}, fn
      {{:error, {:exception, %Nebulex.RegistryLookupError{} = error, _}}, node}, {acc1, acc2} ->
        # The cache was not found in the node, maybe it was stopped and
        # "Process Groups" is not updated yet, then ignore the error
        {acc1, [{node, error} | acc2]}

      {{:error, {:erpc, :noconnection}}, node}, {acc1, acc2} ->
        # Remote node is down and maybe the "Process Groups" is not updated yet
        {acc1, [{node, :noconnection} | acc2]}

      error, {acc1, acc2} ->
        {[error | acc1], acc2}
    end)
  end

  defp dispatch_replication_error(meta, rep_errors) do
    if meta.telemetry_prefix do
      Telemetry.execute(
        meta.telemetry_prefix ++ [:replication],
        %{rpc_errors: length(rep_errors)},
        meta |> Map.take([:cache, :name, :action]) |> Map.put(:rpc_errors, rep_errors)
      )
    end
  end
end

defmodule Nebulex.Adapters.Replicated.Bootstrap do
  @moduledoc false
  use GenServer

  import Nebulex.Helpers

  alias Nebulex.{Adapter, Entry, Telemetry}
  alias Nebulex.Adapters.Replicated
  alias Nebulex.Cache.Cluster

  # Max retries in intervals of 1 ms (5 seconds).
  # If in 5 seconds the cache has not started, stop the server.
  @max_retries 5000

  ## API

  @doc false
  def start_link(%{name: name} = adapter_meta) do
    GenServer.start_link(
      __MODULE__,
      adapter_meta,
      name: normalize_module_name([name, Bootstrap])
    )
  end

  ## GenServer Callbacks

  @impl true
  def init(adapter_meta) do
    # Trap exit signals to run cleanup job
    _ = Process.flag(:trap_exit, true)

    # Ensure joining the cluster only when the cache supervision tree is started
    :ok = Cluster.join(adapter_meta.name)

    # Set a global lock to stop any write operation
    # until the synchronization process finishes
    :ok = lock(adapter_meta.name)

    # Init retries
    state = Map.put(adapter_meta, :retries, 0)

    # Start bootstrap process
    {:ok, state, 1}
  end

  @impl true
  def handle_info(:timeout, %{pid: pid} = state) when is_pid(pid) do
    # Start synchronization process
    :ok = sync_data(state)

    # Delete global lock set when the server started
    :ok = unlock(state.name)

    # Bootstrap process finished
    {:noreply, state}
  end

  def handle_info(:timeout, %{name: name, retries: retries} = state)
      when retries < @max_retries do
    Adapter.with_meta(name, fn _adapter, adapter_meta ->
      handle_info(:timeout, adapter_meta)
    end)
  rescue
    ArgumentError -> {:noreply, %{state | retries: retries + 1}, 1}
  end

  def handle_info(:timeout, state) do
    # coveralls-ignore-start
    {:stop, :normal, state}
    # coveralls-ignore-stop
  end

  @impl true
  def terminate(_reason, state) do
    # Ensure leaving the cluster when the cache stops
    :ok = Cluster.leave(state.name)
  end

  ## Helpers

  defp lock(name) do
    nodes = Cluster.get_nodes(name)
    true = :global.set_lock({name, self()}, nodes)
    :ok
  end

  defp unlock(name) do
    nodes = Cluster.get_nodes(name)
    true = :global.del_lock({name, self()}, nodes)
    :ok
  end

  # FIXME: this is because coveralls does not mark this as covered
  # coveralls-ignore-start

  defp sync_data(%{name: name} = adapter_meta) do
    cluster_nodes = Cluster.get_nodes(name)

    case cluster_nodes -- [node()] do
      [] ->
        :ok

      nodes ->
        # Sync process:
        # 1. Push a new generation on all cluster nodes to make the newer one
        #    empty.
        # 2. Copy cached data from one of the cluster nodes; entries will be
        #    stremed from the older generation since the newer one should be
        #    empty.
        # 3. Push a new generation on the current/new node to make it a mirror
        #    of the other cluster nodes.
        # 4. Reset GC timer for ell cluster nodes (making the generation timer
        #    gap among cluster nodes as small as possible).
        with :ok <- maybe_run_on_nodes(adapter_meta, nodes, :new_generation),
             :ok <- copy_entries_from_nodes(adapter_meta, nodes),
             :ok <- maybe_run_on_nodes(adapter_meta, [node()], :new_generation),
             :ok <- maybe_run_on_nodes(adapter_meta, nodes, :reset_generation_timer) do
          :ok
        end
    end
  end

  defp maybe_run_on_nodes(%{cache: cache} = adapter_meta, nodes, fun) do
    if cache.__primary__.__adapter__() == Nebulex.Adapters.Local do
      nodes
      |> :rpc.multicall(Replicated, :with_dynamic_cache, [adapter_meta, fun, []])
      |> handle_multicall(adapter_meta)
    else
      :ok
    end
  end

  defp handle_multicall({responses, failed_nodes}, adapter_meta) do
    {_ok, errors} = Enum.split_with(responses, &(&1 == :ok))

    dispatch_bootstrap_error(
      adapter_meta,
      %{failed_nodes: length(failed_nodes), remote_errors: length(errors)},
      %{failed_nodes: failed_nodes, remote_errors: errors}
    )
  end

  defp copy_entries_from_nodes(adapter_meta, nodes) do
    nodes
    |> Enum.reduce_while([], &stream_entries(adapter_meta, &1, &2))
    |> Enum.each(
      &Replicated.with_dynamic_cache(
        adapter_meta,
        :put,
        [&1.key, &1.value, [ttl: Entry.ttl(&1)]]
      )
    )
  end

  defp stream_entries(meta, node, acc) do
    stream_fun = fn ->
      meta
      |> Replicated.stream(nil, return: :entry, page_size: 100)
      |> Stream.filter(&(not Entry.expired?(&1)))
      |> Stream.map(& &1)
      |> Enum.to_list()
    end

    case :rpc.call(node, Kernel, :apply, [stream_fun, []]) do
      {:badrpc, _} -> {:cont, acc}
      entries -> {:halt, entries}
    end
  end

  defp dispatch_bootstrap_error(adapter_meta, measurements, metadata) do
    if adapter_meta.telemetry_prefix do
      Telemetry.execute(
        adapter_meta.telemetry_prefix ++ [:bootstrap],
        measurements,
        adapter_meta |> Map.take([:cache, :name]) |> Map.merge(metadata)
      )
    end
  end

  # coveralls-ignore-stop
end
