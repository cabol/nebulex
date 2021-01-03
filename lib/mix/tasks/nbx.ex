defmodule Mix.Tasks.Nbx do
  @shortdoc "Prints Nebulex help information"

  @moduledoc """
  Prints Nebulex tasks and their information.

      mix nbx

  """

  use Mix.Task

  alias Mix.Tasks.Help

  @doc false
  def run(args) do
    {_opts, args} = OptionParser.parse!(args, strict: [])

    case args do
      [] -> general()
      _ -> Mix.raise("Invalid arguments, expected: mix nbx")
    end
  end

  defp general do
    _ = Application.ensure_all_started(:nebulex)
    Mix.shell().info("Nebulex v#{Application.spec(:nebulex, :vsn)}")
    Mix.shell().info("In-Process and Distributed Cache Toolkit for Elixir.")

    Mix.shell().info(
      "Easily craft and deploy distributed cache topologies and cache usage patterns."
    )

    Mix.shell().info("\nAvailable tasks:\n")
    Help.run(["--search", "nbx."])
  end
end
