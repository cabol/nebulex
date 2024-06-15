defmodule Nebulex.CacheTestCase do
  @moduledoc """
  Shared Tests
  """

  defmacro __using__(_opts) do
    quote do
      use Nebulex.Cache.KVTest
      use Nebulex.Cache.KVExpirationTest
      use Nebulex.Cache.KVPropTest
      use Nebulex.Cache.QueryableTest
      use Nebulex.Cache.QueryableQueryErrorTest
      use Nebulex.Cache.QueryableExpirationTest
      use Nebulex.Cache.TransactionTest
      use Nebulex.Cache.PersistenceTest
      use Nebulex.Cache.PersistenceErrorTest
    end
  end
end
