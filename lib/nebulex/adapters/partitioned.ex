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

  This adapter depends on a local cache adapter (primary storage), it adds
  a thin layer on top of it in order to distribute requests across a group
  of nodes, where is supposed the local cache is running already.

  PG2 is used under-the-hood by the adapter to manage the cluster nodes.
  When the partitioned cache is started in a node, it creates a PG2 group
  and joins it (the cache supervisor PID is joined to the group). Then,
  when a function is invoked, the adapter picks a node from the node list
  (using the PG2 group members), and then the function is executed on that
  node. In the same way, when the supervisor process of the partitioned cache
  dies, the PID of that process is automatically removed from the PG2 group;
  this is why it's recommended to use a consistent hashing algorithm for the
  node selector.

  ## Features

    * Support for partitioned topology (Sharding Distribution Model).
    * Support for transactions via Erlang global name registration facility.
    * Configurable hash-slot module to compute the node.

  When used, aside from the `:otp_app` and `:adapter` the cache expects
  `:primary` option as well. For example, the cache:

      defmodule MyApp.PartitionedCache do
        use Nebulex.Cache,
          otp_app: :my_app,
          adapter: Nebulex.Adapters.Partitioned,
          primary: MyApp.PartitionedCache.Primary

        defmodule Primary do
          use Nebulex.Cache,
            otp_app: :my_app,
            adapter: Nebulex.Adapters.Local,
            backend: :shards
        end
      end

  Where the configuration for the cache must be in your application environment,
  usually defined in your `config/config.exs`:

      config :my_app, MyApp.PartitionedCache.Primary,
        gc_interval: 3600,
        partitions: System.schedulers_online()

  For more information about the usage, see `Nebulex.Cache` documentation.

  ## Compile-Time Options

  In addition to `:otp_app` and `:adapter`, this adapter supports the next
  compile-time options:

    * `:primary` - Defines the module for the primary storage. The value must
      be a valid local cache adapter so that the partitioned adapter can store
      the data in there. For example, you can set the `Nebulex.Adapters.Local`
      as value, unless you want to provide another one.

    * `:hash_slot` - Defines the module implementing
      `Nebulex.Adapter.HashSlot` behaviour.

  ## Config Options

  These options can be set through the config file:

    * `task_supervisor_opts` - Start-time options passed to
      `Task.Supervisor.start_link/1` when the adapter is initialized.

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

  This adapter provides some additional functions to the `Nebulex.Cache` API.

  ### `__primary__`

  Returns the local cache adapter (the local backend).

  ### `__task_sup__`

  Returns the task supervisor module that manages RPC calls.

  ### `__nodes__`

  Returns the nodes that belongs to the caller Cache.

  ### `get_node/1`

  This function invokes `c:Nebulex.Adapter.NodeSelector.get_node/2` internally.

      MyCache.get_node("mykey")

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

  # Inherit default keyslot callback
  use Nebulex.Adapter.HashSlot

  import Nebulex.Helpers

  alias Nebulex.Cache.Cluster
  alias Nebulex.RPC

  ## Adapter

  @impl true
  defmacro __before_compile__(env) do
    opts = Module.get_attribute(env.module, :opts)
    task_supervisor = Module.concat(env.module, TaskSupervisor)
    primary = opts[:primary] || raise ArgumentError, "expected primary: to be given as argument"

    hash_slot =
      opts
      |> Keyword.get(:hash_slot, __MODULE__)
      |> assert_behaviour(Nebulex.Adapter.HashSlot, "hash_slot")

    quote do
      def __primary__, do: unquote(primary)

      def __task_sup__, do: unquote(task_supervisor)

      def __nodes__, do: Cluster.get_nodes(__MODULE__)

      def get_node(key) do
        Cluster.get_node(__MODULE__, key, unquote(hash_slot))
      end

      @impl true
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

    child_spec =
      Nebulex.Adapters.Supervisor.child_spec(
        name: Module.concat(cache, Supervisor),
        strategy: :rest_for_one,
        children: [
          {cache.__primary__, Keyword.put(opts, :cache, cache.__primary__)},
          {Task.Supervisor, [name: cache.__task_sup__] ++ task_sup_opts}
        ]
      )

    {:ok, child_spec}
  end

  @impl true
  def get(cache, key, opts) do
    call(cache, key, :get, [key, opts], opts)
  end

  @impl true
  def get_all(cache, keys, opts) do
    map_reduce(
      keys,
      cache,
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
  def put(cache, key, value, ttl, on_write, opts) do
    call(cache, key, :put, [key, value, ttl, on_write, opts], opts)
  end

  @impl true
  def put_all(cache, entries, ttl, on_write, opts) do
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
      cache,
      :put_all,
      [ttl, on_write, opts],
      Keyword.get(opts, :timeout),
      reducer
    )
    |> case do
      {true, _} ->
        true

      {false, keys} ->
        :ok = Enum.each(keys, &delete(cache, &1, []))
        on_write == :put
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
  def incr(cache, key, incr, ttl, opts) do
    call(cache, key, :incr, [key, incr, ttl, opts], opts)
  end

  @impl true
  def ttl(cache, key) do
    call(cache, key, :ttl, [key])
  end

  @impl true
  def expire(cache, key, ttl) do
    call(cache, key, :expire, [key, ttl])
  end

  @impl true
  def touch(cache, key) do
    call(cache, key, :touch, [key])
  end

  @impl true
  def size(cache) do
    cache.__task_sup__
    |> RPC.multi_call(
      cache.__nodes__,
      cache.__primary__.__adapter__,
      :size,
      [cache.__primary__]
    )
    |> handle_rpc_multi_call(:size, &Enum.sum/1)
  end

  @impl true
  def flush(cache) do
    cache.__task_sup__
    |> RPC.multi_call(
      cache.__nodes__,
      cache.__primary__.__adapter__,
      :flush,
      [cache.__primary__]
    )
    |> elem(0)
    |> Enum.sum()
  end

  ## Queryable

  @impl true
  def all(cache, query, opts) do
    cache.__task_sup__
    |> RPC.multi_call(
      cache.__nodes__,
      cache.__primary__.__adapter__,
      :all,
      [cache.__primary__, query, opts],
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
    cache.__primary__
    |> cache.__primary__.__adapter__.stream(query, opts)
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
      cache.__primary__.__adapter__,
      fun,
      [cache.__primary__ | args],
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
      {key, _} = entry, acc ->
        node = cache.get_node(key)
        Map.put(acc, node, [entry | Map.get(acc, node, [])])

      key, acc ->
        node = cache.get_node(key)
        Map.put(acc, node, [key | Map.get(acc, node, [])])
    end)
  end

  defp map_reduce(enum, cache, action, args, timeout, reducer) do
    groups =
      enum
      |> group_keys_by_node(cache)
      |> Enum.map(fn {node, group} ->
        {node, {cache.__primary__.__adapter__, action, [cache.__primary__, group | args]}}
      end)

    RPC.multi_call(cache.__task_sup__, groups, timeout: timeout, reducer: reducer)
  end

  defp handle_rpc_multi_call({res, []}, _action, fun) do
    fun.(res)
  end

  defp handle_rpc_multi_call({_, errors}, action, _) do
    raise Nebulex.RPCMultiCallError, action: action, errors: errors
  end
end
