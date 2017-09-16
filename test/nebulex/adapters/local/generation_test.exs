defmodule Nebulex.Adapters.Local.GenerationTest do
  use ExUnit.Case, async: true

  alias Nebulex.TestCache.LocalWithGC, as: TestCache

  setup do
    {:ok, pid} = TestCache.start_link(name: :gc_cache, n_generations: 3, gc_interval: 1)
    :ok

    on_exit fn ->
      _ = :timer.sleep(10)
      if Process.alive?(pid), do: TestCache.stop(pid, 1)
    end
  end

  test "garbage collection" do
    assert length(TestCache.__metadata__.generations) == 1

    for i <- 2..3 do
      _ = :timer.sleep(1010)
      assert length(TestCache.__metadata__.generations) == i
    end

    for _ <- 1..12 do
      _ = :timer.sleep(1010)
      assert length(TestCache.__metadata__.generations) == 3
    end
  end

  test "create new generation and reset timeout" do
    assert length(TestCache.__metadata__.generations) == 1

    _ = :timer.sleep(800)
    assert length(TestCache.new_generation()) == 2

    _ = :timer.sleep(500)
    assert length(TestCache.__metadata__.generations) == 2

    _ = :timer.sleep(510)
    assert length(TestCache.__metadata__.generations) == 3
  end

  test "create new generation without reset timeout" do
    assert length(TestCache.__metadata__.generations) == 1

    _ = :timer.sleep(800)
    assert length(TestCache.new_generation(reset_timeout: false)) == 2

    _ = :timer.sleep(500)
    assert length(TestCache.__metadata__.generations) == 3
  end
end
