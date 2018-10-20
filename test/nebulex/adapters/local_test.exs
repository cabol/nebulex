defmodule Nebulex.Adapters.LocalTest do
  use ExUnit.Case, async: true
  use Nebulex.CacheTest, cache: Nebulex.TestCache.Local

  import Ex2ms

  alias Nebulex.Object
  alias Nebulex.TestCache.Local, as: TestCache
  alias Nebulex.TestCache.Versionless

  setup do
    {:ok, pid} = TestCache.start_link(n_generations: 2)
    :ok

    on_exit(fn ->
      _ = :timer.sleep(10)
      if Process.alive?(pid), do: TestCache.stop(pid)
    end)
  end

  test "fail with ArgumentError because cache was stopped" do
    :ok =
      TestCache
      |> Process.whereis()
      |> TestCache.stop()

    assert_raise ArgumentError, fn -> TestCache.set(1, 13, return: :object) end
    assert_raise ArgumentError, fn -> TestCache.get(1) end
    assert_raise ArgumentError, fn -> TestCache.delete(1) end
  end

  test "set without version generator" do
    {:ok, pid} = Versionless.start_link()

    %Object{key: 1, value: 1, version: nil} = Versionless.set(1, 1, return: :object)
    %Object{key: 1, value: 2, version: nil} = Versionless.set(1, 2, return: :object)

    :ok = Versionless.stop(pid)
  end

  test "get_and_update" do
    assert {nil, 1} ==
             TestCache.get_and_update(1, fn v ->
               if v, do: {v, v * 2}, else: {v, 1}
             end)

    assert {1, 2} == TestCache.get_and_update(1, &{&1, &1 * 2})

    {2, %Object{key: 1, value: 6, expire_at: _, version: _}} =
      TestCache.get_and_update(1, &{&1, &1 * 3}, return: :object)

    assert {6, nil} == TestCache.get_and_update(1, &{&1, nil})
    assert 6 == TestCache.get(1)
    assert {6, nil} == TestCache.get_and_update(1, fn _ -> :pop end)
    assert {nil, 3} == TestCache.get_and_update(3, &{&1, 3})

    fun = fn v ->
      if v, do: {v, :ok}, else: {v, :error}
    end

    assert {nil, :error} ==
             TestCache.get_and_update(
               :a,
               fun,
               version: -1,
               on_conflict: :override
             )

    assert {:error, :error} ==
             TestCache.get_and_update(
               :a,
               fun,
               version: -1,
               on_conflict: :nothing
             )

    assert_raise Nebulex.VersionConflictError, fn ->
      1
      |> TestCache.set(1, return: :key)
      |> TestCache.get_and_update(&{&1, -1}, version: -1)
    end

    assert_raise ArgumentError, fn ->
      TestCache.get_and_update(1, fn _ -> :other end)
    end
  end

  test "incr with update" do
    assert 1 == TestCache.update_counter(:counter)
    assert 2 == TestCache.update_counter(:counter)

    assert {2, 4} == TestCache.get_and_update(:counter, &{&1, &1 * 2})
    assert 5 == TestCache.update_counter(:counter)

    assert 10 == TestCache.update(:counter, 1, &(&1 * 2))
    assert 0 == TestCache.update_counter(:counter, -10)

    TestCache.set("foo", "bar")

    assert_raise ArgumentError, fn ->
      TestCache.update_counter("foo")
    end
  end

  test "set_many failure" do
    :ok =
      TestCache
      |> Process.whereis()
      |> TestCache.stop()

    assert {:error, ["apples"]} == TestCache.set_many(%{"apples" => 1})
  end

  test "update_counter with ttl" do
    assert 1 == TestCache.update_counter(:counter_with_ttl, 1, ttl: 1)
    assert 2 == TestCache.update_counter(:counter_with_ttl)
    assert 2 == TestCache.get(:counter_with_ttl)
    _ = :timer.sleep(1010)
    refute TestCache.get(:counter_with_ttl)

    assert 1 == TestCache.update_counter(:counter_with_ttl, 1, ttl: 5)
    assert 5 == TestCache.object_info(:counter_with_ttl, :ttl)

    assert 1 == :counter_with_ttl |> TestCache.expire(1) |> Object.remaining_ttl()
    _ = :timer.sleep(1010)
    refute TestCache.get(:counter_with_ttl)
  end

  test "update_counter over an existing object" do
    assert 0 == TestCache.set(:counter, 0)
    assert 1 == TestCache.update_counter(:counter)
    assert 3 == TestCache.update_counter(:counter, 2)
  end

  test "all and stream using match_spec queries" do
    values = for x <- 1..5, do: TestCache.set(x, x * 2)
    TestCache.new_generation()
    values = values ++ for x <- 6..10, do: TestCache.set(x, x * 2)

    assert values ==
             :all
             |> TestCache.stream(page_size: 3, return: :value)
             |> Enum.to_list()
             |> :lists.usort()

    {_, expected} = Enum.split(values, 5)

    test_ms =
      fun do
        {_, value, _, _} when value > 10 -> value
      end

    for action <- [:all, :stream] do
      assert expected == all_or_stream(action, test_ms, page_size: 3, return: :value)

      msg = ~r"invalid match spec"

      assert_raise Nebulex.QueryError, msg, fn ->
        all_or_stream(action, :invalid_query)
      end
    end
  end

  test "all and stream using expired and unexpired queries" do
    for action <- [:all, :stream] do
      expired = for x <- 1..5, do: TestCache.set(x, x * 2, ttl: 3)
      unexpired = for x <- 6..10, do: TestCache.set(x, x * 2)
      all = expired ++ unexpired

      opts = [page_size: 3, return: :value]

      assert all == all_or_stream(action, :all, opts)
      assert all == all_or_stream(action, :all_unexpired, opts)
      assert [] == all_or_stream(action, :all_expired, opts)

      :timer.sleep(3500)

      assert unexpired == all_or_stream(action, :all_unexpired, opts)
      assert expired == all_or_stream(action, :all_expired, opts)
    end
  end

  test "push generations" do
    # should be empty
    refute TestCache.get(1)

    # set some entries
    for x <- 1..2, do: TestCache.set(x, x)

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
    assert 1 == get_from_old(1).value
    assert 2 == get_from_old(2).value

    # fetch entry 1 to set it into the new generation
    assert 1 == TestCache.get(1)
    assert 1 == get_from_new(1).value
    refute get_from_new(2)
    refute get_from_old(1)
    assert 2 == get_from_old(2).value

    # create a new generation, the old generation should be deleted
    TestCache.new_generation()

    # entry 1 should be into the old generation and entry 2 deleted
    refute get_from_new(1)
    refute get_from_new(2)
    assert 1 == get_from_old(1).value
    refute get_from_old(2)
  end

  test "push generations with ttl" do
    assert 1 == TestCache.set(1, 1, ttl: 2)
    assert 1 == TestCache.get(1)

    TestCache.new_generation()

    refute get_from_new(1)
    assert 1 == get_from_old(1).value
    assert 1 == TestCache.get(1)

    :timer.sleep(2010)

    refute TestCache.get(1)
    refute get_from_new(1)
    refute get_from_old(1)
  end

  ## Helpers

  defp get_from_new(key) do
    TestCache.__metadata__().generations
    |> hd
    |> get_from(key)
  end

  defp get_from_old(key) do
    TestCache.__metadata__().generations
    |> List.last()
    |> get_from(key)
  end

  defp get_from(gen, key) do
    case :shards_local.lookup(gen, key, TestCache.__state__()) do
      [] ->
        nil

      [{^key, val, vsn, expire_at}] ->
        %Object{key: key, value: val, version: vsn, expire_at: expire_at}
    end
  end

  defp all_or_stream(action, ms, opts \\ []) do
    TestCache
    |> apply(action, [ms, opts])
    |> case do
      list when is_list(list) ->
        :lists.usort(list)

      stream ->
        stream
        |> Enum.to_list()
        |> :lists.usort()
    end
  end
end
