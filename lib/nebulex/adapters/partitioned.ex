defmodule Nebulex.Adapters.Partitioned do
  @moduledoc ~S"""
  Built-in adapter for partitioned cache topology.

  ## Overall features

    * Partitioned cache topology (Sharding Distribution Model).
    * Configurable primary storage adapter.
    * Configurable Keyslot to distributed the keys across the cluster members.
    * Support for transactions via Erlang global name registration facility.
    * Stats support rely on the primary storage adapter.

  ## Partitioned Cache Topology

  There are several key points to consider about a partitioned cache:

    * _**Partitioned**_: The data in a distributed cache is spread out over
      all the servers in such a way that no two servers are responsible for
      the same piece of cached data. This means that the size of the cache
      and the processing power associated with the management of the cache
      can grow linearly with the size of the cluster. Also, it means that
      operations against data in the cache can be accomplished with a
      "single hop," in other words, involving at most one other server.

    * _**Load-Balanced**_:  Since the data is spread out evenly over the
      servers, the responsibility for managing the data is automatically
      load-balanced across the cluster.

    * _**Ownership**_: Exactly one node in the cluster is responsible for each
      piece of data in the cache.

    * _**Point-To-Point**_: The communication for the partitioned cache is all
      point-to-point, enabling linear scalability.

    * _**Location Transparency**_: Although the data is spread out across
      cluster nodes, the exact same API is used to access the data, and the
      same behavior is provided by each of the API methods. This is called
      location transparency, which means that the developer does not have to
      code based on the topology of the cache, since the API and its behavior
      will be the same with a local cache, a replicated cache, or a distributed
      cache.

    * _**Failover**_: Failover of a distributed cache involves promoting backup
      data to be primary storage. When a cluster node fails, all remaining
      cluster nodes determine what data each holds in backup that the failed
      cluster node had primary responsible for when it died. Those data becomes
      the responsibility of whatever cluster node was the backup for the data.
      However, this adapter does not provide fault-tolerance implementation,
      each piece of data is kept in a single node/machine (via sharding), then,
      if a node fails, the data kept by this node won't be available for the
      rest of the cluster memebers.

  > Based on **"Distributed Caching Essential Lessons"** by **Cameron Purdy**
    and [Coherence Partitioned Cache Service][oracle-pcs].

  [oracle-pcs]: https://docs.oracle.com/cd/E13924_01/coh.340/e13819/partitionedcacheservice.htm

  ## Additional implementation notes

  `:pg2` or `:pg` (>= OTP 23) is used under-the-hood by the adapter to manage
  the cluster nodes. When the partitioned cache is started in a node, it creates
  a group and joins it (the cache supervisor PID is joined to the group). Then,
  when a function is invoked, the adapter picks a node from the group members,
  and then the function is executed on that specific node. In the same way,
  when a partitioned cache supervisor dies (the cache is stopped or killed for
  some reason), the PID of that process is automatically removed from the PG
  group; this is why it's recommended to use consistent hashing for distributing
  the keys across the cluster nodes.

  > **NOTE:** `pg2` will be replaced by `pg` in future, since the `pg2` module
    is deprecated as of OTP 23 and scheduled for removal in OTP 24.

  This adapter depends on a local cache adapter (primary storage), it adds
  a thin layer on top of it in order to distribute requests across a group
  of nodes, where is supposed the local cache is running already. However,
  you don't need to define any additional cache module for the primary
  storage, instead, the adapter initializes it automatically (it adds the
  primary storage as part of the supervision tree) based on the given
  options within the `primary_storage_adapter:` argument.

  ## Usage

  When used, the Cache expects the `:otp_app` and `:adapter` as options.
  The `:otp_app` should point to an OTP application that has the cache
  configuration. For example:

      defmodule MyApp.PartitionedCache do
        use Nebulex.Cache,
          otp_app: :my_app,
          adapter: Nebulex.Adapters.Partitioned
      end

  Optionally, you can configure the desired primary storage adapter with the
  option `:primary_storage_adapter`; defaults to `Nebulex.Adapters.Local`.

      defmodule MyApp.PartitionedCache do
        use Nebulex.Cache,
          otp_app: :my_app,
          adapter: Nebulex.Adapters.Partitioned,
          primary_storage_adapter: Nebulex.Adapters.Local
      end

  Also, you can provide a custom keyslot function:

      defmodule MyApp.PartitionedCache do
        use Nebulex.Cache,
          otp_app: :my_app,
          adapter: Nebulex.Adapters.Partitioned,
          primary_storage_adapter: Nebulex.Adapters.Local

        @behaviour Nebulex.Adapter.Keyslot

        @impl true
        def hash_slot(key, range) do
          key
          |> :erlang.phash2()
          |> :jchash.compute(range)
        end
      end

  Where the configuration for the cache must be in your application environment,
  usually defined in your `config/config.exs`:

      config :my_app, MyApp.PartitionedCache,
        keyslot: MyApp.PartitionedCache,
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
          {MyApp.PartitionedCache, []},
          ...
        ]

  See `Nebulex.Cache` for more information.

  ## Options

  This adapter supports the following options and all of them can be given via
  the cache configuration:

    * `:primary` - The options that will be passed to the adapter associated
      with the local primary storage. These options will depend on the local
      adapter to use.

    * `:keyslot` - Defines the module implementing `Nebulex.Adapter.Keyslot`
      behaviour.

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

  Retrieving the cluster nodes associated with the given cache `name`:

      MyCache.nodes()

  Get a cluster node based on the given `key`:

      MyCache.get_node("mykey")

  Joining the cache to the cluster:

      MyCache.join_cluster()

  Leaving the cluster (removes the cache from the cluster):

      MyCache.leave_cluster()

  ## Caveats of partitioned adapter

  For `c:Nebulex.Cache.get_and_update/3` and `c:Nebulex.Cache.update/4`,
  they both have a parameter that is the anonymous function, and it is compiled
  into the module where it is created, which means it necessarily doesn't exists
  on remote nodes. To ensure they work as expected, you must provide functions
  from modules existing in all nodes of the group.
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

  # Inherit default keyslot implementation
  use Nebulex.Adapter.Keyslot

  import Nebulex.Adapter
  import Nebulex.Helpers

  alias Nebulex.Cache.Cluster
  alias Nebulex.RPC

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
      A convenience function to get the node of the given `key`.
      """
      def get_node(key) do
        with_meta(get_dynamic_cache(), fn _adapter, %{name: name, keyslot: keyslot} ->
          Cluster.get_node(name, key, keyslot)
        end)
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

    # Keyslot module for selecting nodes
    keyslot =
      opts
      |> Keyword.get(:keyslot, __MODULE__)
      |> assert_behaviour(Nebulex.Adapter.Keyslot, "keyslot")

    # Maybe task supervisor for distributed tasks
    {task_sup_name, children} = sup_child_spec(name, opts)

    # Prepare metadata
    meta = %{
      telemetry_prefix: telemetry_prefix,
      name: name,
      primary_name: primary_opts[:name],
      task_sup: task_sup_name,
      keyslot: keyslot,
      stats: stats
    }

    # Prepare child_spec
    child_spec =
      Nebulex.Adapters.Supervisor.child_spec(
        name: normalize_module_name([name, Supervisor]),
        strategy: :rest_for_one,
        # children: [{cache.__primary__, primary_opts}] ++ children,
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
      # task supervisor to execute parallel and/or remote commands
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
    call(adapter_meta, key, :get, [key, opts], opts)
  end

  @impl true
  def get_all(adapter_meta, keys, opts) do
    with_span(adapter_meta, :get_all, fn ->
      do_get_all(adapter_meta, keys, opts)
    end)
  end

  defp do_get_all(adapter_meta, keys, opts) do
    map_reduce(
      keys,
      adapter_meta,
      :get_all,
      [opts],
      Keyword.get(opts, :timeout),
      {
        %{},
        fn
          {:ok, res}, _, acc when is_map(res) ->
            Map.merge(acc, res)

          _, _, acc ->
            acc
        end
      }
    )
  end

  @impl true
  def put(adapter_meta, key, value, _ttl, on_write, opts) do
    do_put(on_write, adapter_meta, key, value, opts)
  end

  defp do_put(:put, adapter_meta, key, value, opts) do
    :ok = call(adapter_meta, key, :put, [key, value, opts], opts)
    true
  end

  defp do_put(:put_new, adapter_meta, key, value, opts) do
    call(adapter_meta, key, :put_new, [key, value, opts], opts)
  end

  defp do_put(:replace, adapter_meta, key, value, opts) do
    call(adapter_meta, key, :replace, [key, value, opts], opts)
  end

  @impl true
  def put_all(adapter_meta, entries, _ttl, :put, opts) do
    with_span(adapter_meta, :put_all, fn ->
      do_put_all(:put_all, adapter_meta, entries, opts)
    end)
  end

  def put_all(adapter_meta, entries, _ttl, :put_new, opts) do
    with_span(adapter_meta, :put_new_all, fn ->
      do_put_all(:put_new_all, adapter_meta, entries, opts)
    end)
  end

  def do_put_all(action, adapter_meta, entries, opts) do
    reducer = {
      {true, []},
      fn
        {:ok, :ok}, {_, {_, _, [_, _, [kv, _]]}}, {bool, acc} ->
          {bool, Enum.reduce(kv, acc, &[elem(&1, 0) | &2])}

        {:ok, true}, {_, {_, _, [_, _, [kv, _]]}}, {bool, acc} ->
          {bool, Enum.reduce(kv, acc, &[elem(&1, 0) | &2])}

        {:ok, false}, _, {_, acc} ->
          {false, acc}

        {:error, _}, _, {_, acc} ->
          {false, acc}
      end
    }

    entries
    |> map_reduce(
      adapter_meta,
      action,
      [opts],
      Keyword.get(opts, :timeout),
      reducer
    )
    |> case do
      {true, _} ->
        true

      {false, keys} ->
        :ok = Enum.each(keys, &delete(adapter_meta, &1, []))
        action == :put_all
    end
  end

  @impl true
  def delete(adapter_meta, key, opts) do
    call(adapter_meta, key, :delete, [key, opts], opts)
  end

  @impl true
  def take(adapter_meta, key, opts) do
    call(adapter_meta, key, :take, [key, opts], opts)
  end

  @impl true
  def has_key?(adapter_meta, key) do
    call(adapter_meta, key, :has_key?, [key])
  end

  @impl true
  def update_counter(adapter_meta, key, amount, _ttl, _default, opts) do
    call(adapter_meta, key, :incr, [key, amount, opts], opts)
  end

  @impl true
  def ttl(adapter_meta, key) do
    call(adapter_meta, key, :ttl, [key])
  end

  @impl true
  def expire(adapter_meta, key, ttl) do
    call(adapter_meta, key, :expire, [key, ttl])
  end

  @impl true
  def touch(adapter_meta, key) do
    call(adapter_meta, key, :touch, [key])
  end

  ## Nebulex.Adapter.Queryable

  @impl true
  def execute(%{name: name, task_sup: task_sup} = adapter_meta, operation, query, opts) do
    with_span(adapter_meta, operation, fn ->
      reducer =
        case operation do
          :all -> &List.flatten/1
          _ -> &Enum.sum/1
        end

      task_sup
      |> RPC.multi_call(
        Cluster.get_nodes(name),
        __MODULE__,
        :with_dynamic_cache,
        [adapter_meta, operation, [query, opts]],
        opts
      )
      |> handle_rpc_multi_call(operation, reducer)
    end)
  end

  @impl true
  def stream(%{name: name, task_sup: task_sup} = adapter_meta, query, opts) do
    with_span(adapter_meta, :stream, fn ->
      Stream.resource(
        fn ->
          Cluster.get_nodes(name)
        end,
        fn
          [] ->
            {:halt, []}

          [node | nodes] ->
            elements =
              rpc_call(
                task_sup,
                node,
                __MODULE__,
                :eval_stream,
                [adapter_meta, query, opts],
                opts
              )

            {elements, nodes}
        end,
        & &1
      )
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

  @doc """
  Helper to perform `stream/3` locally.
  """
  def eval_stream(meta, query, opts) do
    meta
    |> with_dynamic_cache(:stream, [query, opts])
    |> Enum.to_list()
  end

  ## Private Functions

  defp get_node(%{name: name, keyslot: keyslot}, key) do
    Cluster.get_node(name, key, keyslot)
  end

  defp call(adapter_meta, key, action, args, opts \\ []) do
    with_span(adapter_meta, action, fn ->
      adapter_meta
      |> get_node(key)
      |> rpc_call(adapter_meta, action, args, opts)
    end)
  end

  defp rpc_call(node, %{task_sup: task_sup} = meta, fun, args, opts) do
    rpc_call(task_sup, node, __MODULE__, :with_dynamic_cache, [meta, fun, args], opts)
  end

  if Code.ensure_loaded?(:erpc) do
    defp rpc_call(supervisor, node, mod, fun, args, opts) do
      RPC.call(supervisor, node, mod, fun, args, opts[:timeout] || 5000)
    end
  else
    defp rpc_call(supervisor, node, mod, fun, args, opts) do
      case RPC.call(supervisor, node, mod, fun, args, opts[:timeout] || 5000) do
        {:badrpc, remote_ex} ->
          raise remote_ex

        response ->
          response
      end
    end
  end

  defp group_keys_by_node(enum, adapter_meta) do
    Enum.reduce(enum, %{}, fn
      {key, _} = entry, acc ->
        node = get_node(adapter_meta, key)
        Map.put(acc, node, [entry | Map.get(acc, node, [])])

      key, acc ->
        node = get_node(adapter_meta, key)
        Map.put(acc, node, [key | Map.get(acc, node, [])])
    end)
  end

  defp map_reduce(
         enum,
         %{task_sup: task_sup} = meta,
         action,
         args,
         timeout,
         reducer
       ) do
    groups =
      enum
      |> group_keys_by_node(meta)
      |> Enum.map(fn {node, group} ->
        {node, {__MODULE__, :with_dynamic_cache, [meta, action, [group | args]]}}
      end)

    RPC.multi_call(task_sup, groups, timeout: timeout, reducer: reducer)
  end

  defp handle_rpc_multi_call({res, []}, _action, fun) do
    fun.(res)
  end

  defp handle_rpc_multi_call({responses, errors}, action, _) do
    raise Nebulex.RPCMultiCallError, action: action, responses: responses, errors: errors
  end
end

defmodule Nebulex.Adapters.Partitioned.Bootstrap do
  @moduledoc false
  use GenServer

  import Nebulex.Helpers

  alias Nebulex.Cache.Cluster

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

    # Start bootstrap process
    {:ok, adapter_meta}
  end

  @impl true
  def terminate(_reason, adapter_meta) do
    # Ensure leaving the cluster when the cache stops
    :ok = Cluster.leave(adapter_meta.name)
  end
end
