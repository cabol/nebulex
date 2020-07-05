defmodule Nebulex.CacheTest do
  @moduledoc """
  Shared Tests
  """

  defmacro __using__(_opts) do
    quote do
      use Nebulex.Cache.EntryTest
      use Nebulex.Cache.QueryableTest
      use Nebulex.Cache.TransactionTest
      use Nebulex.Cache.PersistenceTest
    end
  end
end
