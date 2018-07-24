defmodule Mix.Tasks.Nebulex.Bench do
  @moduledoc """
  Runs simple benchmarks for `Nebulex.Cache` operations.

  ## Examples

      mix nebulex.bench
  """

  use Mix.Task

  @doc false
  def run(_args) do
    System.cmd("epmd", ["-daemon"])
    Mix.Task.run("app.start", [])
    :ok = start_nodes()
    Mix.Tasks.Bench.run([])
  end

  defp start_nodes() do
    required_files =
      for file <- File.ls!("./test/support") do
        {file, Code.require_file("../../test/support/" <> file, __DIR__)}
      end

    nodes = Keyword.values(Nebulex.Cluster.spawn())

    Enum.each(required_files, fn {file, loaded} ->
      Enum.each(loaded, fn {mod, bin} ->
        expected = List.duplicate({:module, mod}, length(nodes))

        {^expected, []} =
          :rpc.multicall(nodes, :code, :load_binary, [mod, to_charlist(file), bin])
      end)
    end)
  end
end
