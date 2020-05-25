defmodule Nebulex.Adapters.Local.GenerationTest do
  use ExUnit.Case, async: true

  import Nebulex.CacheHelpers

  alias Nebulex.Adapters.Local.Generation
  alias Nebulex.TestCache.LocalWithGC, as: TestCache
  alias Nebulex.TestCache.LocalWithSizeLimit

  :ok = Application.put_env(:nebulex, LocalWithGC, compressed: true)

  describe "gc" do
    setup do
      {:ok, pid} = TestCache.start_link(gc_interval: 1000, generations: 3)
      :ok

      on_exit(fn ->
        :ok = Process.sleep(10)
        if Process.alive?(pid), do: TestCache.stop(pid)
      end)
    end

    test "create generations" do
      assert generations_len(TestCache) == 1

      for i <- 2..3 do
        :ok = Process.sleep(1020)
        assert generations_len(TestCache) == i
      end

      assert TestCache.flush() == 0

      for _ <- 1..12 do
        :ok = Process.sleep(1020)
        assert generations_len(TestCache) == 3
      end
    end

    test "create new generation and reset timeout" do
      assert generations_len(TestCache) == 1

      :ok = Process.sleep(800)
      assert length(TestCache.new_generation()) == 2

      :ok = Process.sleep(500)
      assert generations_len(TestCache) == 2

      :ok = Process.sleep(520)
      assert generations_len(TestCache) == 3
    end

    test "create new generation without reset timeout" do
      assert generations_len(TestCache) == 1

      :ok = Process.sleep(800)
      assert length(TestCache.new_generation(reset_timer: false)) == 2

      :ok = Process.sleep(500)
      assert generations_len(TestCache) == 3
    end
  end

  describe "allocated memory" do
    test "cleanup is triggered when max generation size is reached" do
      {:ok, pid} =
        LocalWithSizeLimit.start_link(
          gc_interval: 3_600_000,
          generations: 3,
          allocated_memory: 100_000,
          gc_cleanup_min_timeout: 1000,
          gc_cleanup_max_timeout: 3000
        )

      assert generations_len(LocalWithSizeLimit) == 1

      {mem_size, _} = Generation.memory_info(LocalWithSizeLimit)
      :ok = Generation.realloc(LocalWithSizeLimit, mem_size * 2)

      # triggers the cleanup event
      :ok = check_cache_size(LocalWithSizeLimit)

      :ok = flood_cache(mem_size, mem_size * 2)
      assert generations_len(LocalWithSizeLimit) == 1
      assert_mem_size(:>)

      # wait until the cleanup event is triggered
      :ok = Process.sleep(3000)

      assert generations_len(LocalWithSizeLimit) == 2
      assert_mem_size(:<=)

      :ok = flood_cache(mem_size, mem_size * 2)
      assert generations_len(LocalWithSizeLimit) == 3
      assert_mem_size(:>)

      :ok = flood_cache(mem_size, mem_size * 2)
      assert generations_len(LocalWithSizeLimit) == 3
      assert_mem_size(:>)

      # triggers the cleanup event
      :ok = check_cache_size(LocalWithSizeLimit)

      assert generations_len(LocalWithSizeLimit) == 3

      :ok = LocalWithSizeLimit.stop(pid)
    end

    test "default options" do
      {:ok, pid} =
        LocalWithSizeLimit.start_link(
          gc_interval: :invalid,
          gc_cleanup_min_timeout: -1,
          gc_cleanup_max_timeout: -1
        )

      assert %{
               gc_interval: nil,
               gc_cleanup_min_timeout: 30_000,
               gc_cleanup_max_timeout: 300_000
             } = get_state()

      :ok = LocalWithSizeLimit.stop(pid)
    end

    test "cleanup while cache is being used" do
      {:ok, pid} =
        LocalWithSizeLimit.start_link(
          gc_interval: 3_600_000,
          generations: 3,
          allocated_memory: 100,
          gc_cleanup_min_timeout: 1000,
          gc_cleanup_max_timeout: 3000
        )

      assert generations_len(LocalWithSizeLimit) == 1

      tasks = for i <- 1..3, do: Task.async(fn -> task_fun(LocalWithSizeLimit, i) end)

      for _ <- 1..100 do
        :ok = Process.sleep(10)

        LocalWithSizeLimit
        |> Generation.server_name()
        |> send(:cleanup)
      end

      for task <- tasks, do: Task.shutdown(task)
      :ok = LocalWithSizeLimit.stop(pid)
    end
  end

  describe "max size" do
    test "cleanup is triggered when size limit is reached" do
      {:ok, pid} =
        LocalWithSizeLimit.start_link(
          gc_interval: 3_600_000,
          generations: 3,
          max_size: 3,
          gc_cleanup_min_timeout: 10,
          gc_cleanup_max_timeout: 1000
        )

      assert generations_len(LocalWithSizeLimit) == 1
      assert LocalWithSizeLimit.size() == 0

      _ = cache_put(LocalWithSizeLimit, 1..4)
      assert LocalWithSizeLimit.size() == 4

      :ok = Process.sleep(1100)
      assert generations_len(LocalWithSizeLimit) == 2

      :ok = Process.sleep(1100)
      assert generations_len(LocalWithSizeLimit) == 2

      _ = cache_put(LocalWithSizeLimit, 5..8)
      assert LocalWithSizeLimit.size() == 8

      :ok = Process.sleep(1100)
      assert generations_len(LocalWithSizeLimit) == 3

      :ok = LocalWithSizeLimit.stop(pid)
    end
  end

  ## Private Functions

  defp get_state do
    LocalWithSizeLimit
    |> Generation.server_name()
    |> :sys.get_state()
  end

  defp check_cache_size(cache) do
    :cleanup =
      cache
      |> Generation.server_name()
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

  defp generations_len(cache) do
    length(cache.__metadata__().generations)
  end

  defp task_fun(cache, i) do
    :ok = cache.put("#{inspect(self())}.#{i}", i)
    :ok = Process.sleep(1)
    task_fun(cache, i + 1)
  end
end
