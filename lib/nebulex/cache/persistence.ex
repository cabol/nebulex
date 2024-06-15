defmodule Nebulex.Cache.Persistence do
  @moduledoc false

  import Nebulex.Adapter, only: [defcommand: 1]
  import Nebulex.Utils, only: [unwrap_or_raise: 1]

  @doc """
  Implementation for `c:Nebulex.Cache.dump/2`.
  """
  defcommand dump(name, path, opts)

  @doc """
  Implementation for `c:Nebulex.Cache.dump!/2`.
  """
  def dump!(name, path, opts) do
    unwrap_or_raise dump(name, path, opts)
  end

  @doc """
  Implementation for `c:Nebulex.Cache.load/2`.
  """
  defcommand load(name, path, opts)

  @doc """
  Implementation for `c:Nebulex.Cache.load!/2`.
  """
  def load!(name, path, opts) do
    unwrap_or_raise load(name, path, opts)
  end
end
