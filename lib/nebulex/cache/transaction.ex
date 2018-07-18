defmodule Nebulex.Cache.Transaction do
  @moduledoc false

  @doc """
  Implementation for `Nebulex.Cache.transaction/2`.
  """
  def transaction(cache, fun, opts) do
    cache.__adapter__.transaction(cache, fun, opts)
  end

  @doc """
  Implementation for `Nebulex.Cache.in_transaction?/0`.
  """
  def in_transaction?(cache) do
    cache.__adapter__.in_transaction?(cache)
  end
end
