defmodule Nebulex.Cache.Queryable do
  @moduledoc false

  alias Nebulex.Adapter

  @default_page_size 10

  @doc """
  Implementation for `c:Nebulex.Cache.all/2`.
  """
  def all(name, query, opts) do
    Adapter.with_meta(name, & &1.all(&2, query, opts))
  end

  @doc """
  Implementation for `c:Nebulex.Cache.stream/2`.
  """
  def stream(name, query, opts) do
    opts = Keyword.put_new(opts, :page_size, @default_page_size)
    Adapter.with_meta(name, & &1.stream(&2, query, opts))
  end
end
