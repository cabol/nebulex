defmodule Nebulex.Cache.KVErrorTest do
  import Nebulex.CacheCase

  deftests do
    import Nebulex.CacheCase, only: [assert_error_module: 2, assert_error_reason: 2]

    describe "put/3 error:" do
      test "command failed", %{cache: cache} = ctx do
        assert {:error, %Nebulex.Error{module: module, reason: reason}} =
                 cache.put("hello", "world")

        assert_error_module(ctx, module)
        assert_error_reason(ctx, reason)
      end
    end

    describe "put_new/3 error:" do
      test "command failed", %{cache: cache} = ctx do
        assert {:error, %Nebulex.Error{module: module, reason: reason}} =
                 cache.put_new("hello", "world")

        assert_error_module(ctx, module)
        assert_error_reason(ctx, reason)
      end
    end

    describe "put_new!/3 error:" do
      test "raises an exception", %{cache: cache} do
        assert_raise Nebulex.Error, fn ->
          cache.put_new!("hello", "world")
        end
      end
    end

    describe "replace/3 error:" do
      test "command failed", %{cache: cache} = ctx do
        assert {:error, %Nebulex.Error{module: module, reason: reason}} =
                 cache.replace("hello", "world")

        assert_error_module(ctx, module)
        assert_error_reason(ctx, reason)
      end
    end

    describe "replace!/3 error:" do
      test "raises an exception", %{cache: cache} do
        assert_raise Nebulex.Error, fn ->
          cache.replace!("hello", "world")
        end
      end
    end

    describe "put_all/2 error:" do
      test "command failed", %{cache: cache} = ctx do
        assert {:error, %Nebulex.Error{module: module, reason: reason}} =
                 cache.put_all(%{"apples" => 1, "bananas" => 3})

        assert_error_module(ctx, module)
        assert_error_reason(ctx, reason)
      end
    end

    describe "put_all!/2 error:" do
      test "raises an exception", %{cache: cache} do
        assert_raise Nebulex.Error, fn ->
          cache.put_all!(other: 1)
        end
      end
    end

    describe "put_new_all/2 error:" do
      test "command failed", %{cache: cache} = ctx do
        assert {:error, %Nebulex.Error{module: module, reason: reason}} =
                 cache.put_new_all(%{"apples" => 1, "bananas" => 3})

        assert_error_module(ctx, module)
        assert_error_reason(ctx, reason)
      end
    end

    describe "put_new_all!/2 error:" do
      test "raises an exception", %{cache: cache} do
        assert_raise Nebulex.Error, fn ->
          cache.put_new_all!(other: 1)
        end
      end
    end

    describe "fetch/2 error:" do
      test "command failed", %{cache: cache} = ctx do
        assert {:error, %Nebulex.Error{module: module, reason: reason}} = cache.fetch(1)

        assert_error_module(ctx, module)
        assert_error_reason(ctx, reason)
      end
    end

    describe "fetch!/2 error:" do
      test "raises an exception", %{cache: cache} do
        assert_raise Nebulex.Error, fn ->
          cache.fetch!("raise")
        end
      end
    end

    describe "get/2 error:" do
      test "command failed", %{cache: cache} = ctx do
        assert {:error, %Nebulex.Error{module: module, reason: reason}} = cache.get("error")

        assert_error_module(ctx, module)
        assert_error_reason(ctx, reason)
      end
    end

    describe "get!/2 error:" do
      test "raises an exception", %{cache: cache} do
        assert_raise Nebulex.Error, fn ->
          cache.get!("raise")
        end
      end
    end

    describe "delete/2 error:" do
      test "command failed", %{cache: cache} = ctx do
        assert {:error, %Nebulex.Error{module: module, reason: reason}} = cache.delete("error")

        assert_error_module(ctx, module)
        assert_error_reason(ctx, reason)
      end
    end

    describe "delete!/2 error:" do
      test "raises an exception", %{cache: cache} do
        assert_raise Nebulex.Error, fn ->
          cache.delete!("raise")
        end
      end
    end

    describe "take/2 error:" do
      test "command failed", %{cache: cache} = ctx do
        assert {:error, %Nebulex.Error{module: module, reason: reason}} = cache.take("error")

        assert_error_module(ctx, module)
        assert_error_reason(ctx, reason)
      end
    end

    describe "take!/2 error:" do
      test "raises an exception", %{cache: cache} do
        assert_raise Nebulex.Error, fn ->
          cache.take!("raise")
        end
      end
    end

    describe "has_key?/1 error:" do
      test "command failed", %{cache: cache} = ctx do
        assert {:error, %Nebulex.Error{module: module, reason: reason}} = cache.has_key?("error")

        assert_error_module(ctx, module)
        assert_error_reason(ctx, reason)
      end
    end

    describe "update!/4 error:" do
      test "raises because put error", %{cache: cache} do
        assert_raise Nebulex.Error, fn ->
          cache.update!("error", 1, &String.to_integer/1)
        end
      end

      test "raises because fetch error", %{cache: cache} do
        assert_raise Nebulex.Error, fn ->
          cache.update!("error", 1, &String.to_integer/1)
        end
      end
    end

    describe "incr!/3 error:" do
      test "raises an exception", %{cache: cache} do
        assert_raise Nebulex.Error, fn ->
          cache.incr!(:raise)
        end
      end
    end

    describe "decr!/3 error:" do
      test "raises an exception", %{cache: cache} do
        assert_raise Nebulex.Error, fn ->
          cache.decr!(:raise)
        end
      end
    end
  end
end
