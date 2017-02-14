defmodule Nebulex.Object do
  @moduledoc """
  Cache Object.
  """

  defstruct [:key, :value, :version, ttl: :infinity]

  @type t :: %__MODULE__{key: any, value: any, version: any, ttl: timeout}

  @spec new(key :: any) :: Nebulex.Object.t
  def new(key) do
    %Nebulex.Object{key: key}
  end

  @spec new(key :: any, value :: any) :: Nebulex.Object.t
  def new(key, value) do
    %Nebulex.Object{key: key, value: value}
  end

  @spec new(key :: any, value :: any, version :: any) :: Nebulex.Object.t
  def new(key, value, version) do
    %Nebulex.Object{key: key, value: value, version: version}
  end
end
