defmodule Nebulex.Cache.StatsTest do
  use ExUnit.Case, async: true

  import Nebulex.TestCase
  import Mock

  alias Nebulex.Cache.Stats
  alias Nebulex.Time

  defmodule Cache do
    use Nebulex.Cache,
      otp_app: :nebulex,
      adapter: Nebulex.Adapters.Multilevel
  end

  @config [
    model: :inclusive,
    levels: [
      l1: [
        gc_interval: Time.expiry_time(1, :hour),
        backend: :shards
      ],
      l2: [
        adapter: Nebulex.Adapters.Partitioned,
        primary: [
          gc_interval: Time.expiry_time(1, :hour)
        ]
      ]
    ]
  ]

  describe "enabled stats" do
    setup do
      {:ok, pid} = Cache.start_link([stats: true] ++ @config)
      :ok

      on_exit(fn ->
        :ok = Process.sleep(20)
        if Process.alive?(pid), do: Cache.stop()
      end)
    end

    test "hits and misses" do
      :ok = Cache.put_all(a: 1, b: 2)

      assert Cache.get(:a) == 1
      assert Cache.has_key?(:a)
      assert Cache.ttl(:b) == :infinity
      refute Cache.get(:c)
      refute Cache.get(:d)

      assert stats = Cache.stats_info()
      assert stats.writes == 4
      assert stats.hits == 3
      assert stats.misses == 4
    end

    test "writes" do
      assert Cache.put_all(a: 1, b: 2) == :ok
      refute Cache.put_new_all(a: 1, b: 2)
      assert Cache.put_new_all(c: 3, d: 4, e: 3)
      assert Cache.put(1, 1) == :ok
      refute Cache.put_new(1, 2)
      refute Cache.replace(2, 2)
      assert Cache.put_new(2, 2)
      assert Cache.replace(2, 22)
      assert Cache.incr(:counter) == 1
      refute Cache.expire(:f, 1000)
      assert Cache.expire(:a, 1000)
      refute Cache.touch(:f)
      assert Cache.touch(:b)

      :ok = Process.sleep(1100)
      refute Cache.get(:a)

      assert stats = Cache.stats_info()
      assert stats.writes == 22
      assert stats.misses == 2
      assert stats.expirations == 2
    end

    test "evictions" do
      entries = for x <- 1..10, do: {x, x}
      :ok = Cache.put_all(entries)

      assert Cache.delete(1) == :ok
      assert Cache.take(2) == 2
      refute Cache.take(20)

      assert stats = Cache.stats_info()
      assert stats.writes == 20
      assert stats.misses == 2
      assert stats.evictions == 4

      assert Cache.flush() == 16

      assert stats = Cache.stats_info()
      assert stats.evictions == 20
    end

    test "expirations" do
      :ok = Cache.put_all(a: 1, b: 2)
      :ok = Cache.put_all([c: 3, d: 4], ttl: 1000)

      assert Cache.get_all([:a, :b, :c, :d]) == %{a: 1, b: 2, c: 3, d: 4}

      :ok = Process.sleep(1100)
      assert Cache.get_all([:a, :b, :c, :d]) == %{a: 1, b: 2}

      assert stats = Cache.stats_info()
      assert stats.writes == 8
      assert stats.hits == 6
      assert stats.misses == 4
      assert stats.evictions == 4
      assert stats.expirations == 4
    end
  end

  describe "disabled stats" do
    setup do
      {:ok, pid} = Cache.start_link(@config)
      :ok

      on_exit(fn ->
        :ok = Process.sleep(20)
        if Process.alive?(pid), do: Cache.stop()
      end)
    end

    test "stat_counter is nil" do
      refute Cache.stats_info()
    end

    test "dispatch_stats is skipped" do
      with_mock :telemetry, [], execute: fn _, _, _ -> :ok end do
        :ok = Cache.dispatch_stats()

        refute called(
                 :telemetry.execute(
                   [:nebulex, :cache, :stats_test, :cache],
                   %{
                     hits: 0,
                     misses: 0,
                     writes: 0,
                     evictions: 0,
                     expirations: 0
                   },
                   %{cache: Nebulex.Cache.StatsTest.Cache}
                 )
               )
      end
    end
  end

  describe "dispatch_stats" do
    setup do
      {:ok, pid} = Cache.start_link([stats: true] ++ @config)
      :ok

      on_exit(fn ->
        :ok = Process.sleep(20)
        if Process.alive?(pid), do: Cache.stop()
      end)
    end

    test "emits a telemetry event when called" do
      with_mock :telemetry, [], execute: fn _, _, _ -> :ok end do
        :ok = Cache.dispatch_stats()

        assert called(
                 :telemetry.execute(
                   [:nebulex, :cache, :stats_test, :cache, :stats],
                   %{hits: 0, misses: 0, writes: 0, evictions: 0, expirations: 0},
                   %{cache: Nebulex.Cache.StatsTest.Cache}
                 )
               )
      end
    end
  end

  describe "dispatch_stats with dynamic cache" do
    setup_with_dynamic_cache(Cache, :stats_with_dispatch, [stats: true] ++ @config)

    test "emits a telemetry event when called" do
      with_mock :telemetry, [], execute: fn _, _, _ -> :ok end do
        :ok = Cache.dispatch_stats(telemetry_prefix: [:my_event], metadata: %{tag: "tag1"})

        assert called(
                 :telemetry.execute(
                   [:my_event, :stats],
                   %{hits: 0, misses: 0, writes: 0, evictions: 0, expirations: 0},
                   %{cache: :stats_with_dispatch, tag: "tag1"}
                 )
               )
      end
    end
  end
end
