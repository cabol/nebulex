defmodule Nebulex.Adapters.Supervisor do
  # Utility module for building a supervisor to wrap up the adapter's children.
  @moduledoc false

  @doc """
  Builds a supervisor spec with the given `options` for wrapping up the
  adapter's children.
  """
  @spec child_spec(keyword) :: Supervisor.child_spec()
  def child_spec(options) do
    {children, options} = Keyword.pop(options, :children, [])

    %{
      id: Keyword.fetch!(options, :name),
      start: {Supervisor, :start_link, [children, options]},
      type: :supervisor
    }
  end
end
