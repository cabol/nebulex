defmodule Nebulex.Adapters.Local.GenerationTest do
  use ExUnit.Case, async: true

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
    assert 1 == length(TestCache.__metadata__().generations)

    for i <- 2..3 do
      :ok = Process.sleep(1020)
      assert i == length(TestCache.__metadata__().generations)
    end

    assert :ok == TestCache.flush()

    for _ <- 1..12 do
      :ok = Process.sleep(1020)
      assert 3 == length(TestCache.__metadata__().generations)
    end
  end

  test "create new generation and reset timeout" do
    assert 1 == length(TestCache.__metadata__().generations)

    :ok = Process.sleep(800)
    assert 2 == length(TestCache.new_generation())

    :ok = Process.sleep(500)
    assert 2 == length(TestCache.__metadata__().generations)

    :ok = Process.sleep(520)
    assert 3 == length(TestCache.__metadata__().generations)
  end

  test "create new generation without reset timeout" do
    assert 1 == length(TestCache.__metadata__().generations)

    :ok = Process.sleep(800)
    assert 2 == length(TestCache.new_generation(reset_timeout: false))

    :ok = Process.sleep(500)
    assert 3 == length(TestCache.__metadata__().generations)
  end

  test "cleanup is triggered when max generation size is reached" do
    assert {:ok, pid} = LocalWithSizeLimit.start_link()
    assert 1 == length(LocalWithSizeLimit.__metadata__().generations)

    assert_generations(1, 10_000, 1)
    assert_generations(2, 100, 2)

    assert_generations(3, 100, 2)
    assert_generations(4, 100, 2)

    assert_generations(5, 15_000, 2)
    assert_generations(6, 100, 3)

    assert :ok == LocalWithSizeLimit.stop(pid)
  end

  ## Private Functions

  defp assert_generations(key, n, n_gens) do
    _ = LocalWithSizeLimit.set(key, rand_bytes(n))
    :ok = Process.sleep(1000)
    assert n_gens == length(LocalWithSizeLimit.__metadata__().generations)
  end

  defp rand_bytes(n) do
    for(_ <- 1..n, do: "a")
  end
end
