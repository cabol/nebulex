defmodule Nebulex.CacheTest do
  @moduledoc """
  Shared Tests
  """

  defmacro __using__(_opts) do
    quote do
      use Nebulex.Cache.EntryTest
      use Nebulex.Cache.EntryExpirationTest
      use Nebulex.Cache.EntryPropTest
      use Nebulex.Cache.QueryableTest
      use Nebulex.Cache.TransactionTest
      use Nebulex.Cache.PersistenceTest
      use Nebulex.Cache.PersistenceErrorTest
    end
  end
end
