defmodule Nebulex.Cache.StatsTest do
  use ExUnit.Case, async: true

  alias Nebulex.Cache.Stats
  alias Nebulex.TestCache.CacheStats

  setup do
    {:ok, pid} = CacheStats.start_link(n_generations: 2)
    :ok

    on_exit fn ->
      _ = :timer.sleep(10)
      if Process.alive?(pid), do: CacheStats.stop(pid, 1)
    end
  end

  test "test counters" do
    CacheStats.new_generation()

    for x <- 1..5, do: CacheStats.set x, x
    assert Stats.get_counter(CacheStats, :set) == 5

    for x <- 1..5, do: assert CacheStats.get(x) == x
    assert Stats.get_counter(CacheStats, :get) == 5
    for x <- 6..9, do: refute CacheStats.get(x)
    assert Stats.get_counter(CacheStats, :get_miss_count) == 4
    assert Stats.get_counter(CacheStats, :get) == 5

    assert CacheStats.delete(1) == 1
    assert Stats.get_counter(CacheStats, :delete) == 1

    counters = Stats.get_counters(CacheStats)
    assert Keyword.get(counters, :get) == 5
    assert Keyword.get(counters, :get_miss_count) == 4
    assert Keyword.get(counters, :set) == 5
    assert Keyword.get(counters, :delete) == 1

    assert Stats.reset_counter(CacheStats, :get) == true
    assert Stats.get_counter(CacheStats, :get) == 0

    assert Stats.reset_counters(CacheStats) == :ok
    assert Stats.get_counter(CacheStats, :get) == 0
    assert Stats.get_counter(CacheStats, :get_miss_count) == 0
    assert Stats.get_counter(CacheStats, :set) == 0
    assert Stats.get_counter(CacheStats, :delete) == 0
  end
end
