defmodule Nebulex.Caching.SimpleKeyGenerator do
  @moduledoc """
  KeyGenerator implementation.
  """
  @behaviour Nebulex.Caching.KeyGenerator

  @impl true
  def generate(_mod, _fun, []), do: 0
  def generate(_mod, _fun, [arg]), do: arg
  def generate(_mod, _fun, args), do: :erlang.phash2(args)
end
