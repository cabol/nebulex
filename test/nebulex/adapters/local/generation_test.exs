defmodule Nebulex.Adapters.Local.GenerationTest do
  use ExUnit.Case, async: true

  alias Nebulex.TestCache.LocalWithGC, as: TestCache

  setup do
    {:ok, pid} = TestCache.start_link(name: :gc_cache, n_generations: 3, gc_interval: 1)
    :ok

    on_exit(fn ->
      _ = :timer.sleep(10)
      if Process.alive?(pid), do: TestCache.stop(pid)
    end)
  end

  test "garbage collection" do
    assert 1 == length(TestCache.__metadata__().generations)

    for i <- 2..3 do
      _ = :timer.sleep(1020)
      assert i == length(TestCache.__metadata__().generations)
    end

    assert :ok == TestCache.flush()

    for _ <- 1..12 do
      _ = :timer.sleep(1020)
      assert 3 == length(TestCache.__metadata__().generations)
    end
  end

  test "create new generation and reset timeout" do
    assert 1 == length(TestCache.__metadata__().generations)

    _ = :timer.sleep(800)
    assert 2 == length(TestCache.new_generation())

    _ = :timer.sleep(500)
    assert 2 == length(TestCache.__metadata__().generations)

    _ = :timer.sleep(520)
    assert 3 == length(TestCache.__metadata__().generations)
  end

  test "create new generation without reset timeout" do
    assert 1 == length(TestCache.__metadata__().generations)

    _ = :timer.sleep(800)
    assert 2 == length(TestCache.new_generation(reset_timeout: false))

    _ = :timer.sleep(500)
    assert 3 == length(TestCache.__metadata__().generations)
  end
end
