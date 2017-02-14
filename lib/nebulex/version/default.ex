defmodule Nebulex.Version.Default do
  @moduledoc false
  @behaviour Nebulex.Version

  @doc false
  def generate(_) do
    # TODO: Improve this generator, vector clocks maybe?
    DateTime.utc_now |> DateTime.to_unix(:nanoseconds)
  end
end
