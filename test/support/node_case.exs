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
    apply_for_all(nodes, caches, fn node, cache ->
      {_, {:ok, pid}} = start_cache(node, cache)
      pid
    end)
  end

  def start_cache(node_name, cache, opts \\ []) do
    call_node(node_name, fn ->
      cache.start_link(opts)
    end)
  end

  def stop_caches(node_pid_list) do
    Enum.each(node_pid_list, fn {node, cache, pid} ->
      stop_cache(node, cache, pid)
    end)
  end

  def stop_cache(node_name, cache, pid) do
    call_node(node_name, fn ->
      if Process.alive?(pid), do: cache.stop(pid, @timeout)
    end)
  end

  defp apply_for_all(nodes, caches, fun) do
    Enum.reduce(nodes, [], fn node, acc ->
      for(cache <- caches, do: {node, cache, fun.(node, cache)}) ++ acc
    end)
  end

  defp call_node(node, func) do
    parent = self()
    ref = make_ref()

    pid =
      Node.spawn_link(node, fn ->
        result = func.()
        send(parent, {ref, result})
        ref = Process.monitor(parent)

        receive do
          {:DOWN, ^ref, :process, _, _} -> :ok
        end
      end)

    receive do
      {^ref, result} -> {pid, result}
    after
      @timeout -> {pid, {:error, :timeout}}
    end
  end
end
