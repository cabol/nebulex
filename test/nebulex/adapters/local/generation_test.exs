defmodule Nebulex.Adapters.Local.GenerationTest do
  use ExUnit.Case, async: true

  alias Nebulex.Adapters.Local.Generation
  alias Nebulex.Adapters.Local.Generation.State
  alias Nebulex.TestCache.LocalWithGC, as: TestCache
  alias Nebulex.TestCache.LocalWithSizeLimit

  :ok = Application.put_env(:nebulex, LocalWithGC, compressed: true)

  :ok =
    Application.put_env(
      :nebulex,
      LocalWithSizeLimit,
      allocated_memory: 100_000,
      gc_cleanup_interval: 2
    )

  setup do
    {:ok, pid} = TestCache.start_link(gc_interval: 1, generations: 3)
    :ok

    on_exit(fn ->
      :ok = Process.sleep(10)
      if Process.alive?(pid), do: TestCache.stop(pid)
    end)
  end

  test "garbage collection" do
    assert 1 == generations_len(TestCache)

    for i <- 2..3 do
      :ok = Process.sleep(1020)
      assert i == generations_len(TestCache)
    end

    assert 0 == TestCache.flush()

    for _ <- 1..12 do
      :ok = Process.sleep(1020)
      assert 3 == generations_len(TestCache)
    end
  end

  test "create new generation and reset timeout" do
    assert 1 == generations_len(TestCache)

    :ok = Process.sleep(800)
    assert 2 == length(TestCache.new_generation())

    :ok = Process.sleep(500)
    assert 2 == generations_len(TestCache)

    :ok = Process.sleep(520)
    assert 3 == generations_len(TestCache)
  end

  test "create new generation without reset timeout" do
    assert 1 == generations_len(TestCache)

    :ok = Process.sleep(800)
    assert 2 == length(TestCache.new_generation(reset_timer: false))

    :ok = Process.sleep(500)
    assert 3 == generations_len(TestCache)
  end

  test "cleanup is triggered when max generation size is reached" do
    {:ok, pid} =
      LocalWithSizeLimit.start_link(
        gc_interval: 3600,
        generations: 3,
        allocated_memory: 100_000,
        gc_cleanup_min_timeout: 1,
        gc_cleanup_max_timeout: 3
      )

    assert 1 == generations_len(LocalWithSizeLimit)

    %State{memory: mem_size} = Generation.get_state(LocalWithSizeLimit)
    :ok = Generation.realloc(LocalWithSizeLimit, mem_size * 2)

    # triggers the cleanup event
    :ok = check_cache_size(LocalWithSizeLimit)

    :ok = flood_cache(mem_size, mem_size * 2)
    assert 1 == generations_len(LocalWithSizeLimit)
    assert_mem_size(:>)

    # wait until the cleanup event is triggered
    :ok = Process.sleep(3000)

    assert 2 == generations_len(LocalWithSizeLimit)
    assert_mem_size(:<=)

    :ok = flood_cache(mem_size, mem_size * 2)
    assert 3 == generations_len(LocalWithSizeLimit)
    assert_mem_size(:>)

    :ok = flood_cache(mem_size, mem_size * 2)
    assert 3 == generations_len(LocalWithSizeLimit)
    assert_mem_size(:>)

    # triggers the cleanup event
    :ok = check_cache_size(LocalWithSizeLimit)

    assert 3 == generations_len(LocalWithSizeLimit)

    :ok = LocalWithSizeLimit.stop(pid)
  end

  test "default options" do
    {:ok, pid} =
      LocalWithSizeLimit.start_link(
        gc_interval: :invalid,
        gc_cleanup_min_timeout: -1,
        gc_cleanup_max_timeout: -1
      )

    assert %State{
             gc_interval: nil,
             gc_cleanup_min_timeout: 30,
             gc_cleanup_max_timeout: 300
           } = Generation.get_state(LocalWithSizeLimit)

    :ok = LocalWithSizeLimit.stop(pid)
  end

  test "cleanup while cache is being used" do
    {:ok, pid} =
      LocalWithSizeLimit.start_link(
        gc_interval: 3600,
        generations: 3,
        allocated_memory: 100,
        gc_cleanup_min_timeout: 1,
        gc_cleanup_max_timeout: 3
      )

    assert 1 == generations_len(LocalWithSizeLimit)

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

  ## Private Functions

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
    %State{memory: mem_size} = Generation.get_state(LocalWithSizeLimit)
    flood_cache(mem_size, max_size)
  end

  defp assert_mem_size(greater_or_less) do
    %State{
      allocated_memory: max_size,
      memory: mem_size
    } = Generation.get_state(LocalWithSizeLimit)

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
