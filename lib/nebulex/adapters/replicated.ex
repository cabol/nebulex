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

  For more information about the usage, see `Nebulex.Cache` documentation.

  ## Options

  This adapter supports the following options and all of them can be given via
  the cache configuration:

    * `:primary` - The options that will be passed to the adapter associated
      with the local primary storage. These options will depend on the local
      adapter to use.

    * `task_supervisor_opts` - Start-time options passed to
      `Task.Supervisor.start_link/1` when the adapter is initialized.

    * `:bootstrap_timeout` - a timeout in milliseconds that bootstrap process
      will wait after the cache supervision tree is started so the data can be
      imported from remote nodes. Defaults to `1000`.

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

  ## Extended API

  This adapter provides some additional convenience functions to the
  `Nebulex.Cache` API.

  Retrieving the primary storage or local cache module:

      MyCache.__primary__()

  Retrieving the cluster nodes associated with the given cache name:

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

  alias Nebulex.Cache.{Cluster, Stats}
  alias Nebulex.RPC

  ## Adapter

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
      def nodes(name \\ __MODULE__), do: Cluster.get_nodes(name)
    end
  end

  @impl true
  def init(opts) do
    # required cache name
    cache = Keyword.fetch!(opts, :cache)
    name = opts[:name] || cache

    # maybe use stats
    stat_counter = opts[:stat_counter] || Stats.init(opts)

    # primary cache options
    primary_opts =
      opts
      |> Keyword.get(:primary, [])
      |> Keyword.put(:stat_counter, stat_counter)

    # maybe put a name to primary storage
    primary_opts =
      if opts[:name],
        do: [name: normalize_module_name([name, Primary])] ++ primary_opts,
        else: primary_opts

    # task supervisor to execute parallel and/or remote commands
    task_sup_name = normalize_module_name([name, TaskSupervisor])
    task_sup_opts = Keyword.get(opts, :task_supervisor_opts, [])

    # bootstrap timeout in milliseconds
    bootstrap_timeout = Keyword.get(opts, :bootstrap_timeout, 1500)

    meta = %{
      name: name,
      primary_name: primary_opts[:name],
      task_sup: task_sup_name,
      stat_counter: stat_counter,
      bootstrap_timeout: bootstrap_timeout
    }

    child_spec =
      Nebulex.Adapters.Supervisor.child_spec(
        name: normalize_module_name([name, Supervisor]),
        strategy: :rest_for_one,
        children: [
          {cache.__primary__, primary_opts},
          {Nebulex.Adapters.Replicated.Bootstrap, Map.put(meta, :cache, cache)},
          {Task.Supervisor, [name: task_sup_name] ++ task_sup_opts}
        ]
      )

    # join the cache to the cluster
    :ok = Cluster.join(name)

    {:ok, child_spec, meta}
  end

  @impl true
  def get(meta, key, opts) do
    with_dynamic_cache(meta, :get, [key, opts])
  end

  @impl true
  def get_all(meta, keys, opts) do
    with_dynamic_cache(meta, :get_all, [keys, opts])
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
    keys = for {k, _} <- entries, do: k
    action = if on_write == :put_new, do: :put_new_all, else: :put_all
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
  def incr(adapter_meta, key, incr, _ttl, opts) do
    with_transaction(adapter_meta, :incr, [key], [key, incr, opts], opts)
  end

  @impl true
  def has_key?(meta, key) do
    with_dynamic_cache(meta, :has_key?, [key])
  end

  @impl true
  def ttl(meta, key) do
    with_dynamic_cache(meta, :ttl, [key])
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
  def size(meta) do
    with_dynamic_cache(meta, :size, [])
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
  def all(meta, query, opts) do
    with_dynamic_cache(meta, :all, [query, opts])
  end

  @impl true
  def stream(meta, query, opts) do
    with_dynamic_cache(meta, :stream, [query, opts])
  end

  ## Transaction

  @impl true
  def transaction(%{name: name} = adapter_meta, opts, fun) do
    super(adapter_meta, Keyword.put(opts, :nodes, Cluster.get_nodes(name)), fun)
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
    case :ets.lookup(:global_locks, {pid, :"$global_lock"}) do
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
         %{name: name, task_sup: task_sup} = meta,
         action,
         args,
         opts
       ) do
    task_sup
    |> RPC.multi_call(
      Cluster.get_nodes(name),
      __MODULE__,
      :with_dynamic_cache,
      [meta, action, args],
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

  alias Nebulex.Adapter
  alias Nebulex.Adapters.Replicated
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
  def handle_info(:import, %{timer_ref: timer_ref, adapter_meta: %{pid: _} = meta} = state) do
    _ = Process.cancel_timer(timer_ref)
    :ok = import_from_nodes(meta)
    {:noreply, state}
  end

  def handle_info(:import, %{adapter_meta: %{name: name}} = state) do
    Adapter.with_meta(name, fn _adapter, adapter_meta ->
      handle_info(:import, %{state | adapter_meta: adapter_meta})
    end)
  end

  defp import_from_nodes(%{name: name, cache: cache} = meta) do
    cluster_nodes = Cluster.get_nodes(name)

    case cluster_nodes -- [node()] do
      [] ->
        :ok

      nodes ->
        Replicated.transaction(
          meta,
          [
            keys: [:"$global_lock"],
            nodes: cluster_nodes
          ],
          fn ->
            nodes
            |> Enum.reduce_while([], &stream_entries(meta, &1, &2))
            |> Enum.each(&cache.__primary__.put(&1.key, &1.value, ttl: Entry.ttl(&1)))
          end
        )
    end
  end

  defp stream_entries(meta, node, acc) do
    # FIXME: this is because coveralls does not check this as covered
    # coveralls-ignore-start
    stream_fun = fn ->
      meta
      |> Replicated.stream(:unexpired, return: :entry, page_size: 10)
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
