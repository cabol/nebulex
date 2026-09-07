defmodule Nebulex.Cache.CompositeKVErrorTest do
  import Nebulex.CacheCase

  deftests do
    import Nebulex.CacheCase, only: [assert_error_module: 2, assert_error_reason: 2]

    describe "composite KV error" do
      test "get_and_update/3", %{cache: cache} = ctx do
        assert {:error, %Nebulex.Error{module: module, reason: reason}} =
                 cache.get_and_update("error", &{&1, &1})

        assert_error_module ctx, module
        assert_error_reason ctx, reason
      end

      test "get_and_update!/3 raises an exception", %{cache: cache} do
        assert_raise Nebulex.Error, fn ->
          cache.get_and_update!("error", &{&1, &1})
        end
      end

      test "update/4", %{cache: cache} = ctx do
        assert {:error, %Nebulex.Error{module: module, reason: reason}} =
                 cache.update("error", 1, &Integer.to_string/1)

        assert_error_module ctx, module
        assert_error_reason ctx, reason
      end

      test "update!/4 raises an exception", %{cache: cache} do
        assert_raise Nebulex.Error, fn ->
          cache.update!("error", 1, &Integer.to_string/1)
        end
      end

      test "fetch_or_store/3", %{cache: cache} = ctx do
        assert {:error, %Nebulex.Error{module: module, reason: reason}} =
                 cache.fetch_or_store("error", &cache.fetch_or_store_fun/0)

        assert_error_module ctx, module
        assert_error_reason ctx, reason
      end

      test "fetch_or_store!/3 raises an exception", %{cache: cache} do
        assert_raise Nebulex.Error, fn ->
          cache.fetch_or_store!("error", &cache.fetch_or_store_fun/0)
        end
      end

      test "get_or_store/3", %{cache: cache} = ctx do
        assert {:error, %Nebulex.Error{module: module, reason: reason}} =
                 cache.get_or_store("error", &cache.get_or_store_fun/0)

        assert_error_module ctx, module
        assert_error_reason ctx, reason
      end

      test "get_or_store!/3 raises an exception", %{cache: cache} do
        assert_raise Nebulex.Error, fn ->
          cache.get_or_store!("error", &cache.get_or_store_fun/0)
        end
      end
    end
  end
end
