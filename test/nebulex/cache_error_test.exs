defmodule Nebulex.CacheErrorTest do
  use ExUnit.Case, async: true
  use Mimic

  # Inherit error tests
  use Nebulex.Cache.KVErrorTest
  use Nebulex.Cache.KVExpirationErrorTest
  use Nebulex.Cache.QueryableErrorTest

  setup do
    Nebulex.Cache.Registry
    |> stub(:lookup, fn _ ->
      %{adapter: Nebulex.FakeAdapter, telemetry: true, telemetry_prefix: [:nebulex, :test]}
    end)

    {:ok, cache: Nebulex.TestCache.Cache, name: __MODULE__}
  end

  describe "put!/3" do
    test "raises an error due to a timeout", %{cache: cache} do
      assert_raise Nebulex.Error, ~r/command execution timed out/, fn ->
        cache.put!(:error, :timeout)
      end
    end

    test "raises an error due to RuntimeError", %{cache: cache} do
      msg =
        Regex.escape(
          "the following exception occurred when executing a command.\n\n" <>
            "    ** (RuntimeError) runtime error\n"
        )

      assert_raise Nebulex.Error, ~r/#{msg}/, fn ->
        cache.put!(:error, %RuntimeError{})
      end
    end
  end
end
