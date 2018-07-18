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
        for x <- 1..3, do: @cache.set x, x

        assert 1 == @cache.get(1)
        @cache.new_generation()
        %Object{value: 2, key: 2, version: v2} = @cache.get(2, return: :object)

        assert 1 == @cache.delete(1, return: :key)
        refute @cache.get(1)

        2 = @cache.delete(2, return: :key, version: v2)
        refute @cache.get(2)

        assert :non_existent == @cache.delete(:non_existent, return: :key)
        assert :a == :a |> @cache.set(1, return: :key) |> @cache.delete(return: :key)
        refute @cache.get(:a)

        assert_raise Nebulex.ConflictError, fn ->
          @cache.delete(3, version: -1)
        end

        assert 1 == @cache.set(:a, 1)
        assert 1 == @cache.get(:a)
        assert :a == @cache.delete(:a, version: -1, on_conflict: :override, return: :key)
        refute @cache.get(:a)

        assert 1 == @cache.set(:b, 1)
        assert 1 == @cache.get(:b)
        assert :b == @cache.delete(:b, version: -1, on_conflict: :nothing, return: :key)
        assert 1 == @cache.get(:b)

        assert :x == @cache.delete(:x, version: -1, on_conflict: :override, return: :key)
        refute @cache.get(:x)
      end

      test "get" do
        for x <- 1..2, do: @cache.set(x, x)

        assert 1 == @cache.get(1)
        @cache.new_generation()
        assert 2 == @cache.get(2)
        refute @cache.get(3)
        refute @cache.get(3, return: :object)

        %Object{value: 1, key: 1, version: v1} = @cache.get(1, return: :object)
        %Object{value: 2, key: 2, version: _} = @cache.get(2, return: :object)
        refute @cache.get(3, return: :object)

        assert 1 ==  @cache.get(1, version: v1)

        assert_raise Nebulex.ConflictError, fn ->
          assert @cache.get(1, version: -1)
        end

        assert 1 == @cache.set(:a, 1)
        assert 1 == @cache.get(:a, version: -1, on_conflict: :nothing)
        assert 1 == @cache.get(:a, version: -1, on_conflict: :override)
      end

      test "get!" do
        for x <- 1..2, do: @cache.set(x, x)

        assert 1 == @cache.get!(1)
        @cache.new_generation()
        assert 2 == @cache.get!(2)

        assert_raise KeyError, fn ->
          @cache.get!(3)
        end
      end

      test "set" do
        for x <- 1..4, do: @cache.set(x, x)

        @cache.new_generation()
        assert 1 == @cache.get(1)
        assert 2 == @cache.get(2)

        %Object{value: 11, key: 1, version: v1} = @cache.set(1, 11, return: :object)
        %Object{value: 12, key: 1, version: v2} = @cache.set(1, 12, return: :object, version: v1)
        assert v1 != v2

        assert 12 == @cache.set(1, 13, version: -1, on_conflict: :nothing)
        assert 13 == @cache.set(1, 13, version: -1, on_conflict: :override)

        assert_raise Nebulex.ConflictError, fn ->
          @cache.set(1, 13, return: :object, version: -1)
        end

        for x <- 3..4, do: @cache.set(x, x * x)
        assert 9 == @cache.get(3)
        assert 16 == @cache.get(4)

        assert 1 == @cache.set(:a, 1, version: -1)

        assert_raise ArgumentError, fn ->
          @cache.set(:a, 1, version: -1, on_conflict: :invalid) == 1
        end

        refute @cache.set("foo", nil)
        refute @cache.get("foo")
      end

      test "has_key?" do
        for x <- 1..2, do: @cache.set(x, x)

        assert @cache.has_key?(1)
        assert @cache.has_key?(2)
        refute @cache.has_key?(3)
      end

      test "size" do
        for x <- 1..100, do: @cache.set(x, x)
        assert 100 == @cache.size

        for x <- 1..50, do: @cache.delete(x)
        assert 50 == @cache.size

        @cache.new_generation()
        for x <- 51..60, do: assert @cache.get(x) == x
        assert 50 == @cache.size()
      end

      test "flush" do
        Enum.each(1..2, fn _ ->
          for x <- 1..100, do: @cache.set(x, x)

          assert @cache.flush() == :ok
          _ = :timer.sleep(500)

          for x <- 1..100, do: refute @cache.get(x)
        end)
      end

      test "keys" do
        set1 = for x <- 1..50, do: @cache.set(x, x)

        @cache.new_generation()
        set2 = for x <- 51..100, do: @cache.set(x, x)
        for x <- 1..30, do: assert @cache.get(x) == x
        expected = :lists.usort(set1 ++ set2)

        assert expected == @cache.keys()

        set3 = for x <- 20..60, do: @cache.delete(x, return: :key)

        assert @cache.keys() == :lists.usort(expected -- set3)
      end

      test "reduce" do
        local_fun =
          fn(object, {acc1, acc2}) ->
            if Map.has_key?(acc1, object.key),
              do: {acc1, acc2},
              else: {Map.put(acc1, object.key, object.value), object.value + acc2}
          end

        reducer_fun =
          case @cache.__adapter__ do
            Nebulex.Adapters.Dist -> &(@cache.reducer_fun/2)
            _adapter              -> local_fun
          end

        set1 = for x <- 1..3, do: @cache.set(x, x)
        @cache.new_generation()
        set2 = for x <- 2..5, do: @cache.set(x, x)
        expected = :maps.from_list(for x <- 1..5, do: {x, x})

        assert {expected, 15} == @cache.reduce({%{}, 0}, reducer_fun)
      end

      test "to_map" do
        set1 = for x <- 1..50, do: @cache.set(x, x)

        @cache.new_generation()
        set2 = for x <- 51..100, do: @cache.set(x, x)
        for x <- 1..30, do: assert @cache.get(x) == x
        expected = :maps.from_list(for x <- 1..100, do: {x, x})

        assert expected == @cache.to_map()
        assert expected == @cache.to_map(return: :value)
        %Object{key: 1} = Map.get(@cache.to_map(return: :object), 1)
      end

      test "pop" do
        for x <- 1..2, do: @cache.set(x, x)

        assert 1 == @cache.pop(1)
        assert 2 == @cache.pop(2)
        refute @cache.pop(3)

        for x <- 1..3, do: refute @cache.get(x)

        %Object{value: "hello", key: :a} =
          :a
          |> @cache.set("hello", return: :key)
          |> @cache.pop(return: :object)

        assert_raise Nebulex.ConflictError, fn ->
          :b
          |> @cache.set("hello", return: :key)
          |> @cache.pop(version: -1)
        end
      end

      test "update" do
        for x <- 1..2, do: @cache.set x, x

        assert "1" == @cache.update(1, 1, &Integer.to_string/1)
        assert "2" == @cache.update(2, 1, &Integer.to_string/1)
        assert 1 == @cache.update(3, 1, &Integer.to_string/1)
        refute @cache.update(4, nil, &Integer.to_string/1)
        refute @cache.get(4)

        %Object{key: 11, value: 1, ttl: _, version: _} =
          @cache.update(11, 1, &Integer.to_string/1, return: :object)

        assert 1 == @cache.update(3, 3, &Integer.to_string/1, version: -1, on_conflict: :nothing)
        assert "1" == @cache.update(3, 3, &Integer.to_string/1, version: -1, on_conflict: :override)

        assert_raise Nebulex.ConflictError, fn ->
          :a
          |> @cache.set(1, return: :key)
          |> @cache.update(0, &Integer.to_string/1, version: -1)
        end
      end

      test "update_counter" do
        assert 1 == @cache.update_counter(:counter)
        assert 2 == @cache.update_counter(:counter)
        assert 4 == @cache.update_counter(:counter, 2)
        assert 7 == @cache.update_counter(:counter, 3)
        assert 7 == @cache.update_counter(:counter, 0)

        assert 7 == @cache.get(:counter)

        assert 6 == @cache.update_counter(:counter, -1)
        assert 5 == @cache.update_counter(:counter, -1)
        assert 3 == @cache.update_counter(:counter, -2)
        assert 0 == @cache.update_counter(:counter, -3)

        expected_counter_obj = %Object{key: :counter, value: 0, ttl: :infinity}
        assert @cache.get(:counter, return: :object) == expected_counter_obj

        assert 1 == @cache.update_counter(:counter_with_ttl, 1, ttl: 1)
        assert 2 == @cache.update_counter(:counter_with_ttl)
        assert 2 == @cache.get(:counter_with_ttl)
        _ = :timer.sleep(1010)
        refute @cache.get(:counter_with_ttl)

        assert_raise ArgumentError, fn ->
          @cache.update_counter(:counter, "foo")
        end
      end

      test "key expiration with ttl" do
        assert 11 ==
          1
          |> @cache.set(11, ttl: 2, return: :key)
          |> @cache.get!()

        _ = :timer.sleep(500)
        assert 11 == @cache.get(1)
        _ = :timer.sleep(1510)
        refute @cache.get(1)

        assert "bar" == @cache.set("foo", "bar", ttl: 2)
        _ = :timer.sleep(900)
        assert "bar" == @cache.get("foo")
        _ = :timer.sleep(1200)
        refute @cache.get("foo")

        assert "bar" == @cache.set("foo", "bar", ttl: 2)
        @cache.new_generation()
        _ = :timer.sleep(900)
        assert "bar" == @cache.get("foo")
        _ = :timer.sleep(1200)
        refute @cache.get("foo")
      end

      test "object ttl" do
        obj =
          1
          |> @cache.set(11, ttl: 3, return: :key)
          |> @cache.get!(return: :object)

        for x <- 3..0 do
          assert x == Object.ttl(obj)
          :timer.sleep(1000)
        end

        assert :infinity ==
          1
          |> @cache.set(11, return: :object)
          |> Object.ttl()

        assert 3 ==
          1
          |> @cache.update(nil, &:erlang.phash2/1, ttl: 3, return: :object)
          |> Object.ttl()

        assert :infinity == Object.ttl(%Object{})
      end

      test "get_and_update an existing object with ttl" do
        assert ttl = @cache.set(1, 1, ttl: 2, return: :object).ttl
        assert 1 == @cache.get(1)

        _ = :timer.sleep(500)
        assert {1, 2} == @cache.get_and_update(1, &Nebulex.TestCache.Dist.get_and_update_fun/1)
        assert ttl == @cache.get(1, return: :object).ttl

        _ = :timer.sleep(2000)
        refute @cache.get(1)
      end

      test "update an existing object with ttl" do
        assert ttl = @cache.set(1, 1, ttl: 2, return: :object).ttl
        assert 1 == @cache.get(1)

        _ = :timer.sleep(500)
        assert "1" == @cache.update(1, 10, &Integer.to_string/1)
        assert ttl == @cache.get(1, return: :object).ttl

        _ = :timer.sleep(2000)
        refute @cache.get(1)
      end

      test "transaction" do
        refute @cache.transaction fn ->
          1
          |> @cache.set(11, return: :key)
          |> @cache.get!(return: :key)
          |> @cache.delete(return: :key)
          |> @cache.get()
        end

        assert_raise MatchError, fn ->
          @cache.transaction fn ->
            :ok =
              1
              |> @cache.set(11, return: :key)
              |> @cache.get!(return: :key)
              |> @cache.delete(return: :key)
              |> @cache.get()
          end
        end
      end

      test "transaction aborted" do
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
        refute @cache.in_transaction?()

        @cache.transaction fn ->
          _ = @cache.set(1, 11, return: :key)
          true = @cache.in_transaction?()
        end
      end

      test "fail on Nebulex.ConflictError" do
        assert 1 == @cache.set(1, 1)

        message = ~r"could not perform cache action because versions mismatch."
        assert_raise Nebulex.ConflictError, message, fn ->
          @cache.set(1, 2, version: -1)
        end
      end
    end
  end
end
