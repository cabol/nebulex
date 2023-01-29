defmodule Nebulex.Cache.Queryable do
  @moduledoc false

  import Nebulex.Helpers

  alias Nebulex.Adapter

  @default_page_size 20

  @doc """
  Implementation for `c:Nebulex.Cache.all/2`.
  """
  def all(name, query, opts) do
    Adapter.with_meta(name, & &1.adapter.execute(&1, :all, query, opts))
  end

  @doc """
  Implementation for `c:Nebulex.Cache.all!/2`.
  """
  def all!(name, query, opts) do
    unwrap_or_raise all(name, query, opts)
  end

  @doc """
  Implementation for `c:Nebulex.Cache.count_all/2`.
  """
  def count_all(name, query, opts) do
    Adapter.with_meta(name, & &1.adapter.execute(&1, :count_all, query, opts))
  end

  @doc """
  Implementation for `c:Nebulex.Cache.count_all!/2`.
  """
  def count_all!(name, query, opts) do
    unwrap_or_raise count_all(name, query, opts)
  end

  @doc """
  Implementation for `c:Nebulex.Cache.delete_all/2`.
  """
  def delete_all(name, query, opts) do
    Adapter.with_meta(name, & &1.adapter.execute(&1, :delete_all, query, opts))
  end

  @doc """
  Implementation for `c:Nebulex.Cache.delete_all!/2`.
  """
  def delete_all!(name, query, opts) do
    unwrap_or_raise delete_all(name, query, opts)
  end

  @doc """
  Implementation for `c:Nebulex.Cache.stream/2`.
  """
  def stream(name, query, opts) do
    opts = Keyword.put_new(opts, :page_size, @default_page_size)
    Adapter.with_meta(name, & &1.adapter.stream(&1, query, opts))
  end

  @doc """
  Implementation for `c:Nebulex.Cache.stream!/2`.
  """
  def stream!(name, query, opts) do
    unwrap_or_raise stream(name, query, opts)
  end
end
