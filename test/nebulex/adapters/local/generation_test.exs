defmodule Nebulex.Adapters.Local.GenerationTest do
  use ExUnit.Case, async: true

  defmodule LocalWithSizeLimit do
    @moduledoc false
    use Nebulex.Cache,
      otp_app: :nebulex,
      adapter: Nebulex.Adapters.Local,
      gc_interval: Nebulex.Time.expiry_time(1, :hour)
  end

  import Nebulex.CacheHelpers
  import Nebulex.CacheCase

  alias Nebulex.Adapters.Local.Generation
  alias Nebulex.Adapters.Local.GenerationTest.LocalWithSizeLimit
  alias Nebulex.TestCache.Cache

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

      assert cache.flush() == 0

      :ok = Process.sleep(1020)
      assert generations_len(name) == 2
    end

    test "create new generation and reset timeout", %{cache: cache, name: name} do
      assert generations_len(name) == 1

      :ok = Process.sleep(800)
      :ok = cache.new_generation(name: name)
      assert length(Generation.list(name)) == 2

      :ok = Process.sleep(500)
      assert generations_len(name) == 2

      :ok = Process.sleep(520)
      assert generations_len(name) == 2
    end

    test "create new generation without reset timeout", %{cache: cache, name: name} do
      assert generations_len(name) == 1

      :ok = Process.sleep(800)
      :ok = cache.new_generation(name: name, reset_timer: false)
      assert length(Generation.list(name)) == 2

      :ok = Process.sleep(500)
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
      assert generations_len(LocalWithSizeLimit) == 2
      assert_mem_size(:>)

      :ok = flood_cache(mem_size, mem_size * 2)
      assert generations_len(LocalWithSizeLimit) == 2
      assert_mem_size(:>)

      # triggers the cleanup event
      :ok = check_cache_size(LocalWithSizeLimit)

      assert generations_len(LocalWithSizeLimit) == 2

      :ok = LocalWithSizeLimit.stop()
    end

    test "default options" do
      {:ok, _pid} =
        LocalWithSizeLimit.start_link(
          gc_interval: :invalid,
          gc_cleanup_min_timeout: -1,
          gc_cleanup_max_timeout: -1
        )

      assert %{
               gc_interval: nil,
               gc_cleanup_min_timeout: 10_000,
               gc_cleanup_max_timeout: 600_000
             } = get_state()

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
        |> Generation.server_name()
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
      assert generations_len(LocalWithSizeLimit) == 2

      :ok = LocalWithSizeLimit.stop()
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
