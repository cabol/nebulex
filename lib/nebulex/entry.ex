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
  # sobelow_skip ["Misc.BinToTerm"]
  @spec decode(binary, [term]) :: term
  def decode(data, opts \\ []) when is_binary(data) do
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
  @spec expired?(t) :: boolean
  def expired?(%__MODULE__{ttl: :infinity}), do: false

  def expired?(%__MODULE__{touched: touched, ttl: ttl, time_unit: unit}) do
    Time.now(unit) - touched >= ttl
  end

  @doc """
  Returns the remaining time-to-live.

  ## Example

      iex> Nebulex.Entry.ttl(%Nebulex.Entry{})
      :infinity
  """
  @spec ttl(t) :: timeout
  def ttl(%__MODULE__{ttl: :infinity}), do: :infinity

  def ttl(%__MODULE__{ttl: ttl, touched: touched, time_unit: unit}) do
    ttl - (Time.now(unit) - touched)
  end
end
