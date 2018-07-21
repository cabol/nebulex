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
      if Process.alive?(pid), do: TestCache.stop(pid)
    end
  end

  test "fail with ArgumentError because cache was stopped" do
    :ok =
      TestCache
      |> Process.whereis()
      |> TestCache.stop()

    assert_raise ArgumentError, fn -> TestCache.set 1, 13, return: :object end
    assert_raise ArgumentError, fn -> TestCache.get 1 end
    assert_raise ArgumentError, fn -> TestCache.delete 1 end
  end

  test "get_and_update" do
    assert {nil, 1} == TestCache.get_and_update(1, fn v ->
      if v, do: {v, v * 2}, else: {v, 1}
    end)

    assert {1, 2} == TestCache.get_and_update(1, &({&1, &1 * 2}))
    {2, %Object{key: 1, value: 6, ttl: _, version: _}} =
      TestCache.get_and_update(1, &({&1, &1 * 3}), return: :object)
    assert {6, nil} == TestCache.get_and_update(1, &({&1, nil}))
    assert 6 == TestCache.get(1)
    assert {6, nil} == TestCache.get_and_update(1, fn _ -> :pop end)
    assert {nil, 3} == TestCache.get_and_update(3, &({&1, 3}))

    assert {nil, :error} == TestCache.get_and_update(:a, fn v ->
      if v, do: {v, :ok}, else: {v, :error}
    end, version: -1, on_conflict: :override)

    assert {:error, :error} == TestCache.get_and_update(:a, fn v ->
      if v, do: {v, :ok}, else: {v, :error}
    end, version: -1, on_conflict: :nothing)

    assert_raise Nebulex.ConflictError, fn ->
      1
      |> TestCache.set(1, return: :key)
      |> TestCache.get_and_update(&({&1, -1}), version: -1)
    end

    assert_raise ArgumentError, fn ->
      TestCache.get_and_update(1, fn _ -> :other end)
    end
  end

  test "incr with update" do
    assert 1 == TestCache.update_counter(:counter)
    assert 2 == TestCache.update_counter(:counter)

    assert {2, 4} == TestCache.get_and_update(:counter, &({&1, &1 * 2}))
    assert 5 == TestCache.update_counter(:counter)

    assert 10 == TestCache.update(:counter, 1, &(&1 * 2))
    assert 0 == TestCache.update_counter(:counter, -10)

    TestCache.set("foo", "bar")
    assert_raise ArgumentError, fn ->
      TestCache.update_counter("foo")
    end
  end

  test "mset failure" do
    :ok =
      TestCache
      |> Process.whereis()
      |> TestCache.stop()

    assert {:error, ["apples"]} == @cache.mset(%{"apples" => 1})
  end

  test "push generations" do
    # should be empty
    refute TestCache.get(1)

    # set some entries
    for x <- 1..2, do: TestCache.set x, x

    # fetch one entry from new generation
    assert 1 == TestCache.get(1)

    # fetch non-existent entries
    refute TestCache.get(3)
    refute TestCache.get(:non_existent)

    # create a new generation
    TestCache.new_generation()

    # both entries should be in the old generation
    refute get_from_new(1)
    refute get_from_new(2)
    assert 1 == (get_from_old(1)).value
    assert 2 == (get_from_old(2)).value

    # fetch entry 1 to set it into the new generation
    assert 1 == TestCache.get(1)
    assert 1 == (get_from_new(1)).value
    refute get_from_new(2)
    refute get_from_old(1)
    assert 2 == (get_from_old(2)).value

    # create a new generation, the old generation should be deleted
    TestCache.new_generation()

    # entry 1 should be into the old generation and entry 2 deleted
    refute get_from_new(1)
    refute get_from_new(2)
    assert 1 == (get_from_old(1)).value
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
