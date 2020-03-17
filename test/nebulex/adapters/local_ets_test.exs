defmodule Nebulex.Adapters.LocalEtsTest do
  use ExUnit.Case, async: true
  use Nebulex.CacheTest, cache: Nebulex.TestCache.Local
  use Nebulex.LocalTest, cache: Nebulex.TestCache.Local

  alias Nebulex.TestCache.Local

  test "backend" do
    assert Local.__backend__() == :ets
  end
end
