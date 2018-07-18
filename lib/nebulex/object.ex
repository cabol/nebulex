defmodule Nebulex.Object do
  @moduledoc """
  Defines a Cache Object.

  This is the struct used by the caches to store and retrieve data.
  """

  defstruct [:key, :value, :version, ttl: :infinity]

  @type t :: %__MODULE__{key: any, value: any, version: any, ttl: timeout}

  @doc """
  Returns the remaining time to live for the given object.

  ## Example

      obj = MyCache.set("foo", "bar", return: :object, ttl: 3)
      Object.ttl(obj)
  """
  @spec ttl(Nebulex.Object.t()) :: timeout
  def ttl(%Nebulex.Object{ttl: :infinity}), do: :infinity

  def ttl(%Nebulex.Object{ttl: ttl}) when is_integer(ttl) do
    remaining = ttl - DateTime.to_unix(DateTime.utc_now())
    if remaining >= 0, do: remaining, else: 0
  end
end
