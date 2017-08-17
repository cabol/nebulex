defmodule Nebulex.Version.Timestamp do
  @moduledoc false
  @behaviour Nebulex.Version

  @doc false
  def generate(_) do
    DateTime.utc_now |> DateTime.to_unix(:nanoseconds)
  end
end
