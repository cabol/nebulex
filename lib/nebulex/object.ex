defmodule Nebulex.Object do
  @moduledoc """
  Defines a Cache Object.

  This is the struct used by the caches to store and retrieve data.
  """

  defstruct [:key, :value, :version, :expire_at]

  @type t :: %__MODULE__{
          key: any,
          value: any,
          version: any,
          expire_at: integer | nil
        }

  @doc """
  Returns the UNIX timestamp in seconds for the given `ttl`.

  ## Example

      iex> Nebulex.Object.expire_at(10)
      1539787704
  """
  @spec expire_at(ttl :: timeout | nil) :: integer | nil
  def expire_at(nil), do: nil
  def expire_at(:infinity), do: nil

  def expire_at(ttl) when is_integer(ttl) do
    DateTime.to_unix(DateTime.utc_now()) + ttl
  end

  @doc """
  Returns the remaining time to live for the given timestamp.

  ## Example

      iex> expire_at = Nebulex.Object.expire_at(10)
      iex> Nebulex.Object.remaining_ttl(expire_at)
      10
  """
  @spec remaining_ttl(object_or_ttl :: Nebulex.Object.t() | integer | nil) :: timeout
  def remaining_ttl(nil), do: :infinity
  def remaining_ttl(%Nebulex.Object{expire_at: expire_at}), do: remaining_ttl(expire_at)

  def remaining_ttl(expire_at) when is_integer(expire_at) do
    remaining = expire_at - DateTime.to_unix(DateTime.utc_now())
    if remaining >= 0, do: remaining, else: 0
  end
end
