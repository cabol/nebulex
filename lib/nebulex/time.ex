defmodule Nebulex.Time do
  @moduledoc """
  Time utilities.
  """

  ## API

  @doc """
  Returns the current system time in the given time unit.

  The `unit` is set to `:millisecond` by default.

  ## Examples

      iex> now = Nebulex.Time.now()
      iex> is_integer(now) and now > 0
      true

  """
  @spec now(System.time_unit()) :: integer()
  defdelegate now(unit \\ :millisecond), to: System, as: :system_time
end
