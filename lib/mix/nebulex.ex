defmodule Mix.Nebulex do
  # Conveniences for writing Mix.Tasks in Nebulex.
  @moduledoc false

  @doc """
  Gets a path relative to the application path.
  Raises on umbrella application.
  """
  def no_umbrella!(task) do
    if Mix.Project.umbrella? do
      Mix.raise "Cannot run task #{inspect task} from umbrella application"
    end
  end
end
