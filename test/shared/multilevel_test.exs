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
        levels_and_pids = start_levels()
        :ok

        on_exit fn ->
          stop_levels(levels_and_pids)
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

      test "all" do
        expected = for x <- 1..100, do: @cache.set(x, x, return: :key)

        assert @cache.all == expected
        assert @cache.all(return: :value) == expected
        [%Object{} | _] = @cache.all(return: :object)
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

      test "transaction" do
        refute @cache.transaction 1, fn ->
          @cache.set(1, 11, return: :key)
          |> @cache.get!(return: :key)
          |> @cache.delete(return: :key)
          |> @cache.get
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
