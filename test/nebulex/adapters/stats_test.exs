defmodule Nebulex.Adapters.StatsTest do
  use ExUnit.Case

  import Mock
  import Nebulex.CacheCase

  alias Nebulex.Cache.Stats

  ## Shared cache

  defmodule Cache do
    use Nebulex.Cache,
      otp_app: :nebulex,
      adapter: Nebulex.Adapters.Multilevel

    defmodule L1 do
      use Nebulex.Cache,
        otp_app: :nebulex,
        adapter: Nebulex.Adapters.Local
    end

    defmodule L2 do
      use Nebulex.Cache,
        otp_app: :nebulex,
        adapter: Nebulex.Adapters.Replicated
    end

    defmodule L3 do
      use Nebulex.Cache,
        otp_app: :nebulex,
        adapter: Nebulex.Adapters.Partitioned
    end

    defmodule L4 do
      use Nebulex.Cache,
        otp_app: :nebulex,
        adapter: Nebulex.Adapters.Local
    end
  end

  ## Shared constants

  @config [
    model: :inclusive,
    levels: [
      {Cache.L1, gc_interval: :timer.hours(1), backend: :shards},
      {Cache.L2, primary: [gc_interval: :timer.hours(1)]},
      {Cache.L3, primary: [gc_interval: :timer.hours(1)]}
    ]
  ]

  @event [:nebulex, :adapters, :stats_test, :cache, :stats]

  ## Tests

  describe "(multilevel) stats/0" do
    alias Cache.L1

    setup_with_cache(Cache, [stats: true] ++ @config)

    test_with_mock "returns an error", L1.__adapter__(), [:passthrough],
      stats: fn _ -> {:error, %Nebulex.Error{reason: :error}} end do
      assert Cache.stats() == {:error, %Nebulex.Error{module: Nebulex.Error, reason: :error}}
    end

    test "hits and misses" do
      :ok = Cache.put_all!(a: 1, b: 2)

      assert Cache.get!(:a) == 1
      assert Cache.exists?(:a)
      assert Cache.ttl!(:b) == :infinity
      refute Cache.get!(:c)
      refute Cache.get!(:d)

      assert Cache.get_all!([:a, :b, :c, :d]) == %{a: 1, b: 2}

      assert_stats_measurements(Cache,
        l1: [hits: 5, misses: 4, writes: 2],
        l2: [hits: 0, misses: 4, writes: 2],
        l3: [hits: 0, misses: 4, writes: 2]
      )
    end

    test "writes and updates" do
      assert Cache.put_all!(a: 1, b: 2) == :ok
      refute Cache.put_new_all!(a: 1, b: 2)
      assert Cache.put_new_all!(c: 3, d: 4, e: 3)
      assert Cache.put!(1, 1) == :ok
      refute Cache.put_new!(1, 2)
      refute Cache.replace!(2, 2)
      assert Cache.put_new!(2, 2)
      assert Cache.replace!(2, 22)
      assert Cache.incr!(:counter) == 1
      assert Cache.incr!(:counter) == 2
      refute Cache.expire!(:f, 1000)
      assert Cache.expire!(:a, 1000)
      refute Cache.touch!(:f)
      assert Cache.touch!(:b)

      :ok = Process.sleep(1100)
      refute Cache.get!(:a)

      wait_until(fn ->
        assert_stats_measurements(Cache,
          l1: [expirations: 1, misses: 1, writes: 8, updates: 4],
          l2: [expirations: 1, misses: 1, writes: 8, updates: 4],
          l3: [expirations: 1, misses: 1, writes: 8, updates: 4]
        )
      end)
    end

    test "evictions" do
      entries = for x <- 1..10, do: {x, x}
      :ok = Cache.put_all!(entries)

      assert Cache.delete!(1) == :ok
      assert Cache.take!(2) == 2

      assert_raise Nebulex.KeyError, fn ->
        Cache.take!(20)
      end

      assert_stats_measurements(Cache,
        l1: [evictions: 2, misses: 1, writes: 10],
        l2: [evictions: 2, misses: 1, writes: 10],
        l3: [evictions: 2, misses: 1, writes: 10]
      )

      assert Cache.delete_all!() == 24

      assert_stats_measurements(Cache,
        l1: [evictions: 10, misses: 1, writes: 10],
        l2: [evictions: 10, misses: 1, writes: 10],
        l3: [evictions: 10, misses: 1, writes: 10]
      )
    end

    test "expirations" do
      :ok = Cache.put_all!(a: 1, b: 2)
      :ok = Cache.put_all!([c: 3, d: 4], ttl: 1000)

      assert Cache.get_all!([:a, :b, :c, :d]) == %{a: 1, b: 2, c: 3, d: 4}

      :ok = Process.sleep(1100)
      assert Cache.get_all!([:a, :b, :c, :d]) == %{a: 1, b: 2}

      wait_until(fn ->
        assert_stats_measurements(Cache,
          l1: [evictions: 2, expirations: 2, hits: 6, misses: 2, writes: 4],
          l2: [evictions: 2, expirations: 2, hits: 0, misses: 2, writes: 4],
          l3: [evictions: 2, expirations: 2, hits: 0, misses: 2, writes: 4]
        )
      end)
    end
  end

  describe "(replicated) stats/0" do
    alias Cache.L2, as: Replicated

    setup_with_cache(Replicated, [stats: true] ++ @config)

    test "hits and misses" do
      :ok = Replicated.put_all!(a: 1, b: 2)

      assert Replicated.get!(:a) == 1
      assert Replicated.get_all!([:a, :b, :c, :d]) == %{a: 1, b: 2}

      assert %Nebulex.Stats{measurements: measurements} = Replicated.stats!()
      assert measurements.hits == 3
      assert measurements.misses == 2
    end
  end

  describe "(partitioned) stats/0" do
    alias Cache.L3, as: Partitioned

    setup_with_cache(Partitioned, [stats: true] ++ @config)

    test "hits and misses" do
      :ok = Partitioned.put_all!(a: 1, b: 2)

      assert Partitioned.get!(:a) == 1
      assert Partitioned.get_all!([:a, :b, :c, :d]) == %{a: 1, b: 2}

      assert %Nebulex.Stats{measurements: measurements} = Partitioned.stats!()
      assert measurements.hits == 3
      assert measurements.misses == 2
    end
  end

  describe "disabled stats in a cache level" do
    setup_with_cache(
      Cache,
      [stats: true] ++
        Keyword.update!(
          @config,
          :levels,
          &(&1 ++ [{Cache.L4, gc_interval: :timer.hours(1), stats: false}])
        )
    )

    test "ignored when returning stats" do
      measurements = Cache.stats!().measurements
      assert Map.get(measurements, :l1)
      assert Map.get(measurements, :l2)
      assert Map.get(measurements, :l3)
      refute Map.get(measurements, :l4)
    end
  end

  describe "cache init error" do
    test "because invalid stats option" do
      _ = Process.flag(:trap_exit, true)

      {:error, {%ArgumentError{message: msg}, _}} =
        Cache.start_link(stats: 123, levels: [{Cache.L1, []}])

      assert msg == "expected stats: to be boolean, got: 123"
    end

    test "L1: invalid stats option" do
      _ = Process.flag(:trap_exit, true)

      {:error, {:shutdown, {_, _, {:shutdown, {_, Cache.L1, {error, _}}}}}} =
        Cache.start_link(stats: true, levels: [{Cache.L1, [stats: 123]}])

      assert error == %ArgumentError{message: "expected stats: to be boolean, got: 123"}
    end

    test "L2: invalid stats option" do
      _ = Process.flag(:trap_exit, true)

      {:error, {:shutdown, {_, _, {:shutdown, {_, Cache.L2, {error, _}}}}}} =
        Cache.start_link(stats: true, levels: [{Cache.L1, []}, {Cache.L2, [stats: 123]}])

      assert error == %ArgumentError{message: "expected stats: to be boolean, got: 123"}
    end

    test "L3: invalid stats option" do
      _ = Process.flag(:trap_exit, true)

      {:error, {:shutdown, {_, _, {:shutdown, {_, Cache.L3, {error, _}}}}}} =
        Cache.start_link(
          stats: true,
          levels: [{Cache.L1, []}, {Cache.L2, []}, {Cache.L3, [stats: 123]}]
        )

      assert error == %ArgumentError{message: "expected stats: to be boolean, got: 123"}
    end
  end

  describe "new generation" do
    alias Cache.L1
    alias Cache.L2.Primary, as: L2Primary
    alias Cache.L3.Primary, as: L3Primary

    setup_with_cache(Cache, [stats: true] ++ @config)

    test "updates evictions" do
      :ok = Cache.put_all!(a: 1, b: 2, c: 3)
      assert Cache.count_all!() == 9

      assert_stats_measurements(Cache,
        l1: [evictions: 0, writes: 3],
        l2: [evictions: 0, writes: 3],
        l3: [evictions: 0, writes: 3]
      )

      _ = L1.new_generation()
      assert Cache.count_all!() == 9

      assert_stats_measurements(Cache,
        l1: [evictions: 0, writes: 3],
        l2: [evictions: 0, writes: 3],
        l3: [evictions: 0, writes: 3]
      )

      _ = L1.new_generation()
      assert Cache.count_all!() == 6

      assert_stats_measurements(Cache,
        l1: [evictions: 3, writes: 3],
        l2: [evictions: 0, writes: 3],
        l3: [evictions: 0, writes: 3]
      )

      _ = L2Primary.new_generation()
      _ = L2Primary.new_generation()
      assert Cache.count_all!() == 3

      assert_stats_measurements(Cache,
        l1: [evictions: 3, writes: 3],
        l2: [evictions: 3, writes: 3],
        l3: [evictions: 0, writes: 3]
      )

      _ = L3Primary.new_generation()
      _ = L3Primary.new_generation()
      assert Cache.count_all!() == 0

      assert_stats_measurements(Cache,
        l1: [evictions: 3, writes: 3],
        l2: [evictions: 3, writes: 3],
        l3: [evictions: 3, writes: 3]
      )
    end
  end

  describe "disabled stats:" do
    setup_with_cache(Cache, @config)

    test "stats/0 returns nil" do
      assert_raise Nebulex.Error, ~r"stats disabled or not supported by the cache", fn ->
        Cache.stats!()
      end
    end

    test "dispatch_stats/1 is skipped" do
      with_telemetry_handler(__MODULE__, [@event], fn ->
        assert {:error, %Nebulex.Error{reason: {:stats_error, _}}} = Cache.dispatch_stats()
      end)
    end
  end

  describe "dispatch_stats/1" do
    setup_with_cache(Cache, [stats: true] ++ @config)

    test "emits a telemetry event when called" do
      with_telemetry_handler(__MODULE__, [@event], fn ->
        :ok = Cache.dispatch_stats(metadata: %{node: node()})
        node = node()

        assert_receive {@event, measurements,
                        %{cache: Nebulex.Adapters.StatsTest.Cache, node: ^node}}

        assert measurements == %{
                 l1: %{hits: 0, misses: 0, writes: 0, evictions: 0, expirations: 0, updates: 0},
                 l2: %{hits: 0, misses: 0, writes: 0, evictions: 0, expirations: 0, updates: 0},
                 l3: %{hits: 0, misses: 0, writes: 0, evictions: 0, expirations: 0, updates: 0}
               }
      end)
    end

    test_with_mock "returns an error", Cache.__adapter__(), [:passthrough],
      stats: fn _ -> {:error, %Nebulex.Error{reason: :error}} end do
      assert Cache.dispatch_stats() ==
               {:error, %Nebulex.Error{module: Nebulex.Error, reason: :error}}
    end
  end

  describe "dispatch_stats/1 with dynamic cache" do
    setup_with_dynamic_cache(
      Cache,
      :stats_with_dispatch,
      [telemetry_prefix: [:my_event], stats: true] ++ @config
    )

    test "emits a telemetry event with custom telemetry_prefix when called" do
      with_telemetry_handler(__MODULE__, [[:my_event, :stats]], fn ->
        :ok = Cache.dispatch_stats(metadata: %{foo: :bar})

        assert_receive {[:my_event, :stats], measurements,
                        %{cache: :stats_with_dispatch, foo: :bar}}

        assert measurements == %{
                 l1: %{hits: 0, misses: 0, writes: 0, evictions: 0, expirations: 0, updates: 0},
                 l2: %{hits: 0, misses: 0, writes: 0, evictions: 0, expirations: 0, updates: 0},
                 l3: %{hits: 0, misses: 0, writes: 0, evictions: 0, expirations: 0, updates: 0}
               }
      end)
    end
  end

  ## Helpers

  defp assert_stats_measurements(cache, levels) do
    measurements = cache.stats!().measurements

    for {level, stats} <- levels, {stat, expected} <- stats do
      assert get_in(measurements, [level, stat]) == expected
    end
  end
end
