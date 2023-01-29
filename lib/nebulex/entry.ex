defmodule Nebulex.Entry do
  @moduledoc """
  Defines a Cache Entry.

  This is the structure used by the caches for representing cache entries.
  """

  # Cache entry definition
  defstruct key: nil,
            value: nil,
            touched: nil,
            exp: :infinity,
            time_unit: :millisecond

  @typedoc """
  Defines a generic struct for a cache entry.

  The entry depends on the adapter completely, this struct/type aims to define
  the common fields.
  """
  @type t :: %__MODULE__{
          key: any,
          value: any,
          touched: integer,
          exp: timeout,
          time_unit: System.time_unit()
        }

  alias Nebulex.Time

  @doc """
  Encodes a cache entry.

  ## Example

      iex> "hello"
      ...> |> Nebulex.Entry.encode()
      ...> |> Nebulex.Entry.decode()
      "hello"

  """
  @spec encode(term, [term]) :: binary
  def encode(data, opts \\ []) do
    data
    |> :erlang.term_to_binary(opts)
    |> Base.encode64()
  end

  @doc """
  Decodes a previously encoded entry.

  ## Example

      iex> "hello"
      ...> |> Nebulex.Entry.encode()
      ...> |> Nebulex.Entry.decode()
      "hello"

  """
  # sobelow_skip ["Misc.BinToTerm"]
  @spec decode(binary, [term]) :: term
  def decode(data, opts \\ []) when is_binary(data) do
    data
    |> Base.decode64!()
    |> :erlang.binary_to_term(opts)
  end

  @doc """
  Returns whether the given `entry` has expired or not.

  ## Example

      iex> Nebulex.Entry.expired?(%Nebulex.Entry{})
      false

      iex> now = Nebulex.Time.now()
      iex> Nebulex.Entry.expired?(%Nebulex.Entry{touched: now, exp: now - 10})
      true

  """
  @spec expired?(t) :: boolean
  def expired?(%__MODULE__{exp: :infinity}), do: false
  def expired?(%__MODULE__{exp: exp, time_unit: unit}), do: Time.now(unit) >= exp

  @doc """
  Returns the remaining time-to-live.

  ## Example

      iex> Nebulex.Entry.ttl(%Nebulex.Entry{})
      :infinity

      iex> now = Nebulex.Time.now()
      iex> ttl = Nebulex.Entry.ttl(%Nebulex.Entry{touched: now, exp: now + 10})
      iex> ttl > 0
      true

  """
  @spec ttl(t) :: timeout
  def ttl(%__MODULE__{exp: :infinity}), do: :infinity
  def ttl(%__MODULE__{exp: exp, time_unit: unit}), do: exp - Time.now(unit)
end
