defmodule Nebulex.Cache.Transaction do
  @moduledoc false

  alias Nebulex.Adapter

  @doc """
  Implementation for `c:Nebulex.Cache.transaction/2`.
  """
  def transaction(name, fun, opts) do
    Adapter.with_meta(name, & &1.adapter.transaction(&1, fun, opts))
  end

  @doc """
  Implementation for `c:Nebulex.Cache.in_transaction?/0`.
  """
  def in_transaction?(name) do
    Adapter.with_meta(name, & &1.adapter.in_transaction?(&1))
  end
end
