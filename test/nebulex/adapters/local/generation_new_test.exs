defmodule GenerationNewTest do
  use ExUnit.Case, async: true

  defmodule LocalWithSizeLimit do
    @moduledoc false
    use Nebulex.Cache,
      otp_app: :nebulex,
      adapter: Nebulex.Adapters.Local
  end

  import Nebulex.CacheCase

  alias GenerationNewTest.LocalWithSizeLimit
  alias Nebulex.Adapters.Local.Generation

  describe "generation_new init" do
    test "ok: with default options" do
      assert {:ok, _pid} = LocalWithSizeLimit.start_link()

      assert %Generation{
               allocated_memory: nil,
               backend: :ets,
               backend_opts: [
                 :set,
                 :public,
                 {:keypos, 2},
                 {:read_concurrency, true},
                 {:write_concurrency, true}
               ],
               gc_cleanup_max_timeout: 600_000,
               gc_cleanup_min_timeout: 10_000,
               gc_cleanup_ref: nil,
               gc_heartbeat_ref: nil,
               gc_interval: nil,
               max_size: nil,
               meta_tab: meta_tab,
               stats_counter: nil
             } = Generation.get_state(LocalWithSizeLimit)

      assert is_reference(meta_tab)

      :ok = LocalWithSizeLimit.stop()
    end

    test "ok:  with custom options" do
      assert {:ok, _pid} =
               LocalWithSizeLimit.start_link(
                 generation_cleanup_timeout: 3_000,
                 generation_max_size: 3,
                 generation_allocated_memory: 1000
               )

      assert %Generation{
               allocated_memory: 1000,
               backend: :ets,
               backend_opts: [
                 :set,
                 :public,
                 {:keypos, 2},
                 {:read_concurrency, true},
                 {:write_concurrency, true}
               ],
               gc_cleanup_max_timeout: 600_000,
               gc_cleanup_min_timeout: 10_000,
               gc_cleanup_ref: nil,
               gc_heartbeat_ref: nil,
               gc_interval: nil,
               max_size: 3,
               generation_cleanup_timeout: 3_000,
               generation_max_size: 3,
               generation_allocated_memory: 1000,
               meta_tab: meta_tab,
               stats_counter: nil
             } = Generation.get_state(LocalWithSizeLimit)

      assert is_reference(meta_tab)

      :ok = LocalWithSizeLimit.stop()
    end
  end

  describe "generation start timeout" do
    test "no sleep" do
      assert {:ok, _pid} =
               LocalWithSizeLimit.start_link(
                 # 1 is very small and means every manual cleanup will trigger new generation
                 generation_start_timeout: 1
               )

      _ = cache_put(LocalWithSizeLimit, 1..3)

      assert 1 == generations_len(LocalWithSizeLimit)

      :timer.sleep(2)
      Generation.maybe_generation_cleanup(LocalWithSizeLimit)

      assert 2 == generations_len(LocalWithSizeLimit)

      assert 3 == LocalWithSizeLimit.count_all()

      :timer.sleep(2)
      Generation.maybe_generation_cleanup(LocalWithSizeLimit)

      assert 0 == LocalWithSizeLimit.count_all()

      :ok = LocalWithSizeLimit.stop()
    end

    test "sleep" do
      assert {:ok, _pid} =
               LocalWithSizeLimit.start_link(
                 generation_start_timeout: 50,
                 generation_cleanup_timeout: 5
               )

      _ = cache_put(LocalWithSizeLimit, 1..3)

      Generation.maybe_generation_cleanup(LocalWithSizeLimit)

      assert 1 == generations_len(LocalWithSizeLimit)

      :timer.sleep(65)

      assert 2 == generations_len(LocalWithSizeLimit)

      assert 3 == LocalWithSizeLimit.count_all()

      :timer.sleep(65)

      assert 0 == LocalWithSizeLimit.count_all()

      :ok = LocalWithSizeLimit.stop()
    end
  end

  describe "allocated memory" do
    test "cleanup is triggered when max generation size is reached" do
      {:ok, _pid} = LocalWithSizeLimit.start_link(generation_allocated_memory: 100_000)

      assert generations_len(LocalWithSizeLimit) == 1

      # triggers the cleanup event
      :ok = Generation.maybe_generation_cleanup(LocalWithSizeLimit)

      write_cache(1000, 1000)
      assert generations_len(LocalWithSizeLimit) == 1
      assert_mem_size(:>)

      # # wait until the cleanup event is triggered
      :ok = Generation.maybe_generation_cleanup(LocalWithSizeLimit)

      assert generations_len(LocalWithSizeLimit) == 2

      write_cache(2, 2)

      :ok = Generation.maybe_generation_cleanup(LocalWithSizeLimit)

      write_cache(1000, 1000)

      assert LocalWithSizeLimit.count_all() > 1800

      :ok = Generation.maybe_generation_cleanup(LocalWithSizeLimit)

      assert LocalWithSizeLimit.count_all() < 1800

      assert LocalWithSizeLimit.count_all() > 900
      :ok = LocalWithSizeLimit.stop()
    end

    test "cleanup while cache is being used" do
      {:ok, _pid} = LocalWithSizeLimit.start_link(generation_max_size: 3)

      assert generations_len(LocalWithSizeLimit) == 1

      tasks = for i <- 1..3, do: Task.async(fn -> task_fun(LocalWithSizeLimit, i) end)

      for _ <- 1..50 do
        :ok = Process.sleep(10)

        LocalWithSizeLimit
        |> Generation.server()
        |> send(:generation_cleanup)
      end

      # at least one cleanup has happened, then total length will be 2
      assert generations_len(LocalWithSizeLimit) == 2

      for task <- tasks, do: Task.shutdown(task)
      :ok = LocalWithSizeLimit.stop()
    end
  end

  describe "max size" do
    test "cleanup is triggered when size limit is reached" do
      {:ok, _pid} = LocalWithSizeLimit.start_link(generation_max_size: 3)

      # Initially there should be only 1 generation and no entries
      assert generations_len(LocalWithSizeLimit) == 1
      assert LocalWithSizeLimit.count_all() == 0

      # Put some entries to exceed the max size
      _ = cache_put(LocalWithSizeLimit, 1..2)

      # Manually trigger cleanup
      :ok = Generation.maybe_generation_cleanup(LocalWithSizeLimit)

      assert generations_len(LocalWithSizeLimit) == 1

      _ = cache_put(LocalWithSizeLimit, 3..4)

      # Validate current size
      assert LocalWithSizeLimit.count_all() == 4

      # Manually trigger cleanup
      :ok = Generation.maybe_generation_cleanup(LocalWithSizeLimit)

      # There should be 2 generation now
      assert generations_len(LocalWithSizeLimit) == 2

      # The entries should be now in the older generation
      assert LocalWithSizeLimit.count_all() == 4

      # Manually trigger cleanup, no cleanup
      :ok = Generation.maybe_generation_cleanup(LocalWithSizeLimit)

      # The entries should be still in the older generation
      assert LocalWithSizeLimit.count_all() == 4

      # Put some entries without exceeding the max size
      _ = cache_put(LocalWithSizeLimit, 5..9)

      # Validate current size
      assert LocalWithSizeLimit.count_all() == 9

      # Manually trigger cleanup
      :ok = Generation.maybe_generation_cleanup(LocalWithSizeLimit)

      # The entries should be in the older generation yet
      assert LocalWithSizeLimit.count_all() == 5

      _ = cache_put(LocalWithSizeLimit, 11..12)

      # Manually trigger cleanup
      :ok = Generation.maybe_generation_cleanup(LocalWithSizeLimit)

      # The entries should be in the older generation yet
      assert LocalWithSizeLimit.count_all() == 7

      # Put some entries to exceed the max size
      _ = cache_put(LocalWithSizeLimit, 13..16)

      # Manually trigger cleanup
      :ok = Generation.maybe_generation_cleanup(LocalWithSizeLimit)

      # The entries should be in the older generation yet
      assert LocalWithSizeLimit.count_all() == 6

      # Manually trigger cleanup
      :ok = Generation.maybe_generation_cleanup(LocalWithSizeLimit)

      # Cache should be empty now
      assert LocalWithSizeLimit.count_all() == 6

      # Stop the cache
      :ok = LocalWithSizeLimit.stop()
    end
  end

  describe "disable gc" do
    test "disable gc" do
      {:ok, _pid} = LocalWithSizeLimit.start_link(generation_max_size: 3)

      # Put some entries to exceed the max size
      _ = cache_put(LocalWithSizeLimit, 1..4)

      # Manually trigger cleanup
      :ok = Generation.maybe_generation_cleanup(LocalWithSizeLimit)

      assert generations_len(LocalWithSizeLimit) == 2

      _ = cache_put(LocalWithSizeLimit, 5..8)

      :ok = Generation.enable_gc(LocalWithSizeLimit, false)
      :ok = Generation.enable_gc(LocalWithSizeLimit, false)

      :ok = Generation.maybe_generation_cleanup(LocalWithSizeLimit)

      assert 8 == LocalWithSizeLimit.count_all()

      :ok = Generation.enable_gc(LocalWithSizeLimit, true)
      :ok = Generation.enable_gc(LocalWithSizeLimit, true)

      :ok = Generation.maybe_generation_cleanup(LocalWithSizeLimit)

      assert 4 == LocalWithSizeLimit.count_all()

      LocalWithSizeLimit.stop()
    end
  end

  # ## Private Functions

  defp assert_mem_size(greater_or_less) do
    {mem_size, max_size} = Generation.memory_info(LocalWithSizeLimit)
    assert apply(Kernel, greater_or_less, [mem_size, max_size])
  end

  defp write_cache(keys, length) do
    for _ <- 1..keys do
      data =
        :crypto.strong_rand_bytes(length)
        |> Base.encode64()
        |> binary_part(0, length)

      :ok = LocalWithSizeLimit.put(data, data)
    end
  end

  defp generations_len(name) do
    name
    |> Generation.list()
    |> length()
  end

  defp task_fun(cache, i) do
    :ok = cache.put("#{inspect(self())}.#{i}", i)
    :ok = Process.sleep(1)
    task_fun(cache, i + 1)
  end
end
