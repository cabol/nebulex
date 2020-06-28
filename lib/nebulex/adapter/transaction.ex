defmodule Nebulex.Adapter.Transaction do
  @moduledoc ~S"""
  Specifies the adapter transactions API.

  ## Default implementation

  This module also provides a default implementation which uses the Erlang
  library `:global`.

  This implementation accepts the following options:

    * `:keys` - The list of the keys that will be locked. Since the lock id is
      generated based on the key, if this option is not set, a fixed/constant
      lock id is used to perform the transaction, then all further transactions
      (without this option set) are serialized and the performance is affected
      significantly. For that reason it is recommended to pass the list of keys
      involved in the transaction.

    * `:nodes` - The list of the nodes where the lock will be set, or on
      all nodes if none are specified.

    * `:retries` - If the key has been locked by other process already, and
      `:retries` is not equal to 0, the process sleeps for a while and tries
      to execute the action later. When `:retries` attempts have been made,
      an exception is raised. If `:retries` is `:infinity` (the default),
      the function will eventually be executed (unless the lock is never
      released).

  Let's see an example:

      MyCache.transaction fn ->
        counter = MyCache.get(:counter)
        MyCache.set(:counter, counter + 1)
      end

  Locking only the involved key (recommended):

      MyCache.transaction [keys: [:counter]], fn ->
        counter = MyCache.get(:counter)
        MyCache.set(:counter, counter + 1)
      end

      MyCache.transaction [keys: [:alice, :bob]], fn ->
        alice = MyCache.get(:alice)
        bob = MyCache.get(:bob)
        MyCache.set(:alice, %{alice | balance: alice.balance + 100})
        MyCache.set(:bob, %{bob | balance: bob.balance + 100})
      end
  """

  @doc false
  defmacro __using__(_opts) do
    quote do
      @behaviour Nebulex.Adapter.Transaction

      alias Nebulex.Cache.Cluster

      @impl true
      def transaction(%{name: name} = adapter_meta, opts, fun) do
        adapter_meta
        |> in_transaction?()
        |> do_transaction(
          name,
          Keyword.get(opts, :keys, []),
          Keyword.get(opts, :nodes, Cluster.get_nodes(name)),
          Keyword.get(opts, :retries, :infinity),
          fun
        )
      end

      @impl true
      def in_transaction?(%{name: name}) do
        if Process.get({name, self()}), do: true, else: false
      end

      defoverridable transaction: 3, in_transaction?: 1

      ## Helpers

      defp do_transaction(true, _name, _keys, _nodes, _retries, fun) do
        fun.()
      end

      defp do_transaction(false, name, keys, nodes, retries, fun) do
        ids = lock_ids(name, keys)

        case set_locks(ids, nodes, retries) do
          true ->
            try do
              _ = Process.put({name, self()}, %{keys: keys, nodes: nodes})
              fun.()
            after
              _ = Process.delete({name, self()})
              del_locks(ids, nodes)
            end

          false ->
            raise "transaction aborted"
        end
      end

      defp set_locks(ids, nodes, retries) do
        maybe_set_lock = fn id, {:ok, acc} ->
          case :global.set_lock(id, nodes, retries) do
            true -> {:cont, {:ok, [id | acc]}}
            false -> {:halt, {:error, acc}}
          end
        end

        case Enum.reduce_while(ids, {:ok, []}, maybe_set_lock) do
          {:ok, _} ->
            true

          {:error, locked_ids} ->
            :ok = del_locks(locked_ids, nodes)
            false
        end
      end

      defp del_locks(ids, nodes) do
        Enum.each(ids, fn id ->
          true = :global.del_lock(id, nodes)
        end)
      end

      defp lock_ids(name, []) do
        [{name, self()}]
      end

      defp lock_ids(name, keys) do
        for key <- keys, do: {{name, key}, self()}
      end
    end
  end

  @doc """
  Runs the given function inside a transaction.

  A successful transaction returns the value returned by the function.

  See `c:Nebulex.Cache.transaction/2`.
  """
  @callback transaction(Nebulex.Adapter.adapter_meta(), Nebulex.Cache.opts(), fun) :: any

  @doc """
  Returns `true` if the given process is inside a transaction.

  See `c:Nebulex.Cache.in_transaction?/0`.
  """
  @callback in_transaction?(Nebulex.Adapter.adapter_meta()) :: boolean
end
