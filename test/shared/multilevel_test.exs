defmodule Nebulex.MultilevelTest do
  @moduledoc """
  Shared Tests
  """

  @doc false
  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      alias Nebulex.Object

      @cache Keyword.fetch!(opts, :cache)
      @levels Keyword.fetch!(Application.fetch_env!(:nebulex, @cache), :levels)
      @l1 :lists.nth(1, @levels)
      @l2 :lists.nth(2, @levels)
      @l3 :lists.nth(3, @levels)

      setup do
        {:ok, ml_cache} = @cache.start_link()
        levels_and_pids = start_levels()
        :ok

        on_exit fn ->
          stop_levels(levels_and_pids)
          if Process.alive?(ml_cache), do: @cache.stop(ml_cache, 1)
        end
      end

      test "fail on __before_compile__ because missing levels config" do
        assert_raise ArgumentError, ~r"missing :levels configuration", fn ->
          defmodule MissingLevelsConfig do
            use Nebulex.Cache, otp_app: :nebulex, adapter: Nebulex.Adapters.Multilevel
          end
        end
      end

      test "fail on __before_compile__ because empty level list" do
        :ok = Application.put_env(:nebulex, String.to_atom("#{__MODULE__}.EmptyLevelList"), [levels: []])

        msg = ~r":levels configuration in config must have at least one level"
        assert_raise ArgumentError, msg, fn ->
          defmodule EmptyLevelList do
            use Nebulex.Cache, otp_app: :nebulex, adapter: Nebulex.Adapters.Multilevel
          end
        end
      end

      test "set" do
        assert @cache.set(1, 1) == 1
        assert @l1.get(1) == 1
        refute @l2.get(1)
        refute @l3.get(1)

        assert @cache.set(2, 2, level: 2) == 2
        assert @l2.get(2) == 2
        refute @l1.get(2)
        refute @l3.get(2)

        assert @cache.set(3, 3, level: :all) == 3
        assert @l1.get(3) == 3
        assert @l2.get(3) == 3
        assert @l3.get(3) == 3

        assert @cache.set("foo", nil) == nil
        refute @cache.get("foo")
      end

      test "delete" do
        assert @cache.set(1, 1) == 1
        assert @cache.set(2, 2, level: 2) == 2
        assert @cache.set(3, 3, level: :all) == 3

        assert @cache.delete(1, return: :key) == 1
        refute @l1.get(1)
        refute @l2.get(1)
        refute @l3.get(1)

        assert @cache.delete(2, return: :key, level: 2) == 2
        refute @l1.get(2)
        refute @l2.get(2)
        refute @l3.get(2)

        assert @cache.delete(3, return: :key, level: :all) == 3
        refute @l1.get(3)
        refute @l2.get(3)
        refute @l3.get(3)
      end

      test "has_key?" do
        assert @cache.set(1, 1) == 1
        assert @cache.set(2, 2, level: 2) == 2
        assert @cache.set(3, 3, level: :all) == 3

        assert @cache.has_key?(1)
        assert @cache.has_key?(2)
        assert @cache.has_key?(3)
        refute @cache.has_key?(4)
      end

      test "size" do
        for x <- 1..10, do: @l1.set(x, x)
        for x <- 11..20, do: @l2.set(x, x)
        for x <- 21..30, do: @l3.set(x, x)
        assert @cache.size() == 30

        for x <- [1, 11, 21], do: @cache.delete(x)
        assert @cache.size() == 29

        assert @l1.delete(1) == 1
        assert @l2.delete(11) == 11
        assert @l3.delete(21) == 21
        assert @cache.size() == 27
      end

      test "flush" do
        for x <- 1..10, do: @l1.set(x, x)
        for x <- 11..20, do: @l2.set(x, x)
        for x <- 21..30, do: @l3.set(x, x)

        assert @cache.flush() == :ok
        _ = :timer.sleep(500)

        for x <- 1..30, do: refute @cache.get(x)
      end

      test "keys" do
        l1 = for x <- 1..30, do: @l1.set(x, x)
        l2 = for x <- 20..60, do: @l2.set(x, x)
        l3 = for x <- 50..100, do: @l3.set(x, x)
        expected = :lists.usort(l1 ++ l2 ++ l3)

        assert @cache.keys() == expected

        del = for x <- 20..60, do: @cache.delete(x, level: :all)

        assert @cache.keys() == :lists.usort(expected -- del)
      end

      test "reduce" do
        l1 = for x <- 1..5, do: @l1.set(x, x)
        l2 = for x <- 3..7, do: @l2.set(x, x)
        l3 = for x <- 6..10, do: @l3.set(x, x)
        expected = :maps.from_list(for x <- 1..10, do: {x, x})

        assert @cache.reduce({%{}, 0}, fn({key, value}, {acc1, acc2}) ->
          if Map.has_key?(acc1, key),
            do: {acc1, acc2},
            else: {Map.put(acc1, key, value), value + acc2}
        end) == {expected, 55}
      end

      test "to_map" do
        l1 = for x <- 1..30, do: @l1.set(x, x)
        l2 = for x <- 20..60, do: @l2.set(x, x)
        l3 = for x <- 50..100, do: @l3.set(x, x)
        expected = :maps.from_list(for x <- 1..100, do: {x, x})

        assert @cache.to_map() == expected
        assert @cache.to_map(return: :value) == expected
        %Object{key: 1} = Map.get(@cache.to_map(return: :object), 1)
      end

      test "pop" do
        assert @cache.set(1, 1) == 1
        assert @cache.set(2, 2, level: 2) == 2
        assert @cache.set(3, 3, level: :all) == 3

        assert @cache.pop(1) == 1
        assert @cache.pop(2) == 2
        assert @cache.pop(3) == 3
        refute @l1.get(1)
        refute @l2.get(2)
        refute @l1.get(3)
        assert @l2.get(3)
        assert @l3.get(3)

        assert @cache.pop(3) == 3
        refute @l1.get(3)
        refute @l2.get(3)
        assert @l3.get(3)

        assert @cache.pop(3) == 3
        refute @l1.get(3)
        refute @l2.get(3)
        refute @l3.get(3)

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

      test "get_and_update" do
        assert @cache.set(1, 1) == 1
        assert @cache.set(2, 2, level: :all) == 2

        assert @cache.get_and_update(1, &({&1, &1 * 2})) == {1, 2}
        assert @l1.get(1) == 2
        refute @l2.get(1)
        refute @l3.get(1)

        assert @cache.get_and_update(2, &({&1, &1 * 2}), level: :all) == {2, 4}
        assert @l1.get(2) == 4
        assert @l2.get(2) == 4
        assert @l3.get(2) == 4

        assert @cache.get_and_update(1, fn _ -> :pop end) == {2, nil}
        refute @l1.get(1)

        assert @cache.get_and_update(2, fn _ -> :pop end, level: :all) == {4, nil}
        refute @l1.get(2)
        refute @l2.get(2)
        refute @l3.get(2)
      end

      test "update" do
        assert @cache.set(1, 1) == 1
        assert @cache.set(2, 2, level: :all) == 2

        assert @cache.update(1, 1, &(&1 * 2)) == 2
        assert @l1.get(1) == 2
        refute @l2.get(1)
        refute @l3.get(1)

        assert @cache.update(2, 1, &(&1 * 2), level: :all) == 4
        assert @l1.get(2) == 4
        assert @l2.get(2) == 4
        assert @l3.get(2) == 4
      end

      test "update_counter" do
        assert @cache.update_counter(1) == 1
        assert @l1.get(1) == 1
        refute @l2.get(1)
        refute @l3.get(1)

        assert @cache.update_counter(2, 2, level: 2) == 2
        assert @l2.get(2) == 2
        refute @l1.get(2)
        refute @l3.get(2)

        assert @cache.update_counter(3, 3, level: :all) == 3
        assert @l1.get(3) == 3
        assert @l2.get(3) == 3
        assert @l3.get(3) == 3

        assert @cache.update_counter(4, 5, level: :all) == 5
        assert @cache.update_counter(4, -5, level: :all) == 0
        assert @l1.get(4) == 0
        assert @l2.get(4) == 0
        assert @l3.get(4) == 0
      end

      test "transaction" do
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
        refute @cache.in_transaction?

        @cache.transaction fn ->
          _ = @cache.set(1, 11, return: :key)
          true = @cache.in_transaction?
        end
      end

      test "get with fallback" do
        assert_for_all_levels(nil, 1)
        assert @cache.get(1, fallback: fn(key) -> key * 2 end) == 2
        assert_for_all_levels(2, 1)
      end

      ## Helpers

      defp start_levels do
        for l <- @levels do
          {:ok, pid} = l.start_link()
          {l, pid}
        end
      end

      defp stop_levels(levels_and_pids) do
        for {level, pid} <- levels_and_pids do
          _ = :timer.sleep(10)
          if Process.alive?(pid), do: level.stop(pid, 1)
        end
      end

      defp assert_for_all_levels(expected, key) do
        Enum.each(@levels, fn(cache) ->
          case @cache.__model__ do
            :inclusive -> ^expected = cache.get(key)
            :exclusive -> nil = cache.get(key)
          end
        end)
      end
    end
  end
end
