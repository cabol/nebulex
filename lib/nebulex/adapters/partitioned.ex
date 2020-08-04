defmodule Nebulex.Adapters.Partitioned do
  @moduledoc ~S"""
  Built-in adapter for partitioned cache topology.

  A partitioned cache is a clustered, fault-tolerant cache that has linear
  scalability. Data is partitioned among all the machines of the cluster.
  For fault-tolerance, partitioned caches can be configured to keep each piece
  of data on one or more unique machines within a cluster. This adapter
  in particular hasn't fault-tolerance built-in, each piece of data is kept
  in a single node/machine (sharding), therefore, if a node fails, the data
  kept by this node won't be available for the rest of the cluster.

  PG2 is used under-the-hood by the adapter to manage the cluster nodes.
  When the partitioned cache is started in a node, it creates a PG2 group
  and joins it (the cache supervisor PID is joined to the group). Then,
  when a function is invoked, the adapter picks a node from the node list
  (using the PG2 group members), and then the function is executed on that
  node. In the same way, when the supervisor process of the partitioned cache
  dies, the PID of that process is automatically removed from the PG2 group;
  this is why it's recommended to use a consistent hashing algorithm for the
  node selector.

  > **NOTE:** `pg2` will be replaced by `pg` in future, since the `pg2` module
    is deprecated as of OTP 23 and scheduled for removal in OTP 24.

  This adapter depends on a local cache adapter (primary storage), it adds
  a thin layer on top of it in order to distribute requests across a group
  of nodes, where is supposed the local cache is running already. However,
  you don't need to define or declare an additional cache module for the
  ocal store, instead, the adapter initializes it automatically (adds the
  local cache store as part of the supervision tree) based on the given
  options within the `primary:` argument.

  ## Features

    * Support for partitioned topology (Sharding Distribution Model).
    * Support for transactions via Erlang global name registration facility.
    * Configurable primary store (primary local cache).
    * Configurable keyslot module to compute the node.

  We can define a partitioned cache as follows:

      defmodule MyApp.PartitionedCache do
        use Nebulex.Cache,
          otp_app: :my_app,
          adapter: Nebulex.Adapters.Partitioned

        @behaviour Nebulex.Adapter.Keyslot

        @impl true
        def compute(key, range) do
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

    * `:keyslot` - Defines the module implementing `Nebulex.Adapter.Keyslot`
      behaviour.

    * `task_supervisor_opts` - Start-time options passed to
      `Task.Supervisor.start_link/1` when the adapter is initialized.

  ## Shared Primary Options

    * `:adapter` - The adapter to be used for the partitioned cache as the
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

  This adapter provides some additional convenience functions to the
  `Nebulex.Cache` API.

  Retrieving the cluster nodes associated with the given cache `name`:

      MyCache.nodes()
      MyCache.nodes(:cache_name)

  Get a cluster node for the cache `name` based on the given `key`:

      MyCache.get_node("mykey")
      MyCache.get_node(:cache_name, "mykey")

  > If no cache name is passed to the previous functions, the name of the
    calling cache module is used by default

  ## Limitations

  For `c:Nebulex.Cache.get_and_update/3` and `c:Nebulex.Cache.update/4`,
  they both have a parameter that is the anonymous function, and it is compiled
  into the module where it is created, which means it necessarily doesn't exists
  on remote nodes. To ensure they work as expected, you must provide functions
  from modules existing in all nodes of the group.
  """

  # Provide Cache Implementation
  @behaviour Nebulex.Adapter
  @behaviour Nebulex.Adapter.Queryable

  # Inherit default transaction implementation
  use Nebulex.Adapter.Transaction

  # Inherit default persistence implementation
  use Nebulex.Adapter.Persistence

  # Inherit default compute callback
  use Nebulex.Adapter.Keyslot

  import Nebulex.Helpers

  alias Nebulex.Adapter
  alias Nebulex.Cache.{Cluster, Stats}
  alias Nebulex.RPC

  ## Adapter

  @impl true
  defmacro __before_compile__(_env) do
    quote do
      @doc """
      A convenience function for getting the cluster nodes.
      """
      def nodes(name \\ __MODULE__), do: Cluster.get_nodes(name)

      @doc """
      A convenience function to get the node of the given `key`.
      """
      def get_node(name \\ __MODULE__, key) do
        Adapter.with_meta(name, fn _adapter, %{keyslot: keyslot} ->
          Cluster.get_node(name, key, keyslot)
        end)
      end
    end
  end

  @impl true
  def init(opts) do
    # required cache name
    name = opts[:name] || Keyword.fetch!(opts, :cache)

    # maybe use stats
    stat_counter = opts[:stat_counter] || Stats.init(opts)

    # set up the primary cache store
    primary = Keyword.get(opts, :primary, [])
    {primary_adapter, primary} = Keyword.pop(primary, :adapter, Nebulex.Adapters.Local)
    primary_adapter = assert_behaviour(primary_adapter, Nebulex.Adapter, "adapter")
    primary_name = normalize_module_name([name, Primary])
    primary = [name: primary_name, stat_counter: stat_counter] ++ primary
    {:ok, primary_child_spec, primary_meta} = primary_adapter.init(primary)

    # task supervisor to execute parallel and/or remote commands
    task_sup_name = normalize_module_name([name, TaskSupervisor])
    task_sup_opts = Keyword.get(opts, :task_supervisor_opts, [])

    # keyslot module for selecting nodes
    keyslot =
      opts
      |> Keyword.get(:keyslot, __MODULE__)
      |> assert_behaviour(Nebulex.Adapter.Keyslot, "keyslot")

    child_spec =
      Nebulex.Adapters.Supervisor.child_spec(
        name: normalize_module_name([name, Supervisor]),
        strategy: :rest_for_one,
        children: [
          primary_child_spec,
          {Task.Supervisor, [name: task_sup_name] ++ task_sup_opts}
        ]
      )

    meta = %{
      name: name,
      primary: primary_adapter,
      primary_meta: primary_meta,
      task_sup: task_sup_name,
      keyslot: keyslot,
      stat_counter: stat_counter
    }

    # join the cache to the cluster
    :ok = Cluster.join(name)

    {:ok, child_spec, meta}
  rescue
    e in ArgumentError ->
      reraise RuntimeError, e.message, __STACKTRACE__
  end

  @impl true
  def get(adapter_meta, key, opts) do
    call(adapter_meta, key, :get, [key, opts], opts)
  end

  @impl true
  def get_all(adapter_meta, keys, opts) do
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
  def put(adapter_meta, key, value, ttl, on_write, opts) do
    call(adapter_meta, key, :put, [key, value, ttl, on_write, opts], opts)
  end

  @impl true
  def put_all(adapter_meta, entries, ttl, on_write, opts) do
    reducer = {
      {true, []},
      fn
        {:ok, true}, {_, {_, _, [_, kv, _, _, _]}}, {bool, acc} ->
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
      :put_all,
      [ttl, on_write, opts],
      Keyword.get(opts, :timeout),
      reducer
    )
    |> case do
      {true, _} ->
        true

      {false, keys} ->
        :ok = Enum.each(keys, &delete(adapter_meta, &1, []))
        on_write == :put
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
  def incr(adapter_meta, key, incr, ttl, opts) do
    call(adapter_meta, key, :incr, [key, incr, ttl, opts], opts)
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

  @impl true
  def size(%{name: name, task_sup: task_sup, primary: primary, primary_meta: primary_meta}) do
    task_sup
    |> RPC.multi_call(
      Cluster.get_nodes(name),
      primary,
      :size,
      [primary_meta]
    )
    |> handle_rpc_multi_call(:size, &Enum.sum/1)
  end

  @impl true
  def flush(%{name: name, task_sup: task_sup, primary: primary, primary_meta: primary_meta}) do
    task_sup
    |> RPC.multi_call(
      Cluster.get_nodes(name),
      primary,
      :flush,
      [primary_meta]
    )
    |> elem(0)
    |> Enum.sum()
  end

  ## Queryable

  @impl true
  def all(
        %{name: name, task_sup: task_sup, primary: primary, primary_meta: primary_meta},
        query,
        opts
      ) do
    task_sup
    |> RPC.multi_call(
      Cluster.get_nodes(name),
      primary,
      :all,
      [primary_meta, query, opts],
      opts
    )
    |> handle_rpc_multi_call(:all, &List.flatten/1)
  end

  @impl true
  def stream(
        %{name: name, task_sup: task_sup, primary: primary, primary_meta: primary_meta},
        query,
        opts
      ) do
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
              :eval_local_stream,
              [primary, primary_meta, query, opts],
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
  def eval_local_stream(primary, primary_meta, query, opts) do
    primary_meta
    |> primary.stream(query, opts)
    |> Enum.to_list()
  end

  ## Private Functions

  defp call(adapter_meta, key, fun, args, opts \\ []) do
    adapter_meta
    |> get_node(key)
    |> rpc_call(adapter_meta, fun, args, opts)
  end

  def get_node(%{name: name, keyslot: keyslot}, key) do
    Cluster.get_node(name, key, keyslot)
  end

  defp rpc_call(
         node,
         %{task_sup: task_sup, primary: primary, primary_meta: primary_meta},
         fun,
         args,
         opts
       ) do
    rpc_call(
      task_sup,
      node,
      primary,
      fun,
      [primary_meta | args],
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
         %{
           task_sup: task_sup,
           primary: primary,
           primary_meta: primary_meta
         } = adapter_meta,
         action,
         args,
         timeout,
         reducer
       ) do
    groups =
      enum
      |> group_keys_by_node(adapter_meta)
      |> Enum.map(fn {node, group} ->
        {node, {primary, action, [primary_meta, group | args]}}
      end)

    RPC.multi_call(task_sup, groups, timeout: timeout, reducer: reducer)
  end

  defp handle_rpc_multi_call({res, []}, _action, fun) do
    fun.(res)
  end

  defp handle_rpc_multi_call({_, errors}, action, _) do
    raise Nebulex.RPCMultiCallError, action: action, errors: errors
  end
end
