defmodule Nebulex.Adapters.Local.GenerationNewTest do
  use ExUnit.Case, async: true

  defmodule LocalWithSizeLimit do
    @moduledoc false
    use Nebulex.Cache,
      otp_app: :nebulex,
      adapter: Nebulex.Adapters.Local
  end

  import Nebulex.CacheCase

  alias Nebulex.Adapters.Local.Generation
  alias Nebulex.Adapters.Local.GenerationNewTest.LocalWithSizeLimit
  alias Nebulex.TestCache.Cache

  describe "generation_new init" do
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
                 generation_cleanup_timeout: 3_000,
                 generation_max_size: 3,
                 generation_allocated_memory: 1000
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

  # describe "gc" do
  #   setup_with_dynamic_cache(Cache, :gc_test,
  #     backend: :shards,
  #     gc_interval: 1000,
  #     compressed: true
  #   )

  #   test "create generations", %{cache: cache, name: name} do
  #     assert generations_len(name) == 1

  #     :ok = Process.sleep(1020)
  #     assert generations_len(name) == 2

  #     assert cache.delete_all() == 0

  #     :ok = Process.sleep(1020)
  #     assert generations_len(name) == 2
  #   end

  #   test "create new generation and reset timeout", %{cache: cache, name: name} do
  #     assert generations_len(name) == 1

  #     :ok = Process.sleep(800)

  #     cache.with_dynamic_cache(name, fn ->
  #       cache.new_generation()
  #     end)

  #     assert generations_len(name) == 2

  #     :ok = Process.sleep(500)
  #     assert generations_len(name) == 2

  #     :ok = Process.sleep(520)
  #     assert generations_len(name) == 2
  #   end

  #   test "create new generation without reset timeout", %{cache: cache, name: name} do
  #     assert generations_len(name) == 1

  #     :ok = Process.sleep(800)

  #     cache.with_dynamic_cache(name, fn ->
  #       cache.new_generation(reset_timer: false)
  #     end)

  #     assert generations_len(name) == 2

  #     :ok = Process.sleep(500)
  #     assert generations_len(name) == 2
  #   end

  #   test "reset timer", %{cache: cache, name: name} do
  #     assert generations_len(name) == 1

  #     :ok = Process.sleep(800)

  #     cache.with_dynamic_cache(name, fn ->
  #       cache.reset_generation_timer()
  #     end)

  #     :ok = Process.sleep(220)
  #     assert generations_len(name) == 1

  #     :ok = Process.sleep(1000)
  #     assert generations_len(name) == 2
  #   end
  # end

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

    # test "cleanup while cache is being used" do
    #   {:ok, _pid} =
    #     LocalWithSizeLimit.start_link(
    #       gc_interval: 3_600_000,
    #       allocated_memory: 100,
    #       gc_cleanup_min_timeout: 1000,
    #       gc_cleanup_max_timeout: 3000
    #     )

    #   assert generations_len(LocalWithSizeLimit) == 1

    #   tasks = for i <- 1..3, do: Task.async(fn -> task_fun(LocalWithSizeLimit, i) end)

    #   for _ <- 1..100 do
    #     :ok = Process.sleep(10)

    #     LocalWithSizeLimit
    #     |> Generation.server()
    #     |> send(:cleanup)
    #   end

    #   for task <- tasks, do: Task.shutdown(task)
    #   :ok = LocalWithSizeLimit.stop()
    # end
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
      :ok = Nebulex.Adapters.Local.Generation.maybe_generation_cleanup(LocalWithSizeLimit)

      assert generations_len(LocalWithSizeLimit) == 1

      _ = cache_put(LocalWithSizeLimit, 3..4)

      # Validate current size
      assert LocalWithSizeLimit.count_all() == 4

      # Manually trigger cleanup
      :ok = Nebulex.Adapters.Local.Generation.maybe_generation_cleanup(LocalWithSizeLimit)

      # There should be 2 generation now
      assert generations_len(LocalWithSizeLimit) == 2

      # The entries should be now in the older generation
      assert LocalWithSizeLimit.count_all() == 4

      # Manually trigger cleanup, no cleanup
      :ok = Nebulex.Adapters.Local.Generation.maybe_generation_cleanup(LocalWithSizeLimit)

      # The entries should be still in the older generation
      assert LocalWithSizeLimit.count_all() == 4

      # Put some entries without exceeding the max size
      _ = cache_put(LocalWithSizeLimit, 5..9)

      # Validate current size
      assert LocalWithSizeLimit.count_all() == 9

      # Manually trigger cleanup
      :ok = Nebulex.Adapters.Local.Generation.maybe_generation_cleanup(LocalWithSizeLimit)

      # The entries should be in the older generation yet
      assert LocalWithSizeLimit.count_all() == 5

      _ = cache_put(LocalWithSizeLimit, 11..12)

      # Manually trigger cleanup
      :ok = Nebulex.Adapters.Local.Generation.maybe_generation_cleanup(LocalWithSizeLimit)

      # The entries should be in the older generation yet
      assert LocalWithSizeLimit.count_all() == 7

      # Put some entries to exceed the max size
      _ = cache_put(LocalWithSizeLimit, 13..16)

      # Manually trigger cleanup
      :ok = Nebulex.Adapters.Local.Generation.maybe_generation_cleanup(LocalWithSizeLimit)

      # The entries should be in the older generation yet
      assert LocalWithSizeLimit.count_all() == 6

      # Manually trigger cleanup
      :ok = Nebulex.Adapters.Local.Generation.maybe_generation_cleanup(LocalWithSizeLimit)

      # Cache should be empty now
      assert LocalWithSizeLimit.count_all() == 6

      # Stop the cache
      :ok = LocalWithSizeLimit.stop()
    end
  end

  # ## Private Functions

  # defp check_cache_size(cache) do
  #   :cleanup =
  #     cache
  #     |> Generation.server()
  #     |> send(:cleanup)

  #   :ok = Process.sleep(1000)
  # end

  defp assert_mem_size(greater_or_less) do
    {mem_size, max_size} = Generation.memory_info(LocalWithSizeLimit)
    IO.puts("mem_size is: #{mem_size}")
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
