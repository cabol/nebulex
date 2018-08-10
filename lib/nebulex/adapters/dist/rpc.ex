defmodule Nebulex.Adapters.Dist.RPC do
  # The module invoked by cache adapters for
  # distributed task execution.
  @moduledoc false

  @doc """
  Evaluates `apply(mod, fun, args)` on node `node` and returns the corresponding
  evaluation result, or `{:badrpc, Reason}` if the call fails. The `timeout`
  is a time-out value in milliseconds; it uses `Task.await/2` internally,
  hence, check the function documentation to learn more about it.
  """
  def call(node, mod, fun, args, _task_sup, _timeout) when node == node() do
    apply(mod, fun, args)
  rescue
    exception -> {:badrpc, exception}
  end

  def call(node, mod, fun, args, task_sup, timeout) do
    {task_sup, node}
    |> Task.Supervisor.async(__MODULE__, :call, [node, mod, fun, args, task_sup, timeout])
    |> Task.await(timeout)
  end
end
