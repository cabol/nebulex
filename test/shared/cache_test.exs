defmodule Nebulex.CacheTest do
  @moduledoc """
  Shared Tests
  """

  @doc false
  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      alias Nebulex.Object

      @cache Keyword.fetch!(opts, :cache)

      test "delete" do
        @cache.new_generation
        for x <- 1..3, do: @cache.set x, x

        assert @cache.get(1) == 1
        @cache.new_generation
        %Object{value: 2, key: 2, version: v2} = @cache.get(2, return: :object)

        assert @cache.delete(1, return: :key) == 1
        refute @cache.get(1)

        %Object{value: 2, key: 2, version: _} = @cache.delete(2, return: :object, version: v2)
        refute @cache.get(2)

        refute @cache.delete(:non_existent)
        refute :a |> @cache.set(1, return: :key) |> @cache.delete
        refute @cache.get(:a)

        assert_raise Nebulex.VersionConflictError, fn ->
          @cache.delete(3, version: -1)
        end

        assert @cache.set(:a, 1) == 1
        assert @cache.get(:a) == 1
        assert @cache.delete(:a, version: -1, on_conflict: :delete) == 1
        refute @cache.get(:a)

        assert @cache.set(:b, 1) == 1
        assert @cache.get(:b) == 1
        assert @cache.delete(:b, version: -1, on_conflict: :nothing) == 1
        assert @cache.get(:b) == 1
      end

      test "get" do
        @cache.new_generation
        for x <- 1..2, do: @cache.set x, x

        assert @cache.get(1) == 1
        @cache.new_generation
        assert @cache.get(2) == 2
        refute @cache.get(3)

        %Object{value: 1, key: 1, version: v1} = @cache.get(1, return: :object)
        %Object{value: 2, key: 2, version: _} = @cache.get(2, return: :object)
        refute @cache.get(3, return: :object)

        assert @cache.get(1, version: v1) == 1
        assert_raise Nebulex.VersionConflictError, fn ->
          assert @cache.get(1, version: -1)
        end

        assert @cache.set(:a, 1) == 1
        assert @cache.get(:a, version: -1, on_conflict: :nothing) == 1
        refute @cache.get(:a, version: -1, on_conflict: nil)
      end

      test "get!" do
        @cache.new_generation
        for x <- 1..2, do: @cache.set x, x

        assert @cache.get!(1) == 1
        @cache.new_generation
        assert @cache.get!(2) == 2
        assert_raise KeyError, fn ->
          @cache.get!(3)
        end
      end

      test "set" do
        @cache.new_generation
        for x <- 1..4, do: @cache.set x, x

        @cache.new_generation
        assert @cache.get(1) == 1
        assert @cache.get(2) == 2

        %Object{value: 11, key: 1, version: v1} = @cache.set 1, 11, return: :object
        %Object{value: 12, key: 1, version: v2} = @cache.set 1, 12, return: :object, version: v1
        assert v1 != v2

        _ = @cache.set 1, 13, return: :object, version: -1, on_conflict: :nothing
        _ = @cache.set 1, 13, return: :object, version: -1, on_conflict: :replace

        assert_raise Nebulex.VersionConflictError, fn ->
          @cache.set 1, 13, return: :object, version: -1
        end

        for x <- 3..4, do: @cache.set x, x*x
        assert @cache.get(3) == 9
        assert @cache.get(4) == 16

        assert @cache.set(:a, 1, version: -1) == 1

        assert_raise ArgumentError, fn ->
          @cache.set(:a, 1, version: -1, on_conflict: :invalid) == 1
        end
      end

      test "has_key?" do
        @cache.new_generation
        for x <- 1..2, do: @cache.set x, x

        assert @cache.has_key?(1)
        assert @cache.has_key?(2)
        refute @cache.has_key?(3)
      end

      test "all" do
        @cache.new_generation
        expected = for x <- 1..100, do: @cache.set(x, x, return: :key)

        assert @cache.all == expected
        assert @cache.all(return: :value) == expected
        [%Object{} | _] = @cache.all(return: :object)
      end

      test "pop" do
        @cache.new_generation
        for x <- 1..2, do: @cache.set x, x

        assert @cache.pop(1) == 1
        assert @cache.pop(2) == 2
        refute @cache.pop(3)

        for x <- 1..3, do: refute @cache.get(x)

        %Object{value: "hello", key: :a} =
          :a
          |> @cache.set("hello", return: :key)
          |> @cache.pop(return: :object)

        assert_raise Nebulex.VersionConflictError, fn ->
          :b
          |> @cache.set("hello", return: :key)
          |> @cache.pop(version: -1)
        end
      end

      test "key expiration with ttl" do
        @cache.new_generation

        assert 11 ==
          1
          |> @cache.set(11, ttl: 1, return: :key)
          |> @cache.get!

        _ = :timer.sleep 1010

        refute @cache.get(1)
      end

      test "transaction" do
        @cache.new_generation

        refute @cache.transaction 1, fn ->
          @cache.set(1, 11, return: :key)
          |> @cache.get!(return: :key)
          |> @cache.delete(return: :key)
          |> @cache.get
        end
      end

      test "fail on Nebulex.VersionConflictError" do
        @cache.new_generation
        assert @cache.set(1, 1) == 1

        message = ~r"could not perform :set because versions mismatch."
        assert_raise Nebulex.VersionConflictError, message, fn ->
          @cache.set(1, 2, version: -1)
        end
      end
    end
  end
end
