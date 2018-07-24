defmodule Nebulex.Cache.StatsTest do
  use ExUnit.Case, async: true

  alias Nebulex.Cache.Stats
  alias Nebulex.TestCache.CacheStats

  setup do
    {:ok, pid} = CacheStats.start_link(n_generations: 2)
    :ok

    on_exit(fn ->
      _ = :timer.sleep(10)
      if Process.alive?(pid), do: CacheStats.stop(pid)
    end)
  end

  test "test counters" do
    CacheStats.new_generation()

    for x <- 1..5, do: CacheStats.set(x, x)
    assert 5 == Stats.get_counter(CacheStats, :set)

    for x <- 1..5, do: assert(CacheStats.get(x) == x)
    assert 5 == Stats.get_counter(CacheStats, :get)
    for x <- 6..9, do: refute(CacheStats.get(x))
    assert 4 == Stats.get_counter(CacheStats, :get_miss_count)
    assert 5 == Stats.get_counter(CacheStats, :get)

    assert 1 == CacheStats.delete(1, return: :key)
    assert 1 == Stats.get_counter(CacheStats, :delete)

    counters = Stats.get_counters(CacheStats)
    assert 5 == Keyword.get(counters, :get)
    assert 4 == Keyword.get(counters, :get_miss_count)
    assert 5 == Keyword.get(counters, :set)
    assert 1 == Keyword.get(counters, :delete)

    assert true == Stats.reset_counter(CacheStats, :get)
    assert 0 == Stats.get_counter(CacheStats, :get)

    assert :ok == Stats.reset_counters(CacheStats)
    assert 0 == Stats.get_counter(CacheStats, :get)
    assert 0 == Stats.get_counter(CacheStats, :get_miss_count)
    assert 0 == Stats.get_counter(CacheStats, :set)
    assert 0 == Stats.get_counter(CacheStats, :delete)
  end
end
