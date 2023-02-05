defmodule Nebulex.StatsTest do
  use ExUnit.Case, asyc: true
  use Mimic

  import Nebulex.CacheCase

  alias Nebulex.TestCache.StatsCache, as: Cache

  ## Shared constants

  @event [:nebulex, :test_cache, :stats_cache, :stats]

  ## Tests

  describe "stats/0" do
    setup_with_cache Cache, stats: true

    test "returns an error" do
      Nebulex.Cache.Registry
      |> expect(:lookup, fn _ -> {:ok, %{adapter: Nebulex.FakeAdapter}} end)

      assert Cache.stats() == {:error, %Nebulex.Error{module: Nebulex.Error, reason: :error}}
    end

    test "hits and misses" do
      :ok = Cache.put_all!(a: 1, b: 2)

      assert Cache.get!(:a) == 1
      assert Cache.has_key?(:a)
      assert Cache.ttl!(:b) == :infinity
      refute Cache.get!(:c)
      refute Cache.get!(:d)

      assert Cache.get_all!([:a, :b, :c, :d]) == %{a: 1, b: 2}

      assert Cache.stats!().measurements == %{
               hits: 5,
               misses: 4,
               writes: 2,
               evictions: 0,
               expirations: 0,
               updates: 0
             }
    end

    test "writes and updates" do
      assert Cache.put_all!(a: 1, b: 2) == :ok
      assert Cache.put_all(%{a: 1, b: 2}) == :ok
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
        assert Cache.stats!().measurements == %{
                 hits: 0,
                 misses: 1,
                 writes: 10,
                 evictions: 1,
                 expirations: 1,
                 updates: 4
               }
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

      assert Cache.stats!().measurements == %{
               hits: 1,
               misses: 1,
               writes: 10,
               evictions: 2,
               expirations: 0,
               updates: 0
             }

      assert Cache.delete_all!() == 8

      assert Cache.stats!().measurements == %{
               hits: 1,
               misses: 1,
               writes: 10,
               evictions: 10,
               expirations: 0,
               updates: 0
             }
    end

    test "expirations" do
      :ok = Cache.put_all!(a: 1, b: 2)
      :ok = Cache.put_all!([c: 3, d: 4], ttl: 1000)

      assert Cache.get_all!([:a, :b, :c, :d]) == %{a: 1, b: 2, c: 3, d: 4}

      :ok = Process.sleep(1100)
      assert Cache.get_all!([:a, :b, :c, :d]) == %{a: 1, b: 2}

      wait_until(fn ->
        assert Cache.stats!().measurements == %{
                 hits: 6,
                 misses: 2,
                 writes: 4,
                 evictions: 2,
                 expirations: 2,
                 updates: 0
               }
      end)
    end
  end

  describe "cache init error" do
    test "because invalid stats option" do
      _ = Process.flag(:trap_exit, true)

      {:error, {%ArgumentError{message: msg}, _}} = Cache.start_link(stats: 123)

      assert Regex.match?(~r/invalid value/, msg)
    end
  end

  describe "disabled stats:" do
    setup_with_cache Cache, stats: false

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
    setup_with_cache Cache, stats: true

    test "emits a telemetry event when called" do
      with_telemetry_handler(__MODULE__, [@event], fn ->
        :ok = Cache.dispatch_stats(metadata: %{node: node()})

        node = node()

        assert_receive {@event, measurements, %{cache: Cache, node: ^node}}

        assert measurements == %{
                 hits: 0,
                 misses: 0,
                 writes: 0,
                 evictions: 0,
                 expirations: 0,
                 updates: 0
               }
      end)
    end

    test "returns an error" do
      Nebulex.Cache.Registry
      |> expect(:lookup, fn _ -> {:ok, %{adapter: Nebulex.FakeAdapter}} end)

      assert Cache.dispatch_stats() ==
               {:error, %Nebulex.Error{module: Nebulex.Error, reason: :error}}
    end
  end

  describe "dispatch_stats/1 with dynamic cache" do
    setup_with_dynamic_cache Cache,
                             :stats_with_dispatch,
                             telemetry_prefix: [:my_event],
                             stats: true

    test "emits a telemetry event with custom telemetry_prefix when called" do
      with_telemetry_handler(__MODULE__, [[:my_event, :stats]], fn ->
        :ok = Cache.dispatch_stats(metadata: %{foo: :bar})

        assert_receive {[:my_event, :stats], measurements,
                        %{cache: :stats_with_dispatch, foo: :bar}}

        assert measurements == %{
                 hits: 0,
                 misses: 0,
                 writes: 0,
                 evictions: 0,
                 expirations: 0,
                 updates: 0
               }
      end)
    end
  end
end
