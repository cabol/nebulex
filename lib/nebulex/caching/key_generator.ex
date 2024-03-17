defmodule Nebulex.Caching.KeyGenerator do
  @moduledoc """
  Cache key generator.

  See the default implementation `Nebulex.Caching.SimpleKeyGenerator`.
  """

  @typedoc "Key generator type"
  @type t() :: module()

  @doc """
  Receives the decorator `context` as an argument and returns the generated key.
  """
  @callback generate(Nebulex.Caching.Decorators.Context.t()) :: any()
end
