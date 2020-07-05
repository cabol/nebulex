defmodule Nebulex.RPC do
  @moduledoc """
  RPC utilities for distributed task execution.

  This module uses supervised tasks underneath `Task.Supervisor`.
  """

  @typedoc "Task callback"
  @type callback :: {module, atom, [term]}

  @typedoc "Group entry: node -> callback"
  @type node_callback :: {node, callback}

  @typedoc "Node group"
  @type node_group :: %{optional(node) => callback} | [node_callback]

  @typedoc "Reducer spec"
  @type reducer :: {acc :: term, ({:ok, term} | {:error, term}, node_callback, term -> term)}

  @doc """
  Evaluates `apply(mod, fun, args)` on node `node` and returns the corresponding
  evaluation result, or `{:badrpc, reason}` if the call fails.

  A timeout, in milliseconds or `:infinity`, can be given with a default value
  of `5000`. It uses `Task.await/2` internally.

  ## Example

      iex> Nebulex.RPC.call(:my_task_sup, :node1, Kernel, :to_string, [1])
      "1"
  """
  @spec call(Supervisor.supervisor(), node, module, atom, [term], timeout) ::
          term | {:badrpc, term}
  def call(supervisor, node, mod, fun, args, timeout \\ 5000)

  def call(_supervisor, node, mod, fun, args, _timeout) when node == node() do
    apply(mod, fun, args)
  rescue
    exception -> {:badrpc, exception}
  end

  def call(supervisor, node, mod, fun, args, timeout) do
    {supervisor, node}
    |> Task.Supervisor.async(
      __MODULE__,
      :call,
      [supervisor, node, mod, fun, args, timeout]
    )
    |> Task.await(timeout)
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
  @spec multi_call(Supervisor.supervisor(), node_group, Keyword.t()) :: term
  def multi_call(supervisor, node_group, opts \\ []) do
    node_group
    |> Enum.map(fn {node, {mod, fun, args}} ->
      Task.Supervisor.async({supervisor, node}, mod, fun, args)
    end)
    |> handle_multi_call(node_group, opts)
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
  @spec multi_call(Supervisor.supervisor(), [node], module, atom, [term], Keyword.t()) :: term
  def multi_call(supervisor, nodes, mod, fun, args, opts \\ []) do
    multi_call(supervisor, Enum.map(nodes, &{&1, {mod, fun, args}}), opts)
  end

  ## Private Functions

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

  defp default_reducer do
    {
      {[], []},
      fn
        {:ok, res}, _node_callback, {ok, err} ->
          {[res | ok], err}

        {:error, reason}, node_callback, {ok, err} ->
          {ok, [{reason, node_callback} | err]}
      end
    }
  end
end
