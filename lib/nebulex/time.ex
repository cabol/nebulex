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

      iex> Nebulex.Time.now()
      _milliseconds
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
  """
  @spec timeout?(term) :: boolean
  def timeout?(timeout) do
    (is_integer(timeout) and timeout >= 0) or timeout == :infinity
  end

  @doc """
  Returns the equivalent expiration time in milliseconds for the given `time`.

  ## Example

      iex> Nebulex.Time.expiry_time(10, :second)
      10000

      iex> Nebulex.Time.expiry_time(10, :minute)
      600000

      iex> Nebulex.Time.expiry_time(1, :hour)
      3600000

      iex> Nebulex.Time.expiry_time(1, :day)
      86400000
  """
  @spec expiry_time(pos_integer, :second | :minute | :hour | :day) :: pos_integer
  def expiry_time(time, unit \\ :second)

  def expiry_time(time, unit) when is_integer(time) and time > 0 do
    do_expiry_time(time, exp_time_unit(unit))
  end

  def expiry_time(time, _unit) do
    raise ArgumentError,
          "invalid time. The time is expected to be a positive integer, got #{inspect(time)}"
  end

  def do_expiry_time(time, :second) do
    time * 1000
  end

  def do_expiry_time(time, :minute) do
    do_expiry_time(time * 60, :second)
  end

  def do_expiry_time(time, :hour) do
    do_expiry_time(time * 60, :minute)
  end

  def do_expiry_time(time, :day) do
    do_expiry_time(time * 24, :hour)
  end

  defp exp_time_unit(:second), do: :second
  defp exp_time_unit(:minute), do: :minute
  defp exp_time_unit(:hour), do: :hour
  defp exp_time_unit(:day), do: :day

  defp exp_time_unit(other) do
    raise ArgumentError,
          "unsupported time unit. Expected :second, :minute, :hour, or :day" <>
            ", got #{inspect(other)}"
  end
end
