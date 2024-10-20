defmodule Nebulex.Adapter.Transaction do
  @moduledoc """
  Specifies the adapter Transaction API.

  ## Default implementation

  This module also provides a default implementation which uses the Erlang
  library `:global`.

  This implementation accepts the following options:

  #{Nebulex.Adapter.Transaction.Options.options_docs()}

  Let's see an example:

      MyCache.transaction fn ->
        counter = MyCache.get(:counter)
        MyCache.set(:counter, counter + 1)
      end

  Locking only the involved key (recommended):

      MyCache.transaction(
        fn ->
          counter = MyCache.get(:counter)
          MyCache.set(:counter, counter + 1)
        end,
        [keys: [:counter]]
      )

      MyCache.transaction(
        fn ->
          alice = MyCache.get(:alice)
          bob = MyCache.get(:bob)
          MyCache.set(:alice, %{alice | balance: alice.balance + 100})
          MyCache.set(:bob, %{bob | balance: bob.balance + 100})
        end,
        [keys: [:alice, :bob]]
      )

  """

  @doc """
  Runs the given function inside a transaction.

  If an Elixir exception occurs, the exception will bubble up from the
  transaction function. If the cache aborts the transaction, it returns
  `{:error, reason}`.

  A successful transaction returns the value returned by the function wrapped
  in a tuple as `{:ok, value}`.

  See `c:Nebulex.Cache.transaction/2`.
  """
  @callback transaction(Nebulex.Adapter.adapter_meta(), fun(), Nebulex.Cache.opts()) ::
              Nebulex.Cache.ok_error_tuple(any())

  @doc """
  Returns `{:ok, true}` if the current process is inside a transaction;
  otherwise, `{:ok, false}` is returned.

  If there's an error with executing the command, `{:error, reason}`
  is returned, where `reason` is the cause of the error.

  See `c:Nebulex.Cache.in_transaction?/1`.
  """
  @callback in_transaction?(Nebulex.Adapter.adapter_meta(), Nebulex.Cache.opts()) ::
              Nebulex.Cache.ok_error_tuple(boolean())

  @doc false
  defmacro __using__(_opts) do
    quote do
      @behaviour Nebulex.Adapter.Transaction

      import Nebulex.Utils, only: [wrap_ok: 1, wrap_error: 2]

      alias Nebulex.Adapter.Transaction.Options

      @impl true
      def transaction(%{cache: cache, pid: pid} = adapter_meta, fun, opts) do
        opts = Options.validate!(opts)

        adapter_meta
        |> do_in_transaction?()
        |> do_transaction(
          pid,
          adapter_meta[:name] || cache,
          Keyword.fetch!(opts, :keys),
          Keyword.get(opts, :nodes, [node()]),
          Keyword.fetch!(opts, :retries),
          fun
        )
      end

      @impl true
      def in_transaction?(adapter_meta, _opts) do
        wrap_ok do_in_transaction?(adapter_meta)
      end

      defoverridable transaction: 3, in_transaction?: 2

      ## Helpers

      defp do_in_transaction?(%{pid: pid}) do
        !!Process.get({pid, self()})
      end

      defp do_transaction(true, _pid, _name, _keys, _nodes, _retries, fun) do
        {:ok, fun.()}
      end

      defp do_transaction(false, pid, name, keys, nodes, retries, fun) do
        ids = lock_ids(name, keys)

        case set_locks(ids, nodes, retries) do
          true ->
            try do
              _ = Process.put({pid, self()}, %{keys: keys, nodes: nodes})

              {:ok, fun.()}
            after
              _ = Process.delete({pid, self()})

              del_locks(ids, nodes)
            end

          false ->
            wrap_error Nebulex.Error,
              reason: :transaction_aborted,
              cache: name,
              nodes: nodes,
              cache: name
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
        Enum.each(ids, &:global.del_lock(&1, nodes))
      end

      defp lock_ids(name, []) do
        [{name, self()}]
      end

      defp lock_ids(name, keys) do
        Enum.map(keys, &{{name, &1}, self()})
      end
    end
  end
end
