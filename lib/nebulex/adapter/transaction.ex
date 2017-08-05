defmodule Nebulex.Adapter.Transaction  do
  @moduledoc """
  Specifies the adapter transactions API.
  """

  @doc false
  defmacro __using__(_opts) do
    quote do
      @behaviour Nebulex.Adapter.Transaction

      @doc false
      def transaction(cache, opts, fun) do
        keys  = opts[:keys] || []
        nodes = opts[:nodes] || [node() | Node.list()]
        retries = opts[:retries] || :infinity
        do_transaction(cache, keys, nodes, retries, fun)
      end

      @doc false
      def in_transaction?(cache) do
        if Process.get(cache), do: true, else: false
      end

      defoverridable [transaction: 3, in_transaction?: 1]

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
        maybe_set_lock =
          fn(id, {:ok, acc}) ->
            case :global.set_lock(id, nodes, retries) do
              true  -> {:cont, {:ok, [id | acc]}}
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

      defp lock_ids(cache, []),
        do: [{cache, self()}]
      defp lock_ids(cache, keys),
        do: for key <- keys, do: {{cache, key}, self()}
    end
  end

  @doc """
  Runs the given function inside a transaction.

  A successful transaction returns the value returned by the function.

  See `Nebulex.Cache.transaction/2`.
  """
  @callback transaction(cache :: Nebulex.Cache.t, opts :: Nebulex.Cache.opts, function :: fun) :: any

  @doc """
  Returns `true` if the given process is inside a transaction.
  """
  @callback in_transaction?(cache :: Nebulex.Cache.t) :: boolean
end
