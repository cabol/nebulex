defmodule Nebulex.Cache.QueryableErrorTest do
  import Nebulex.CacheCase

  deftests do
    import Nebulex.CacheCase, only: [assert_error_module: 2, assert_error_reason: 2]

    describe "get_all/2" do
      test "error: command failed", %{cache: cache} = ctx do
        assert {:error, %Nebulex.Error{module: module, reason: reason}} =
                 cache.get_all()

        assert_error_module ctx, module
        assert_error_reason ctx, reason
      end

      test "error: raises an exception", %{cache: cache} do
        assert_raise Nebulex.Error, fn ->
          cache.get_all!()
        end
      end
    end

    describe "count_all/2" do
      test "error: command failed", %{cache: cache} = ctx do
        assert {:error, %Nebulex.Error{module: module, reason: reason}} =
                 cache.count_all()

        assert_error_module ctx, module
        assert_error_reason ctx, reason
      end

      test "error: raises an exception", %{cache: cache} do
        assert_raise Nebulex.Error, fn ->
          cache.count_all!()
        end
      end
    end

    describe "delete_all/2" do
      test "error: command failed", %{cache: cache} = ctx do
        assert {:error, %Nebulex.Error{module: module, reason: reason}} =
                 cache.delete_all()

        assert_error_module ctx, module
        assert_error_reason ctx, reason
      end

      test "error: raises an exception", %{cache: cache} do
        assert_raise Nebulex.Error, fn ->
          cache.delete_all!()
        end
      end
    end

    describe "stream/2" do
      test "error: command failed", %{cache: cache} = ctx do
        assert {:error, %Nebulex.Error{module: module, reason: reason}} =
                 cache.stream()

        assert_error_module ctx, module
        assert_error_reason ctx, reason
      end

      test "error: raises an exception", %{cache: cache} do
        assert_raise Nebulex.Error, fn ->
          cache.stream!()
        end
      end
    end
  end
end
