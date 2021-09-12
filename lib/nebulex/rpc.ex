defmodule Nebulex.RPC do
  @moduledoc """
  RPC utilities for distributed task execution.

  This module uses supervised tasks underneath `Task.Supervisor`.

  > **NOTE:** The approach by using distributed tasks will be deprecated
    in the future in favor of `:erpc`.
  """

  import Nebulex.Helpers

  @typedoc "Task callback"
  @type callback :: {module, atom, [term]}

  @typedoc "Group entry: node -> callback"
  @type node_callback :: {node, callback}

  @typedoc "Node group"
  @type node_group :: %{optional(node) => callback} | [node_callback]

  @typedoc "Error kind"
  @type error_kind :: :error | :exit | :throw

  @typedoc "Reducer function spec"
  @type reducer_fun :: ({:ok, term} | {error_kind, term}, node_callback | node, term -> term)

  @typedoc "Reducer spec"
  @type reducer :: {acc :: term, reducer_fun}

  ## API

  @doc """
  Evaluates `apply(mod, fun, args)` on node `node` and returns the corresponding
  evaluation result, or `{:badrpc, Nebulex.RPCError.t()}` if the call fails.

  A timeout, in milliseconds or `:infinity`, can be given with a default value
  of `5000`.

  ## Example

      iex> Nebulex.RPC.call(:node1, Kernel, :to_string, [1])
      "1"

  """
  @spec call(node, module, atom, [term], timeout) :: term | {:error, Nebulex.RPCError.t()}
  def call(node, mod, fun, args, timeout \\ 5000)

  def call(node, mod, fun, args, _timeout) when node == node() do
    apply(mod, fun, args)
  end

  def call(node, mod, fun, args, timeout) do
    with {:badrpc, reason} <- :rpc.call(node, mod, fun, args, timeout) do
      wrap_error Nebulex.RPCError, reason: reason, node: node
    end
  end

  @doc """
  In contrast to a regular single-node RPC, a multicall is an RPC that is sent
  concurrently from one client to multiple servers. The function evaluates
  `apply(mod, fun, args)` on each `node_group` entry and collects the answers.
  Then, evaluates the `reducer` function (set in the `opts`) on each answer.

  ## Options

    * `:timeout` - A timeout, in milliseconds or `:infinity`, can be given with
      a default value of `5000`. It uses `Task.yield_many/2` internally.

    * `:reducer` - Reducer function to be executed on each collected result.
      (check out `reducer` type).

  ## Example

      iex> Nebulex.RPC.multicall(
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
  @spec multicall(node_group, Keyword.t()) :: term
  def multicall(node_group, opts \\ []) do
    {reducer_acc, reducer_fun} = opts[:reducer] || default_reducer()
    timeout = opts[:timeout] || 5000

    for {node, {mod, fun, args}} = group <- node_group do
      {:erpc.send_request(node, mod, fun, args), group}
    end
    |> Enum.reduce(reducer_acc, fn {req_id, group}, acc ->
      try do
        res = :erpc.receive_response(req_id, timeout)
        reducer_fun.({:ok, res}, group, acc)
      rescue
        exception in ErlangError ->
          reducer_fun.({:error, exception.original}, group, acc)
      catch
        :exit, reason ->
          reducer_fun.({:error, {:EXIT, reason}}, group, acc)
      end
    end)
  end

  @doc """
  Similar to `multicall/3` but it uses `:erpc.multicall/5` under the hood.

  ## Options

  Same options as `multicall/3`.

  ## Example

      iex> Nebulex.RPC.multicall(
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
  @spec multicall([node], module, atom, [term], Keyword.t()) :: term
  def multicall(nodes, mod, fun, args, opts \\ []) do
    {reducer_acc, reducer_fun} = opts[:reducer] || default_reducer()

    nodes
    |> :erpc.multicall(mod, fun, args, opts[:timeout] || 5000)
    |> :lists.zip(nodes)
    |> Enum.reduce(reducer_acc, fn {res, node}, acc ->
      reducer_fun.(res, node, acc)
    end)
  end

  ## Helpers

  defp default_reducer do
    {
      {[], []},
      fn
        {:ok, {:ok, res}}, _node_callback, {ok, err} ->
          {[res | ok], err}

        {:ok, {:error, _} = error}, node_callback, {ok, err} ->
          {ok, [{node_callback, error} | err]}

        {:ok, res}, _node_callback, {ok, err} ->
          {[res | ok], err}

        {kind, _} = error, {node, callback}, {ok, err} when kind in [:error, :exit, :throw] ->
          {ok, [{node, {error, callback}} | err]}

        {kind, _} = error, node, {ok, err} when kind in [:error, :exit, :throw] ->
          {ok, [{node, error} | err]}
      end
    }
  end
end
