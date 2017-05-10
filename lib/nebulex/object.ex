defmodule Nebulex.Object do
  @moduledoc """
  Defines a Cache Object.

  This is the struct used by the caches to store and retrieve data.
  """

  defstruct [:key, :value, :version, ttl: :infinity]

  @type t :: %__MODULE__{key: any, value: any, version: any, ttl: timeout}

  @doc """
  Creates a new `Nebulex.Object` with the given `key`.

  ## Example

      Nebulex.Object.new("mykey")
  """
  @spec new(key :: any) :: Nebulex.Object.t
  def new(key) do
    %Nebulex.Object{key: key}
  end

  @doc """
  Creates a new `Nebulex.Object` with the given `key` and `value`.

  ## Example

      Nebulex.Object.new("foo", "bar")
  """
  @spec new(key :: any, value :: any) :: Nebulex.Object.t
  def new(key, value) do
    %Nebulex.Object{key: key, value: value}
  end

  @doc """
  Creates a new `Nebulex.Object` with the given `key`, `value` and `version`.

  ## Example

      Nebulex.Object.new("foo", "bar", "v1")
  """
  @spec new(key :: any, value :: any, version :: any) :: Nebulex.Object.t
  def new(key, value, version) do
    %Nebulex.Object{key: key, value: value, version: version}
  end
end
