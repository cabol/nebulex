defmodule Nebulex.RPC do
  @moduledoc """
  RPC utilities for distributed task execution.

  This module uses supervised tasks underneath `Task.Supervisor`.

  > **NOTE:** The approach by using distributed tasks will be deprecated
    in the future in favor of `:erpc`.
  """

  @typedoc "Task supervisor"
  @type task_sup :: Supervisor.supervisor()

  @typedoc "Task callback"
  @type callback :: {module, atom, [term]}

  @typedoc "Group entry: node -> callback"
  @type node_callback :: {node, callback}

  @typedoc "Node group"
  @type node_group :: %{optional(node) => callback} | [node_callback]

  @typedoc "Reducer function spec"
  @type reducer_fun :: ({:ok, term} | {:error, term}, node_callback | node, term -> term)

  @typedoc "Reducer spec"
  @type reducer :: {acc :: term, reducer_fun}

  ## API

  @doc """
  Evaluates `apply(mod, fun, args)` on node `node` and returns the corresponding
  evaluation result, or `{:badrpc, reason}` if the call fails.

  A timeout, in milliseconds or `:infinity`, can be given with a default value
  of `5000`. It uses `Task.await/2` internally.

  ## Example

      iex> Nebulex.RPC.call(:my_task_sup, :node1, Kernel, :to_string, [1])
      "1"

  """
  @spec call(task_sup, node, module, atom, [term], timeout) :: term | {:badrpc, term}
  def call(supervisor, node, mod, fun, args, timeout \\ 5000) do
    rpc_call(supervisor, node, mod, fun, args, timeout)
  end

  @doc """
  In contrast to a regular single-node RPC, a multicall is an RPC that is sent
  concurrently from one client to multiple servers. The function evaluates
  `apply(mod, fun, args)` on each `node_group` entry and collects the answers.
  Then, evaluates the `reducer` function (set in the `opts`) on each answer.

  This function is similar to `:rpc.multicall/5`.

  ## Options

    * `:timeout` - A timeout, in milliseconds or `:infinity`, can be given with
      a default value of `5000`. It uses `Task.yield_many/2` internally.

    * `:reducer` - Reducer function to be executed on each collected result.
      (check out `reducer` type).

  ## Example

      iex> Nebulex.RPC.multi_call(
      ...>   :my_task_sup,
      ...>   %{
      ...>     node1: {Kernel, :to_string, [1]},
      ...>     node2: {Kernel, :to_string, [2]}
      ...>   },
      ...>   timeout: 10_000,
      ...>   reducer: {
      ...>     [],
      ...>     fn
      ...>       {:ok, res}, _node_callback, acc ->
      ...>         [res | acc]
      ...>
      ...>       {:error, _}, _node_callback, acc ->
      ...>         acc
      ...>     end
      ...>   }
      ...> )
      ["1", "2"]

  """
  @spec multi_call(task_sup, node_group, Keyword.t()) :: term
  def multi_call(supervisor, node_group, opts \\ []) do
    rpc_multi_call(supervisor, node_group, opts)
  end

  @doc """
  Similar to `multi_call/3` but the same `node_callback` (given by `module`,
  `fun`, `args`) is executed on all `nodes`; Internally it creates a
  `node_group` with the same `node_callback` for each node.

  ## Options

  Same options as `multi_call/3`.

  ## Example

      iex> Nebulex.RPC.multi_call(
      ...>   :my_task_sup,
      ...>   [:node1, :node2],
      ...>   Kernel,
      ...>   :to_string,
      ...>   [1],
      ...>   timeout: 5000,
      ...>   reducer: {
      ...>     [],
      ...>     fn
      ...>       {:ok, res}, _node_callback, acc ->
      ...>         [res | acc]
      ...>
      ...>       {:error, _}, _node_callback, acc ->
      ...>         acc
      ...>     end
      ...>   }
      ...> )
      ["1", "1"]

  """
  @spec multi_call(task_sup, [node], module, atom, [term], Keyword.t()) :: term
  def multi_call(supervisor, nodes, mod, fun, args, opts \\ []) do
    rpc_multi_call(supervisor, nodes, mod, fun, args, opts)
  end

  ## Helpers

  if Code.ensure_loaded?(:erpc) do
    defp rpc_call(_supervisor, node, mod, fun, args, _timeout) when node == node() do
      apply(mod, fun, args)
    end

    defp rpc_call(_supervisor, node, mod, fun, args, timeout) do
      :erpc.call(node, mod, fun, args, timeout)
    rescue
      e in ErlangError ->
        case e.original do
          {:exception, original, _} when is_struct(original) ->
            reraise original, __STACKTRACE__

          {:exception, original, _} ->
            :erlang.raise(:error, original, __STACKTRACE__)

          other ->
            reraise %Nebulex.RPCError{reason: other, node: node}, __STACKTRACE__
        end
    end

    def rpc_multi_call(_supervisor, node_group, opts) do
      {reducer_acc, reducer_fun} = opts[:reducer] || default_reducer()
      timeout = opts[:timeout] || 5000

      node_group
      |> Enum.map(fn {node, {mod, fun, args}} = group ->
        {:erpc.send_request(node, mod, fun, args), group}
      end)
      |> Enum.reduce(reducer_acc, fn {req_id, group}, acc ->
        try do
          res = :erpc.receive_response(req_id, timeout)
          reducer_fun.({:ok, res}, group, acc)
        rescue
          exception ->
            reducer_fun.({:error, exception}, group, acc)
        catch
          :exit, reason ->
            reducer_fun.({:error, {:exit, reason}}, group, acc)
        end
      end)
    end

    def rpc_multi_call(_supervisor, nodes, mod, fun, args, opts) do
      {reducer_acc, reducer_fun} = opts[:reducer] || default_reducer()

      nodes
      |> :erpc.multicall(mod, fun, args, opts[:timeout] || 5000)
      |> :lists.zip(nodes)
      |> Enum.reduce(reducer_acc, fn {res, node}, acc ->
        reducer_fun.(res, node, acc)
      end)
    end
  else
    # TODO: This approach by using distributed tasks will be deprecated in the
    #       future in favor of `:erpc` which is proven to improve performance
    #       almost by 3x.

    defp rpc_call(_supervisor, node, mod, fun, args, _timeout) when node == node() do
      apply(mod, fun, args)
    rescue
      # FIXME: this is because coveralls does not check this as covered
      # coveralls-ignore-start
      exception ->
        {:badrpc, exception}
        # coveralls-ignore-stop
    end

    defp rpc_call(supervisor, node, mod, fun, args, timeout) do
      {supervisor, node}
      |> Task.Supervisor.async_nolink(
        __MODULE__,
        :call,
        [supervisor, node, mod, fun, args, timeout]
      )
      |> Task.await(timeout)
    end

    defp rpc_multi_call(supervisor, node_group, opts) do
      node_group
      |> Enum.map(fn {node, {mod, fun, args}} ->
        Task.Supervisor.async_nolink({supervisor, node}, mod, fun, args)
      end)
      |> handle_multi_call(node_group, opts)
    end

    defp rpc_multi_call(supervisor, nodes, mod, fun, args, opts) do
      rpc_multi_call(supervisor, Enum.map(nodes, &{&1, {mod, fun, args}}), opts)
    end

    defp handle_multi_call(tasks, node_group, opts) do
      {reducer_acc, reducer_fun} = Keyword.get(opts, :reducer, default_reducer())

      tasks
      |> Task.yield_many(opts[:timeout] || 5000)
      |> :lists.zip(node_group)
      |> Enum.reduce(reducer_acc, fn
        {{_task, {:ok, res}}, group}, acc ->
          reducer_fun.({:ok, res}, group, acc)

        {{_task, {:exit, reason}}, group}, acc ->
          reducer_fun.({:error, {:exit, reason}}, group, acc)

        {{task, nil}, group}, acc ->
          _ = Task.shutdown(task, :brutal_kill)
          reducer_fun.({:error, :timeout}, group, acc)
      end)
    end
  end

  defp default_reducer do
    {
      {[], []},
      fn
        {:ok, res}, _node_callback, {ok, err} ->
          {[res | ok], err}

        {kind, _} = error, node_callback, {ok, err} when kind in [:error, :exit, :throw] ->
          {ok, [{error, node_callback} | err]}
      end
    }
  end
end
