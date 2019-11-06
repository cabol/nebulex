defmodule Nebulex.Adapters.Local.GenerationTest do
  use ExUnit.Case, async: true

  alias Nebulex.Adapters.Local.Generation
  alias Nebulex.Adapters.Local.Generation.State
  alias Nebulex.TestCache.LocalWithGC, as: TestCache
  alias Nebulex.TestCache.LocalWithSizeLimit

  setup do
    {:ok, pid} = TestCache.start_link()
    :ok

    on_exit(fn ->
      :ok = Process.sleep(10)
      if Process.alive?(pid), do: TestCache.stop(pid)
    end)
  end

  test "garbage collection" do
    assert 1 == n_generations(TestCache)

    for i <- 2..3 do
      :ok = Process.sleep(1020)
      assert i == n_generations(TestCache)
    end

    assert :ok == TestCache.flush()

    for _ <- 1..12 do
      :ok = Process.sleep(1020)
      assert 3 == n_generations(TestCache)
    end
  end

  test "create new generation and reset timeout" do
    assert 1 == n_generations(TestCache)

    :ok = Process.sleep(800)
    assert 2 == length(TestCache.new_generation())

    :ok = Process.sleep(500)
    assert 2 == n_generations(TestCache)

    :ok = Process.sleep(520)
    assert 3 == n_generations(TestCache)
  end

  test "create new generation without reset timeout" do
    assert 1 == n_generations(TestCache)

    :ok = Process.sleep(800)
    assert 2 == length(TestCache.new_generation(reset_timeout: false))

    :ok = Process.sleep(500)
    assert 3 == n_generations(TestCache)
  end

  test "cleanup is triggered when max generation size is reached" do
    assert {:ok, pid} = LocalWithSizeLimit.start_link()
    assert 1 == n_generations(LocalWithSizeLimit)

    %State{memory: mem_size} = Generation.get_state(LocalWithSizeLimit)
    :ok = Generation.realloc(LocalWithSizeLimit, mem_size * 2)

    :ok = flood_cache(mem_size, mem_size * 2)
    assert 1 == n_generations(LocalWithSizeLimit)
    assert_mem_size(:>)

    _ = LocalWithSizeLimit.set("a", generate_value(10))
    :ok = Process.sleep(1000)
    assert 2 == n_generations(LocalWithSizeLimit)
    assert_mem_size(:<=)

    :ok = flood_cache(mem_size, mem_size * 2)
    assert 2 == n_generations(LocalWithSizeLimit)
    assert_mem_size(:>)

    _ = LocalWithSizeLimit.set("a", generate_value(10))
    :ok = Process.sleep(1000)
    assert 3 == n_generations(LocalWithSizeLimit)
    assert_mem_size(:<=)

    assert :ok == LocalWithSizeLimit.stop(pid)
  end

  ## Private Functions

  defp flood_cache(mem_size, max_size) when mem_size > max_size do
    :ok
  end

  defp flood_cache(mem_size, max_size) when mem_size <= max_size do
    _ =
      100_000
      |> :rand.uniform()
      |> LocalWithSizeLimit.set(generate_value(1000))

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

  defp n_generations(cache) do
    length(cache.__metadata__().generations)
  end
end
