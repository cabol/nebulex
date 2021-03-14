defmodule Nebulex.Caching.KeyGenerator do
  @moduledoc ~S"""
  This behaviour provides a callback to.
  """

  @doc """
  Docs.
  """
  @callback generate(module, fun :: atom, args :: [term]) :: term
end
