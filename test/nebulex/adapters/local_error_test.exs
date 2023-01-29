defmodule Nebulex.Adapters.LocalErrorTest do
  use ExUnit.Case, async: true
  use Mimic

  # Inherit error tests
  use Nebulex.Cache.EntryErrorTest
  use Nebulex.Cache.EntryExpirationErrorTest

  setup do
    Nebulex.Cache.Registry
    |> expect(:lookup, fn _ -> {:ok, %{adapter: Nebulex.FakeAdapter}} end)

    {:ok, cache: Nebulex.TestCache.Cache, name: :local_error_cache}
  end

  describe "put!/3" do
    test "raises an error", %{cache: cache} do
      assert_raise RuntimeError, ~r"runtime error", fn ->
        cache.put!(:error, %RuntimeError{})
      end
    end
  end
end
