defmodule Nebulex.Cluster do
  @moduledoc """
  Taken from `Phoenix.PubSub.Cluster`.
  Copyright (c) 2014 Chris McCord
  """

  def spawn(nodes) do
    # Turn node into a distributed node with the given long name
    _ = :net_kernel.start([:"primary@127.0.0.1"])

    # Allow spawned nodes to fetch all code from this node
    _ = :erl_boot_server.start([])
    _ = allow_boot(to_charlist("127.0.0.1"))

    nodes
    |> Enum.map(&Task.async(fn -> spawn_node(&1) end))
    |> Enum.map(&Task.await(&1, 30_000))
  end

  def spawn_node(node_host) do
    {:ok, node} = start_peer(node_host)

    _ = add_code_paths(node)
    _ = transfer_configuration(node)
    _ = ensure_applications_started(node)

    {:ok, node}
  end

  if Code.ensure_loaded?(:peer) do
    defp start_peer(node_host) do
      {:ok, _pid, node} =
        :peer.start(%{
          name: node_name(node_host),
          host: to_charlist("127.0.0.1"),
          args: [inet_loader_args()]
        })

      {:ok, node}
    end
  else
    defp start_peer(node_host) do
      :slave.start(to_charlist("127.0.0.1"), node_name(node_host), inet_loader_args())
    end
  end

  defp rpc(node, module, function, args) do
    :rpc.block_call(node, module, function, args)
  end

  defp inet_loader_args do
    to_charlist("-loader inet -hosts 127.0.0.1 -setcookie #{:erlang.get_cookie()}")
  end

  defp allow_boot(host) do
    {:ok, ipv4} = :inet.parse_ipv4_address(host)
    :erl_boot_server.add_slave(ipv4)
  end

  defp add_code_paths(node) do
    rpc(node, :code, :add_paths, [:code.get_path()])
  end

  defp transfer_configuration(node) do
    for {app_name, _, _} <- Application.loaded_applications() do
      for {key, val} <- Application.get_all_env(app_name) do
        rpc(node, Application, :put_env, [app_name, key, val])
      end
    end
  end

  defp ensure_applications_started(node) do
    rpc(node, Application, :ensure_all_started, [:mix])
    rpc(node, Mix, :env, [Mix.env()])

    for {app_name, _, _} <- Application.loaded_applications(), app_name not in [:dialyxir] do
      rpc(node, Application, :ensure_all_started, [app_name])
    end
  end

  defp node_name(node_host) do
    node_host
    |> to_string()
    |> String.split("@")
    |> Enum.at(0)
    |> String.to_atom()
  end
end
