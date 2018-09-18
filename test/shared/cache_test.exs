defmodule Nebulex.CacheTest do
  @moduledoc """
  Shared Tests
  """

  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      @cache Keyword.fetch!(opts, :cache)

      use Nebulex.Cache.ObjectTest, cache: @cache
      use Nebulex.Cache.TransactionTest, cache: @cache
    end
  end
end
