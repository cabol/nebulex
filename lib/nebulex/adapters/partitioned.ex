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

    * `:join_timeout` - Interval time in milliseconds for joining the
      running partitioned cache to the cluster. This is to ensure it is
      always joined. Defaults to `:timer.seconds(180)`.

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

  ## Telemetry events

  This adapter emits all recommended Telemetry events, and documented
  in `Nebulex.Cache` module (see **"Adapter-specific events"** section).

  Since the partitioned adapter depends on the configured primary storage
  adapter (local cache adapter), this one may also emit Telemetry events.
  Therefore, there will be events emitted by the partitioned adapter as well
  as the primary storage adapter. For example, for the cache defined before
  `MyApp.PartitionedCache`, these would be the emitted events:

    * `[:my_app, :partitioned_cache, :command, :start]`
    * `[:my_app, :partitioned_cache, :primary, :command, :start]`
    * `[:my_app, :partitioned_cache, :command, :stop]`
    * `[:my_app, :partitioned_cache, :primary, :command, :stop]`
    * `[:my_app, :partitioned_cache, :command, :exception]`
    * `[:my_app, :partitioned_cache, :primary, :command, :exception]`

  As you may notice, the telemetry prefix by default for the partitioned cache
  is `[:my_app, :partitioned_cache]`, and the prefix for its primary storage
  `[:my_app, :partitioned_cache, :primary]`.

  See also the [Telemetry guide](http://hexdocs.pm/nebulex/telemetry.html)
  for more information and examples.

  ## Adapter-specific telemetry events

  This adapter exposes following Telemetry events:

    * `telemetry_prefix ++ [:bootstrap, :started]` - Dispatched by the adapter
      when the bootstrap process is started.

      * Measurements: `%{system_time: non_neg_integer}`
      * Metadata:

        ```
        %{
          adapter_meta: %{optional(atom) => term},
          cluster_nodes: [node]
        }
        ```

    * `telemetry_prefix ++ [:bootstrap, :stopped]` - Dispatched by the adapter
      when the bootstrap process is stopped.

      * Measurements: `%{system_time: non_neg_integer}`
      * Metadata:

        ```
        %{
          adapter_meta: %{optional(atom) => term},
          cluster_nodes: [node],
          reason: term
        }
        ```

    * `telemetry_prefix ++ [:bootstrap, :exit]` - Dispatched by the adapter
      when the bootstrap has received an exit signal.

      * Measurements: `%{system_time: non_neg_integer}`
      * Metadata:

        ```
        %{
          adapter_meta: %{optional(atom) => term},
          cluster_nodes: [node],
          reason: term
        }
        ```

    * `telemetry_prefix ++ [:bootstrap, :joined]` - Dispatched by the adapter
      when the bootstrap has joined the cache to the cluster.

      * Measurements: `%{system_time: non_neg_integer}`
      * Metadata:

        ```
        %{
          adapter_meta: %{optional(atom) => term},
          cluster_nodes: [node]
        }
        ```

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
    telemetry = Keyword.fetch!(opts, :telemetry)
    cache = Keyword.fetch!(opts, :cache)
    name = opts[:name] || cache

    # Maybe use stats
    stats = get_boolean_option(opts, :stats)

    # Primary cache options
    primary_opts =
      Keyword.merge(
        [telemetry_prefix: telemetry_prefix ++ [:primary], telemetry: telemetry, stats: stats],
        Keyword.get(opts, :primary, [])
      )

    # Maybe put a name to primary storage
    primary_opts =
      if opts[:name],
        do: [name: normalize_module_name([name, Primary])] ++ primary_opts,
        else: primary_opts

    # Keyslot module for selecting nodes
    keyslot =
      opts
      |> get_option(:keyslot, "an atom", &is_atom/1, __MODULE__)
      |> assert_behaviour(Nebulex.Adapter.Keyslot, "keyslot")

    # Prepare metadata
    adapter_meta = %{
      telemetry_prefix: telemetry_prefix,
      telemetry: telemetry,
      name: name,
      primary_name: primary_opts[:name],
      keyslot: keyslot,
      stats: stats
    }

    # Prepare child_spec
    child_spec =
      Nebulex.Adapters.Supervisor.child_spec(
        name: normalize_module_name([name, Supervisor]),
        strategy: :rest_for_one,
        children: [
          {cache.__primary__, primary_opts},
          {__MODULE__.Bootstrap, {Map.put(adapter_meta, :cache, cache), opts}}
        ]
      )

    {:ok, child_spec, adapter_meta}
  end

  ## Nebulex.Adapter.Entry

  @impl true
  defspan fetch(adapter_meta, key, opts) do
    adapter_meta
    |> call(key, :fetch, [key, opts], opts)
    |> handle_key_error(adapter_meta.name)
  end

  @impl true
  defspan get_all(adapter_meta, keys, opts) do
    case map_reduce(keys, adapter_meta, :get_all, [opts], Keyword.get(opts, :timeout)) do
      {res, []} ->
        {:ok, Enum.reduce(res, %{}, &Map.merge(&2, &1))}

      {_ok, errors} ->
        wrap_error Nebulex.Error, reason: {:rpc_multicall_error, errors}, module: RPC
    end
  end

  @impl true
  defspan put(adapter_meta, key, value, _ttl, on_write, opts) do
    case on_write do
      :put ->
        :ok = call(adapter_meta, key, :put, [key, value, opts], opts)
        {:ok, true}

      :put_new ->
        call(adapter_meta, key, :put_new, [key, value, opts], opts)

      :replace ->
        call(adapter_meta, key, :replace, [key, value, opts], opts)
    end
  end

  @impl true
  defspan put_all(adapter_meta, entries, _ttl, on_write, opts) do
    case on_write do
      :put ->
        do_put_all(:put_all, adapter_meta, entries, opts)

      :put_new ->
        do_put_all(:put_new_all, adapter_meta, entries, opts)
    end
  end

  def do_put_all(action, adapter_meta, entries, opts) do
    case {action, map_reduce(entries, adapter_meta, action, [opts], Keyword.get(opts, :timeout))} do
      {:put_all, {_res, []}} ->
        {:ok, true}

      {:put_new_all, {res, []}} ->
        {:ok, Enum.reduce(res, true, &(&1 and &2))}

      {_, {_ok, errors}} ->
        wrap_error Nebulex.Error, reason: {:rpc_multicall_error, errors}, module: RPC
    end
  end

  @impl true
  defspan delete(adapter_meta, key, opts) do
    call(adapter_meta, key, :delete, [key, opts], opts)
  end

  @impl true
  defspan take(adapter_meta, key, opts) do
    adapter_meta
    |> call(key, :take, [key, opts], opts)
    |> handle_key_error(adapter_meta.name)
  end

  @impl true
  defspan exists?(adapter_meta, key) do
    call(adapter_meta, key, :exists?, [key])
  end

  @impl true
  defspan update_counter(adapter_meta, key, amount, _ttl, _default, opts) do
    call(adapter_meta, key, :incr, [key, amount, opts], opts)
  end

  @impl true
  defspan ttl(adapter_meta, key) do
    adapter_meta
    |> call(key, :ttl, [key])
    |> handle_key_error(adapter_meta.name)
  end

  @impl true
  defspan expire(adapter_meta, key, ttl) do
    call(adapter_meta, key, :expire, [key, ttl])
  end

  @impl true
  defspan touch(adapter_meta, key) do
    call(adapter_meta, key, :touch, [key])
  end

  ## Nebulex.Adapter.Queryable

  @impl true
  defspan execute(adapter_meta, operation, query, opts) do
    reducer =
      case operation do
        :all -> &List.flatten/1
        _ -> &Enum.sum/1
      end

    adapter_meta.name
    |> Cluster.get_nodes()
    |> RPC.multicall(
      __MODULE__,
      :with_dynamic_cache,
      [adapter_meta, operation, [query, opts]],
      opts
    )
    |> handle_rpc_multicall(reducer)
  end

  @impl true
  defspan stream(adapter_meta, query, opts) do
    timeout = opts[:timeout] || 5000

    Stream.resource(
      fn ->
        Cluster.get_nodes(adapter_meta.name)
      end,
      fn
        [] ->
          {:halt, []}

        [node | nodes] ->
          elements =
            unwrap_or_raise RPC.call(
                              node,
                              __MODULE__,
                              :eval_stream,
                              [adapter_meta, query, opts],
                              timeout
                            )

          {elements, nodes}
      end,
      & &1
    )
    |> wrap_ok()
  end

  ## Nebulex.Adapter.Persistence

  @impl true
  defspan dump(adapter_meta, path, opts) do
    super(adapter_meta, path, opts)
  end

  @impl true
  defspan load(adapter_meta, path, opts) do
    super(adapter_meta, path, opts)
  end

  ## Nebulex.Adapter.Transaction

  @impl true
  defspan transaction(adapter_meta, opts, fun) do
    super(adapter_meta, Keyword.put(opts, :nodes, Cluster.get_nodes(adapter_meta.name)), fun)
  end

  @impl true
  defspan in_transaction?(adapter_meta) do
    super(adapter_meta)
  end

  ## Nebulex.Adapter.Stats

  @impl true
  defspan stats(adapter_meta) do
    with_dynamic_cache(adapter_meta, :stats, [])
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
    with {:ok, stream} <- with_dynamic_cache(meta, :stream, [query, opts]) do
      {:ok, Enum.to_list(stream)}
    end
  end

  ## Private Functions

  defp handle_key_error({:error, %Nebulex.KeyError{} = e}, name) do
    {:error, %{e | cache: name}}
  end

  defp handle_key_error(other, _name) do
    other
  end

  defp get_node(%{name: name, keyslot: keyslot}, key) do
    Cluster.get_node(name, key, keyslot)
  end

  defp call(adapter_meta, key, action, args, opts \\ []) do
    adapter_meta
    |> get_node(key)
    |> rpc_call(adapter_meta, action, args, opts)
  end

  defp rpc_call(node, meta, fun, args, opts) do
    RPC.call(node, __MODULE__, :with_dynamic_cache, [meta, fun, args], opts[:timeout] || 5000)
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

  defp map_reduce(enum, meta, action, args, timeout) do
    enum
    |> group_keys_by_node(meta)
    |> Enum.map(fn {node, group} ->
      {node, {__MODULE__, :with_dynamic_cache, [meta, action, [group | args]]}}
    end)
    |> RPC.multicall(timeout: timeout)
  end

  defp handle_rpc_multicall({res, []}, fun) do
    {:ok, fun.(res)}
  end

  defp handle_rpc_multicall({_ok, errors}, _) do
    wrap_error Nebulex.Error, reason: {:rpc_multicall_error, errors}, module: RPC
  end
end

defmodule Nebulex.Adapters.Partitioned.Bootstrap do
  @moduledoc false
  use GenServer

  import Nebulex.Helpers

  alias Nebulex.Cache.Cluster
  alias Nebulex.Telemetry

  # Default join timeout
  @join_timeout :timer.seconds(180)

  # State
  defstruct [:adapter_meta, :join_timeout]

  ## API

  @doc false
  def start_link({%{name: name}, _} = state) do
    GenServer.start_link(
      __MODULE__,
      state,
      name: normalize_module_name([name, Bootstrap])
    )
  end

  ## GenServer Callbacks

  @impl true
  def init({adapter_meta, opts}) do
    # Trap exit signals to run cleanup job
    _ = Process.flag(:trap_exit, true)

    # Bootstrap started
    :ok = dispatch_telemetry_event(:started, adapter_meta)

    # Ensure joining the cluster when the cache supervision tree is started
    :ok = Cluster.join(adapter_meta.name)

    # Bootstrap joined the cache to the cluster
    :ok = dispatch_telemetry_event(:joined, adapter_meta)

    # Build initial state
    state = build_state(adapter_meta, opts)

    # Start bootstrap process
    {:ok, state, state.join_timeout}
  end

  @impl true
  def handle_info(message, state)

  def handle_info(:timeout, %__MODULE__{adapter_meta: adapter_meta} = state) do
    # Ensure it is always joined to the cluster
    :ok = Cluster.join(adapter_meta.name)

    # Bootstrap joined the cache to the cluster
    :ok = dispatch_telemetry_event(:joined, adapter_meta)

    {:noreply, state, state.join_timeout}
  end

  def handle_info({:EXIT, _from, reason}, %__MODULE__{adapter_meta: adapter_meta} = state) do
    # Bootstrap received exit signal
    :ok = dispatch_telemetry_event(:exit, adapter_meta, %{reason: reason})

    {:stop, reason, state}
  end

  @impl true
  def terminate(reason, %__MODULE__{adapter_meta: adapter_meta}) do
    # Ensure leaving the cluster when the cache stops
    :ok = Cluster.leave(adapter_meta.name)

    # Bootstrap stopped or terminated
    :ok = dispatch_telemetry_event(:stopped, adapter_meta, %{reason: reason})
  end

  ## Private Functions

  defp build_state(adapter_meta, opts) do
    # Join timeout to ensure it is always joined to the cluster
    join_timeout =
      get_option(
        opts,
        :join_timeout,
        "an integer > 0",
        &(is_integer(&1) and &1 > 0),
        @join_timeout
      )

    %__MODULE__{adapter_meta: adapter_meta, join_timeout: join_timeout}
  end

  defp dispatch_telemetry_event(event, adapter_meta, meta \\ %{}) do
    Telemetry.execute(
      adapter_meta.telemetry_prefix ++ [:bootstrap, event],
      %{system_time: System.system_time()},
      Map.merge(meta, %{
        adapter_meta: adapter_meta,
        cluster_nodes: Cluster.get_nodes(adapter_meta.name)
      })
    )
  end
end
