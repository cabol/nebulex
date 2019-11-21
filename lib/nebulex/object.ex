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

      iex> expire_at = Nebulex.Object.expire_at(10)
      iex> expire_at - Nebulex.Object.ts()
      10
  """
  @spec expire_at(ttl :: timeout | nil) :: integer | nil
  def expire_at(nil), do: nil
  def expire_at(:infinity), do: nil
  def expire_at(ttl) when is_integer(ttl), do: ts() + ttl

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
    remaining = expire_at - ts()
    if remaining > 0, do: remaining, else: 0
  end

  @doc """
  Wrapper for `DateTime.to_unix/2`.

  ## Example

      iex> 1_464_096_368 |> DateTime.from_unix!() |> Nebulex.Object.ts()
      1464096368
  """
  @spec ts(datetime :: Calendar.datetime()) :: integer()
  def ts(datetime \\ DateTime.utc_now()) do
    DateTime.to_unix(datetime)
  end

  @doc """
  Returns whether the given `object` has expired or not.

  ## Example

      iex> Nebulex.Object.expired?(%Nebulex.Object{})
      false
  """
  @spec expired?(Nebulex.Object.t()) :: boolean
  def expired?(%Nebulex.Object{expire_at: expire_at}) do
    remaining_ttl(expire_at) <= 0
  end

  def encode(data, opts \\ []) do
    data
    |> :erlang.term_to_binary(opts)
    |> Base.url_encode64()
  end

  def decode(data, opts \\ []) when is_binary(data) do
    data
    |> Base.url_decode64!()
    |> :erlang.binary_to_term(opts)
  end
end
