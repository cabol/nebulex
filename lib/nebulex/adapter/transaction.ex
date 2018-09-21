defmodule Nebulex.Adapter.Transaction do
  @moduledoc """
  Specifies the adapter transactions API.

  ## Default implementation

  This module also provides a default implementation which uses the Erlang
  library `:global`.

  Theis implementation accepts the following options:

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

      MyCache.transaction fn ->
        counter = MyCache.get(:counter)
        MyCache.set(:counter, counter + 1)
      end, keys: [:counter]

      MyCache.transaction fn ->
        alice = MyCache.get(:alice)
        bob = MyCache.get(:bob)
        MyCache.set(:alice, %{alice | balance: alice.balance + 100})
        MyCache.set(:bob, %{bob | balance: bob.balance + 100})
      end, keys: [:alice, :bob]
  """

  @doc false
  defmacro __using__(_opts) do
    quote do
      @behaviour Nebulex.Adapter.Transaction

      @doc false
      def transaction(cache, fun, opts) do
        keys = opts[:keys]
        nodes = opts[:nodes] || [node() | Node.list()]
        retries = opts[:retries] || :infinity
        do_transaction(cache, keys, nodes, retries, fun)
      end

      @doc false
      def in_transaction?(cache) do
        if Process.get(cache), do: true, else: false
      end

      defoverridable transaction: 3, in_transaction?: 1

      ## Helpers

      defp do_transaction(cache, keys, nodes, retries, fun) do
        ids = lock_ids(cache, keys)

        case set_locks(ids, nodes, retries) do
          true ->
            try do
              _ = Process.put(cache, %{keys: keys, nodes: nodes})
              fun.()
            after
              _ = Process.delete(cache)
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

        ids
        |> Enum.reduce_while({:ok, []}, maybe_set_lock)
        |> case do
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

      defp lock_ids(cache, nil) do
        [{cache, self()}]
      end

      defp lock_ids(cache, keys) do
        for key <- keys, do: {{cache, key}, self()}
      end
    end
  end

  @doc """
  Runs the given function inside a transaction.

  A successful transaction returns the value returned by the function.

  See `Nebulex.Cache.transaction/2`.
  """
  @callback transaction(
              cache :: Nebulex.Cache.t(),
              function :: fun,
              opts :: Nebulex.Cache.opts()
            ) :: any

  @doc """
  Returns `true` if the given process is inside a transaction.

  See `Nebulex.Cache.in_transaction?/0`.
  """
  @callback in_transaction?(cache :: Nebulex.Cache.t()) :: boolean
end
