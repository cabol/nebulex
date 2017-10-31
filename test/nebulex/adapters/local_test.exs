defmodule Nebulex.Adapters.LocalTest do
  use ExUnit.Case, async: true
  use Nebulex.CacheTest, cache: Nebulex.TestCache.Local

  alias Nebulex.Object
  alias Nebulex.TestCache.Local, as: TestCache

  setup do
    {:ok, pid} = TestCache.start_link(n_generations: 2)
    :ok

    on_exit fn ->
      _ = :timer.sleep(10)
      if Process.alive?(pid), do: TestCache.stop(pid, 1)
    end
  end

  test "fail with ArgumentError because cache was stopped" do
    :ok =
      TestCache
      |> Process.whereis
      |> TestCache.stop(1)

    assert_raise ArgumentError, fn -> TestCache.set 1, 13, return: :object end
    assert_raise ArgumentError, fn -> TestCache.get 1 end
    assert_raise ArgumentError, fn -> TestCache.delete 1 end
  end

  test "get_and_update" do
    TestCache.new_generation()

    assert {nil, 1} == TestCache.get_and_update(1, fn v ->
      if v, do: {v, v * 2}, else: {v, 1}
    end)

    assert TestCache.get_and_update(1, &({&1, &1 * 2})) == {1, 2}
    assert TestCache.get_and_update(1, &({&1, &1 * 3}), return: :object) == {2, 6}
    assert TestCache.get_and_update(1, &({&1, nil})) == {6, nil}
    assert TestCache.get(1) == 6
    assert TestCache.get_and_update(1, fn _ -> :pop end) == {6, nil}
    assert TestCache.get_and_update(3, &({&1, 3})) == {nil, 3}

    assert {nil, :error} == TestCache.get_and_update(:a, fn v ->
      if v, do: {v, :ok}, else: {v, :error}
    end, version: -1, on_conflict: nil)

    assert {:error, :ok} == TestCache.get_and_update(:a, fn v ->
      if v, do: {v, :ok}, else: {v, :error}
    end, version: -1, on_conflict: :nothing)

    assert_raise ArgumentError, fn ->
      TestCache.get_and_update(1, fn _ -> :other end)
    end

    assert_raise Nebulex.VersionConflictError, fn ->
      1
      |> TestCache.set(1, return: :key)
      |> TestCache.get_and_update(&({&1, -1}), version: -1)
    end
  end

  test "update" do
    TestCache.new_generation()

    for x <- 1..2, do: TestCache.set x, x

    assert TestCache.update(1, 1, &(&1 * 2)) == 2
    assert TestCache.update(2, 1, &(&1 * 2)) == 4
    assert TestCache.update(3, 1, &(&1 * 2)) == 1
    assert TestCache.update(4, nil, &(&1 * 2)) == nil
    refute TestCache.get(4)

    assert TestCache.update(3, 3, &(&1 * 2), version: -1, on_conflict: :nothing) == 2
    assert TestCache.update(3, 3, &(&1 * 2), version: -1, on_conflict: nil) == 3

    assert_raise Nebulex.VersionConflictError, fn ->
      :a
      |> TestCache.set(1, return: :key)
      |> TestCache.update(0, &(&1 * 2), version: -1)
    end
  end

  test "incr with update" do
    TestCache.new_generation()

    assert TestCache.update_counter(:counter) == 1
    assert TestCache.update_counter(:counter) == 2

    assert TestCache.get_and_update(:counter, &({&1, &1 * 2})) == {2, 4}
    assert TestCache.update_counter(:counter) == 5

    assert TestCache.update(:counter, 1, &(&1 * 2)) == 10
    assert TestCache.update_counter(:counter, -10) == 0

    TestCache.set("foo", "bar")
    assert_raise ArgumentError, fn ->
      TestCache.update_counter("foo")
    end
  end

  test "push generations" do
    # create 1st generation
    TestCache.new_generation()

    # should be empty
    refute TestCache.get(1)

    # set some entries
    for x <- 1..2, do: TestCache.set x, x

    # fetch one entry from new generation
    assert TestCache.get(1) == 1

    # fetch non-existent entries
    refute TestCache.get(3)
    refute TestCache.get(:non_existent)

    # create a new generation
    TestCache.new_generation()

    # both entries should be in the old generation
    refute get_from_new(1)
    refute get_from_new(2)
    assert (get_from_old(1)).value == 1
    assert (get_from_old(2)).value == 2

    # fetch entry 1 to set it into the new generation
    assert TestCache.get(1) == 1
    assert (get_from_new(1)).value == 1
    refute get_from_new(2)
    refute get_from_old(1)
    assert (get_from_old(2)).value == 2

    # create a new generation, the old generation should be deleted
    TestCache.new_generation()

    # entry 1 should be into the old generation and entry 2 deleted
    refute get_from_new(1)
    refute get_from_new(2)
    assert (get_from_old(1)).value == 1
    refute get_from_old(2)
  end

  ## Helpers

  defp get_from_new(key) do
    TestCache.__metadata__.generations
    |> hd
    |> get_from(key)
  end

  defp get_from_old(key) do
    TestCache.__metadata__.generations
    |> List.last
    |> get_from(key)
  end

  defp get_from(gen, key) do
    case ExShards.Local.lookup(gen, key, TestCache.__state__) do
      [] ->
        nil
      [{^key, val, vsn, ttl}] ->
        %Object{key: key, value: val, version: vsn, ttl: ttl}
    end
  end
end
