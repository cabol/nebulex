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

        2 = @cache.delete(2, return: :object, version: v2)
        refute @cache.get(2)

        assert @cache.delete(:non_existent) == :non_existent
        assert :a |> @cache.set(1, return: :key) |> @cache.delete == :a
        refute @cache.get(:a)

        assert_raise Nebulex.VersionConflictError, fn ->
          @cache.delete(3, version: -1)
        end

        assert @cache.set(:a, 1) == 1
        assert @cache.get(:a) == 1
        assert @cache.delete(:a, version: -1, on_conflict: :delete) == :a
        refute @cache.get(:a)

        assert @cache.set(:b, 1) == 1
        assert @cache.get(:b) == 1
        assert @cache.delete(:b, version: -1, on_conflict: :nothing) == :b
        assert @cache.get(:b) == 1
      end

      test "get" do
        @cache.new_generation
        for x <- 1..2, do: @cache.set x, x

        assert @cache.get(1) == 1
        @cache.new_generation
        assert @cache.get(2) == 2
        refute @cache.get(3)
        refute @cache.get(3, return: :object)

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

        assert @cache.set("foo", nil) == nil
        refute @cache.get("foo")
      end

      test "has_key?" do
        @cache.new_generation
        for x <- 1..2, do: @cache.set x, x

        assert @cache.has_key?(1)
        assert @cache.has_key?(2)
        refute @cache.has_key?(3)
      end

      test "size" do
        @cache.new_generation
        for x <- 1..100, do: @cache.set(x, x)
        assert @cache.size == 100

        for x <- 1..50, do: @cache.delete(x)
        assert @cache.size == 50

        @cache.new_generation
        for x <- 51..60, do: assert @cache.get(x) == x
        assert @cache.size == 50
      end

      test "flush" do
        Enum.each(1..2, fn _ ->
          @cache.new_generation
          for x <- 1..100, do: @cache.set(x, x)

          assert @cache.flush == :ok
          _ = :timer.sleep(500)

          for x <- 1..100, do: refute @cache.get(x)
        end)
      end

      test "keys" do
        @cache.new_generation
        set1 = for x <- 1..50, do: @cache.set(x, x)

        @cache.new_generation
        set2 = for x <- 51..100, do: @cache.set(x, x)
        for x <- 1..30, do: assert @cache.get(x) == x
        expected = :lists.usort(set1 ++ set2)

        assert @cache.keys == expected

        set3 = for x <- 20..60, do: @cache.delete(x)

        assert @cache.keys == :lists.usort(expected -- set3)
      end

      test "reduce" do
        reducer_fun =
          case @cache.__adapter__ do
            Nebulex.Adapters.Dist ->
              &(@cache.reducer_fun/2)
            _ ->
              fn({key, value}, {acc1, acc2}) ->
                if Map.has_key?(acc1, key),
                  do: {acc1, acc2},
                  else: {Map.put(acc1, key, value), value + acc2}
              end
          end

        @cache.new_generation
        set1 = for x <- 1..3, do: @cache.set(x, x)

        @cache.new_generation
        set2 = for x <- 2..5, do: @cache.set(x, x)
        expected = :maps.from_list(for x <- 1..5, do: {x, x})

        assert @cache.reduce({%{}, 0}, reducer_fun) == {expected, 15}
      end

      test "to_map" do
        @cache.new_generation
        set1 = for x <- 1..50, do: @cache.set(x, x)

        @cache.new_generation
        set2 = for x <- 51..100, do: @cache.set(x, x)
        for x <- 1..30, do: assert @cache.get(x) == x
        expected = :maps.from_list(for x <- 1..100, do: {x, x})

        assert @cache.to_map == expected
        assert @cache.to_map(return: :value) == expected
        %Object{key: 1} = Map.get(@cache.to_map(return: :object), 1)
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

      test "update_counter" do
        @cache.new_generation

        assert @cache.update_counter(:counter) == 1
        assert @cache.update_counter(:counter) == 2
        assert @cache.update_counter(:counter, 2) == 4
        assert @cache.update_counter(:counter, 3) == 7
        assert @cache.update_counter(:counter, 0) == 7

        assert @cache.get(:counter) == 7

        assert @cache.update_counter(:counter, -1) == 6
        assert @cache.update_counter(:counter, -1) == 5
        assert @cache.update_counter(:counter, -2) == 3
        assert @cache.update_counter(:counter, -3) == 0

        expected_counter_obj = %Object{key: :counter, value: 0, ttl: :infinity}
        assert @cache.get(:counter, return: :object) == expected_counter_obj

        assert @cache.update_counter(:counter_with_ttl, 1, ttl: 1) == 1
        assert @cache.update_counter(:counter_with_ttl) == 2
        assert @cache.get(:counter_with_ttl) == 2
        _ = :timer.sleep(1010)
        refute @cache.get(:counter_with_ttl)

        assert_raise ArgumentError, fn ->
          @cache.update_counter(:counter, "foo")
        end
      end

      test "key expiration with ttl" do
        @cache.new_generation

        assert 11 ==
          1
          |> @cache.set(11, ttl: 1, return: :key)
          |> @cache.get!

        _ = :timer.sleep(1010)
        refute @cache.get(1)
      end

      test "transaction" do
        @cache.new_generation

        refute @cache.transaction fn ->
          @cache.set(1, 11, return: :key)
          |> @cache.get!(return: :key)
          |> @cache.delete(return: :key)
          |> @cache.get
        end

        assert_raise MatchError, fn ->
          @cache.transaction fn ->
            res =
              @cache.set(1, 11, return: :key)
              |> @cache.get!(return: :key)
              |> @cache.delete(return: :key)
              |> @cache.get
            :ok = res
          end
        end
      end

      test "transaction aborted" do
        @cache.new_generation

        spawn_link fn ->
          @cache.transaction(fn ->
            :timer.sleep(1100)
          end, keys: [1], retries: 1)
        end
        :timer.sleep(200)

        assert_raise RuntimeError, "transaction aborted", fn ->
          @cache.transaction(fn ->
            @cache.get(1)
          end, keys: [1], retries: 1)
        end
      end

      test "in_transaction?" do
        @cache.new_generation

        refute @cache.in_transaction?

        @cache.transaction fn ->
          _ = @cache.set(1, 11, return: :key)
          true = @cache.in_transaction?
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
