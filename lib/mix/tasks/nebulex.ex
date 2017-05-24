defmodule Mix.Tasks.Nebulex do
  use Mix.Task

  @shortdoc "Prints Nebulex help information"

  @moduledoc """
  Prints Nebulex tasks and their information.

      mix nebulex
  """

  @doc false
  def run(args) do
    {_opts, args, _} = OptionParser.parse(args)

    case args do
      [] -> general()
      _  -> Mix.raise "Invalid arguments, expected: mix nebulex"
    end
  end

  defp general do
    {:ok, _} = Application.ensure_all_started(:nebulex)
    Mix.shell.info "Nebulex v#{Application.spec(:nebulex, :vsn)}"
    Mix.shell.info "Local and Distributed Caching Tool for Elixir."
    Mix.shell.info "\nAvailable tasks:\n"
    Mix.Tasks.Help.run(["--search", "nebulex."])
  end
end
