defmodule Nebulex.Time do
  @moduledoc """
  Time utilities.
  """

  # Inline instructions
  @compile {:inline, now: 1, timeout?: 1}

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

  @doc """
  Returns `true` if the given `timeout` is a valid timeout; otherwise, `false`
  is returned.

  Valid timeout: `:infinity | non_neg_integer()`.

  ## Examples

      iex> Nebulex.Time.timeout?(1)
      true

      iex> Nebulex.Time.timeout?(:infinity)
      true

      iex> Nebulex.Time.timeout?(-1)
      false

      iex> Nebulex.Time.timeout?(1.1)
      false

  """
  @spec timeout?(term) :: boolean
  def timeout?(timeout) do
    (is_integer(timeout) and timeout >= 0) or timeout == :infinity
  end
end
