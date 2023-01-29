defmodule Nebulex.NodeCase do
  @moduledoc """
  Based on `Phoenix.PubSub.NodeCase`.
  Copyright (c) 2014 Chris McCord
  """

  @timeout 5000

  defmacro __using__(_opts) do
    quote do
      use ExUnit.Case, async: true
      import unquote(__MODULE__)

      @moduletag :clustered

      @timeout unquote(@timeout)
    end
  end

  def start_caches(nodes, caches) do
    for node <- nodes, {cache, opts} <- caches do
      {:ok, pid} = start_cache(node, cache, opts)

      {node, cache, pid}
    end
  end

  def start_cache(node, cache, opts \\ []) do
    rpc(node, cache, :start_link, [opts])
  end

  def stop_caches(node_pid_list) do
    Enum.each(node_pid_list, fn {node, _cache, pid} ->
      stop_cache(node, pid)
    end)
  end

  def stop_cache(node, pid) do
    rpc(node, Supervisor, :stop, [pid, :normal, @timeout])
  end

  def rpc(node, module, function, args) do
    :rpc.block_call(node, module, function, args)
  end
end
