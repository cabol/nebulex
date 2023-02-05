defmodule Nebulex.Cache.RegistryTest do
  use ExUnit.Case, async: true

  import Nebulex.CacheCase, only: [test_with_dynamic_cache: 3]

  alias Nebulex.TestCache.Cache

  describe "lookup/1" do
    test "error: returns an error with reason ':registry_lookup_error'" do
      assert Nebulex.Cache.Registry.lookup(self()) ==
               {:error,
                %Nebulex.Error{
                  module: Nebulex.Error,
                  reason: {:registry_lookup_error, self()}
                }}
    end
  end

  describe "all_running/0" do
    test "ok: returns all running cache names" do
      test_with_dynamic_cache(Cache, [name: :registry_test_cache], fn ->
        assert :registry_test_cache in Nebulex.Cache.Registry.all_running()
      end)
    end

    test "ok: returns all running cache pids" do
      test_with_dynamic_cache(Cache, [name: nil], fn ->
        assert Nebulex.Cache.Registry.all_running() |> Enum.any?(&is_pid/1)
      end)
    end
  end
end
