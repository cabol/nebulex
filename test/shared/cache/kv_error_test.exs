defmodule Nebulex.Cache.KVErrorTest do
  import Nebulex.CacheCase

  deftests do
    import Nebulex.CacheCase, only: [assert_error_module: 2, assert_error_reason: 2]

    describe "KV error" do
      test "put/3", %{cache: cache} = ctx do
        assert {:error, %Nebulex.Error{module: module, reason: reason}} =
                 cache.put("error", "error")

        assert_error_module ctx, module
        assert_error_reason ctx, reason
      end

      test "put_new/3", %{cache: cache} = ctx do
        assert {:error, %Nebulex.Error{module: module, reason: reason}} =
                 cache.put_new("error", "error")

        assert_error_module ctx, module
        assert_error_reason ctx, reason
      end

      test "put_new!/3 raises an exception", %{cache: cache} do
        assert_raise Nebulex.Error, fn ->
          cache.put_new!("error", "error")
        end
      end

      test "replace/3", %{cache: cache} = ctx do
        assert {:error, %Nebulex.Error{module: module, reason: reason}} =
                 cache.replace("error", "error")

        assert_error_module ctx, module
        assert_error_reason ctx, reason
      end

      test "replace!/3 raises an exception", %{cache: cache} do
        assert_raise Nebulex.Error, fn ->
          cache.replace!("error", "error")
        end
      end

      test "put_all/2", %{cache: cache} = ctx do
        assert {:error, %Nebulex.Error{module: module, reason: reason}} =
                 cache.put_all(%{"error1" => 1, "error2" => 3})

        assert_error_module ctx, module
        assert_error_reason ctx, reason
      end

      test "put_all!/2 raises an exception", %{cache: cache} do
        assert_raise Nebulex.Error, fn ->
          cache.put_all!(error: 1)
        end
      end

      test "put_new_all/2", %{cache: cache} = ctx do
        assert {:error, %Nebulex.Error{module: module, reason: reason}} =
                 cache.put_new_all(%{"error1" => 1, "error2" => 3})

        assert_error_module ctx, module
        assert_error_reason ctx, reason
      end

      test "put_new_all!/2 raises an exception", %{cache: cache} do
        assert_raise Nebulex.Error, fn ->
          cache.put_new_all!(error: 1)
        end
      end

      test "fetch/2", %{cache: cache} = ctx do
        assert {:error, %Nebulex.Error{module: module, reason: reason}} = cache.fetch(:error)

        assert_error_module ctx, module
        assert_error_reason ctx, reason
      end

      test "fetch!/2 raises an exception", %{cache: cache} do
        assert_raise Nebulex.Error, fn ->
          cache.fetch!("raise")
        end
      end

      test "get/2", %{cache: cache} = ctx do
        assert {:error, %Nebulex.Error{module: module, reason: reason}} = cache.get("error")

        assert_error_module ctx, module
        assert_error_reason ctx, reason
      end

      test "get!/2 raises an exception", %{cache: cache} do
        assert_raise Nebulex.Error, fn ->
          cache.get!("raise")
        end
      end

      test "delete/2", %{cache: cache} = ctx do
        assert {:error, %Nebulex.Error{module: module, reason: reason}} = cache.delete("error")

        assert_error_module ctx, module
        assert_error_reason ctx, reason
      end

      test "delete!/2 raises an exception", %{cache: cache} do
        assert_raise Nebulex.Error, fn ->
          cache.delete!("raise")
        end
      end

      test "take/2", %{cache: cache} = ctx do
        assert {:error, %Nebulex.Error{module: module, reason: reason}} = cache.take("error")

        assert_error_module ctx, module
        assert_error_reason ctx, reason
      end

      test "take!/2 raises an exception", %{cache: cache} do
        assert_raise Nebulex.Error, fn ->
          cache.take!("raise")
        end
      end

      test "has_key?/1 command failed", %{cache: cache} = ctx do
        assert {:error, %Nebulex.Error{module: module, reason: reason}} = cache.has_key?("error")

        assert_error_module ctx, module
        assert_error_reason ctx, reason
      end

      test "update!/4 raises because put error", %{cache: cache} do
        assert_raise Nebulex.Error, fn ->
          cache.update!("error", 1, &String.to_integer/1)
        end
      end

      test "update!/4 raises because fetch error", %{cache: cache} do
        assert_raise Nebulex.Error, fn ->
          cache.update!("error", 1, &String.to_integer/1)
        end
      end

      test "incr!/3 raises an exception", %{cache: cache} do
        assert_raise Nebulex.Error, fn ->
          cache.incr!(:raise)
        end
      end

      test "decr!/3 aises an exception", %{cache: cache} do
        assert_raise Nebulex.Error, fn ->
          cache.decr!(:raise)
        end
      end
    end
  end
end
