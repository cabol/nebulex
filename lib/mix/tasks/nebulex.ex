defmodule Mix.Tasks.Nebulex do
  use Mix.Task

  alias Mix.Tasks.Help

  @shortdoc "Prints Nebulex help information"

  @moduledoc """
  Prints Nebulex tasks and their information.

      mix nebulex
  """

  @doc false
  def run(args) do
    {_opts, args, _} = OptionParser.parse(args, switches: [])

    case args do
      [] ->
        general()

      _ ->
        Mix.raise("Invalid arguments, expected: mix nebulex")
    end
  end

  defp general do
    {:ok, _} = Application.ensure_all_started(:nebulex)
    Mix.shell().info("Nebulex v#{Application.spec(:nebulex, :vsn)}")
    Mix.shell().info("A fast, flexible and powerful caching library for Elixir.")
    Mix.shell().info("\nAvailable tasks:\n")
    Help.run(["--search", "nebulex."])
  end
end
