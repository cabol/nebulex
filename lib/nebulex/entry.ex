defmodule Nebulex.Entry do
  @moduledoc """
  Defines a Cache Entry.

  This is the structure used by the caches for representing cache entries.
  """

  defstruct [:key, :value, :touched, ttl: :infinity, time_unit: :millisecond]

  @type t :: %__MODULE__{
          key: any,
          value: any,
          touched: integer,
          ttl: timeout,
          time_unit: System.time_unit()
        }

  alias Nebulex.Time

  @doc """
  Encodes a cache entry.

  ## Example

      iex> Nebulex.Entry.encode(%Nebulex.Entry{})
      _encoded_entry
  """
  @spec encode(term, [term]) :: binary
  def encode(data, opts \\ []) do
    data
    |> :erlang.term_to_binary(opts)
    |> Base.url_encode64()
  end

  @doc """
  Decodes a previously encoded entry.

  ## Example

      iex> %Nebulex.Entry{}
      ...> |> Nebulex.Entry.encode()
      ...> |> Nebulex.Entry.decode()
      _decoded_entry
  """
  @spec decode(binary, [term]) :: term
  def decode(data, opts \\ []) do
    data
    |> Base.url_decode64!()
    |> :erlang.binary_to_term(opts)
  end

  @doc """
  Returns whether the given `entry` has expired or not.

  ## Example

      iex> Nebulex.Entry.expired?(%Nebulex.Entry{})
      false
  """
  @spec expired?(Nebulex.Entry.t()) :: boolean
  def expired?(%Nebulex.Entry{ttl: :infinity}), do: false

  def expired?(%Nebulex.Entry{touched: touched, ttl: ttl, time_unit: unit}) do
    Time.now(unit) - touched >= ttl
  end
end
