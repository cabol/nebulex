defmodule Nebulex.Cache.Transaction do
  @moduledoc false

  import Nebulex.Helpers

  @doc """
  Implementation for `c:Nebulex.Cache.transaction/2`.
  """
  def transaction(name, fun, opts) do
    with_meta(name, & &1.transaction(&2, fun, opts))
  end

  @doc """
  Implementation for `c:Nebulex.Cache.in_transaction?/0`.
  """
  def in_transaction?(name) do
    with_meta(name, & &1.in_transaction?(&2))
  end
end
