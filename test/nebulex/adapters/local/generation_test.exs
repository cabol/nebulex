defmodule Nebulex.Adapters.Local.GenerationTest do
  use ExUnit.Case, async: true

  defmodule LocalWithSizeLimit do
    @moduledoc false
    use Nebulex.Cache,
      otp_app: :nebulex,
      adapter: Nebulex.Adapters.Local,
      gc_interval: :timer.hours(1)
  end

  import Nebulex.CacheCase

  alias Nebulex.Adapters.Local.Generation
  alias Nebulex.Adapters.Local.GenerationTest.LocalWithSizeLimit
  alias Nebulex.TestCache.Cache

  describe "init" do
    test "ok: with default options" do
      assert {:ok, _pid} = LocalWithSizeLimit.start_link()

      assert %Nebulex.Adapters.Local.Generation{
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

    test "ok: with custom options" do
      assert {:ok, _pid} =
               LocalWithSizeLimit.start_link(
                 gc_interval: 10,
                 max_size: 10,
                 allocated_memory: 1000
               )

      assert %Nebulex.Adapters.Local.Generation{
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
               gc_cleanup_ref: gc_cleanup_ref,
               gc_heartbeat_ref: gc_heartbeat_ref,
               gc_interval: 10,
               max_size: 10,
               meta_tab: meta_tab,
               stats_counter: nil
             } = Generation.get_state(LocalWithSizeLimit)

      assert is_reference(gc_cleanup_ref)
      assert is_reference(gc_heartbeat_ref)
      assert is_reference(meta_tab)

      :ok = LocalWithSizeLimit.stop()
    end

    test "error: invalid gc_cleanup_min_timeout" do
      _ = Process.flag(:trap_exit, true)

      assert {:error, {:shutdown, {_, _, {:shutdown, {_, _, {%ArgumentError{message: err}, _}}}}}} =
               LocalWithSizeLimit.start_link(
                 gc_interval: 3600,
                 gc_cleanup_min_timeout: -1,
                 gc_cleanup_max_timeout: -1
               )

      assert err == "expected gc_cleanup_min_timeout: to be an integer > 0, got: -1"
    end
  end

  describe "gc" do
    setup_with_dynamic_cache(Cache, :gc_test,
      backend: :shards,
      gc_interval: 1000,
      compressed: true
    )

    test "create generations", %{cache: cache, name: name} do
      assert generations_len(name) == 1

      :ok = Process.sleep(1020)
      assert generations_len(name) == 2

      assert cache.delete_all() == 0

      :ok = Process.sleep(1020)
      assert generations_len(name) == 2
    end

    test "create new generation and reset timeout", %{cache: cache, name: name} do
      assert generations_len(name) == 1

      :ok = Process.sleep(800)

      cache.with_dynamic_cache(name, fn ->
        cache.new_generation()
      end)

      assert generations_len(name) == 2

      :ok = Process.sleep(500)
      assert generations_len(name) == 2

      :ok = Process.sleep(520)
      assert generations_len(name) == 2
    end

    test "create new generation without reset timeout", %{cache: cache, name: name} do
      assert generations_len(name) == 1

      :ok = Process.sleep(800)

      cache.with_dynamic_cache(name, fn ->
        cache.new_generation(reset_timer: false)
      end)

      assert generations_len(name) == 2

      :ok = Process.sleep(500)
      assert generations_len(name) == 2
    end

    test "reset timer", %{cache: cache, name: name} do
      assert generations_len(name) == 1

      :ok = Process.sleep(800)

      cache.with_dynamic_cache(name, fn ->
        cache.reset_generation_timer()
      end)

      :ok = Process.sleep(220)
      assert generations_len(name) == 1

      :ok = Process.sleep(1000)
      assert generations_len(name) == 2
    end
  end

  describe "allocated memory" do
    test "cleanup is triggered when max generation size is reached" do
      {:ok, _pid} =
        LocalWithSizeLimit.start_link(
          gc_interval: 3_600_000,
          allocated_memory: 100_000,
          gc_cleanup_min_timeout: 1000,
          gc_cleanup_max_timeout: 3000
        )

      assert generations_len(LocalWithSizeLimit) == 1

      {mem_size, _} = Generation.memory_info(LocalWithSizeLimit)
      :ok = Generation.realloc(LocalWithSizeLimit, mem_size * 2)

      # Trigger the cleanup event
      :ok = check_cache_size(LocalWithSizeLimit)

      assert generations_len(LocalWithSizeLimit) == 1

      :ok = flood_cache(mem_size, mem_size * 2)

      assert_mem_size(:>)

      # Wait until the cleanup event is triggered
      :ok = Process.sleep(3100)

      wait_until(fn ->
        assert generations_len(LocalWithSizeLimit) == 2
        assert_mem_size(:<=)
      end)

      :ok = flood_cache(mem_size, mem_size * 2)

      wait_until(fn ->
        assert generations_len(LocalWithSizeLimit) == 2
        assert_mem_size(:>)
      end)

      :ok = flood_cache(mem_size, mem_size * 2)

      wait_until(fn ->
        assert generations_len(LocalWithSizeLimit) == 2
        assert_mem_size(:>)
      end)

      # triggers the cleanup event
      :ok = check_cache_size(LocalWithSizeLimit)

      assert generations_len(LocalWithSizeLimit) == 2

      :ok = LocalWithSizeLimit.stop()
    end

    test "cleanup while cache is being used" do
      {:ok, _pid} =
        LocalWithSizeLimit.start_link(
          gc_interval: 3_600_000,
          allocated_memory: 100,
          gc_cleanup_min_timeout: 1000,
          gc_cleanup_max_timeout: 3000
        )

      assert generations_len(LocalWithSizeLimit) == 1

      tasks = for i <- 1..3, do: Task.async(fn -> task_fun(LocalWithSizeLimit, i) end)

      for _ <- 1..100 do
        :ok = Process.sleep(10)

        LocalWithSizeLimit
        |> Generation.server()
        |> send(:cleanup)
      end

      for task <- tasks, do: Task.shutdown(task)

      :ok = LocalWithSizeLimit.stop()
    end
  end

  describe "max size" do
    test "cleanup is triggered when size limit is reached" do
      {:ok, _pid} =
        LocalWithSizeLimit.start_link(
          gc_interval: 3_600_000,
          max_size: 3,
          gc_cleanup_min_timeout: 1000,
          gc_cleanup_max_timeout: 1500
        )

      # Initially there should be only 1 generation and no entries
      assert generations_len(LocalWithSizeLimit) == 1
      assert LocalWithSizeLimit.count_all() == 0

      # Put some entries to exceed the max size
      _ = cache_put(LocalWithSizeLimit, 1..4)

      # Validate current size
      assert LocalWithSizeLimit.count_all() == 4

      # Wait the max cleanup timeout
      :ok = Process.sleep(1600)

      # There should be 2 generation now
      assert generations_len(LocalWithSizeLimit) == 2

      # The entries should be now in the older generation
      assert LocalWithSizeLimit.count_all() == 4

      # Wait the min cleanup timeout since max size is exceeded
      :ok = Process.sleep(1100)

      # Cache should be empty now
      assert LocalWithSizeLimit.count_all() == 0

      # Put some entries without exceeding the max size
      _ = cache_put(LocalWithSizeLimit, 5..6)

      # Validate current size
      assert LocalWithSizeLimit.count_all() == 2

      # Wait the max cleanup timeout (timeout should be relative to the size)
      :ok = Process.sleep(1600)

      # The entries should be in the newer generation yet
      assert LocalWithSizeLimit.count_all() == 2

      # Put some entries to exceed the max size
      _ = cache_put(LocalWithSizeLimit, 7..8)

      # Wait the max cleanup timeout
      :ok = Process.sleep(1600)

      # The entries should be in the newer generation yet
      assert LocalWithSizeLimit.count_all() == 4

      # Wait the min cleanup timeout since max size is exceeded
      :ok = Process.sleep(1100)

      # Cache should be empty now
      assert LocalWithSizeLimit.count_all() == 0

      # Stop the cache
      :ok = LocalWithSizeLimit.stop()
    end
  end

  describe "cleanup cover" do
    test "cleanup when gc_interval not set" do
      {:ok, _pid} =
        LocalWithSizeLimit.start_link(
          max_size: 3,
          gc_cleanup_min_timeout: 1000,
          gc_cleanup_max_timeout: 1500
        )

      # Put some entries to exceed the max size
      _ = cache_put(LocalWithSizeLimit, 1..4)

      # Wait the max cleanup timeout
      :ok = Process.sleep(1600)

      # assert not crashed
      assert LocalWithSizeLimit.count_all() == 4

      # Stop the cache
      :ok = LocalWithSizeLimit.stop()
    end
  end

  ## Private Functions

  defp check_cache_size(cache) do
    :cleanup =
      cache
      |> Generation.server()
      |> send(:cleanup)

    :ok = Process.sleep(1000)
  end

  defp flood_cache(mem_size, max_size) when mem_size > max_size do
    :ok
  end

  defp flood_cache(mem_size, max_size) when mem_size <= max_size do
    :ok =
      100_000
      |> :rand.uniform()
      |> LocalWithSizeLimit.put(generate_value(1000))

    :ok = Process.sleep(500)
    {mem_size, _} = Generation.memory_info(LocalWithSizeLimit)
    flood_cache(mem_size, max_size)
  end

  defp assert_mem_size(greater_or_less) do
    {mem_size, max_size} = Generation.memory_info(LocalWithSizeLimit)
    assert apply(Kernel, greater_or_less, [mem_size, max_size])
  end

  defp generate_value(n) do
    for(_ <- 1..n, do: "a")
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
