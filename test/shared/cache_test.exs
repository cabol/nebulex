defmodule Nebulex.CacheTest do
  @moduledoc """
  Shared Tests
  """

  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      @cache Keyword.fetch!(opts, :cache)

      use Nebulex.Cache.EntryTest, cache: @cache
      use Nebulex.Cache.QueryableTest, cache: @cache
      use Nebulex.Cache.TransactionTest, cache: @cache
      use Nebulex.Cache.PersistenceTest, cache: @cache
    end
  end
end
