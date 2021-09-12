defmodule Nebulex.Cache.Persistence do
  @moduledoc false

  import Nebulex.Helpers

  alias Nebulex.Adapter

  @doc """
  Implementation for `c:Nebulex.Cache.dump/2`.
  """
  def dump(name, path, opts) do
    Adapter.with_meta(name, & &1.dump(&2, path, opts))
  end

  @doc """
  Implementation for `c:Nebulex.Cache.dump!/2`.
  """
  def dump!(name, path, opts) do
    unwrap_or_raise dump(name, path, opts)
  end

  @doc """
  Implementation for `c:Nebulex.Cache.load/2`.
  """
  def load(name, path, opts) do
    Adapter.with_meta(name, & &1.load(&2, path, opts))
  end

  @doc """
  Implementation for `c:Nebulex.Cache.load!/2`.
  """
  def load!(name, path, opts) do
    unwrap_or_raise load(name, path, opts)
  end
end
