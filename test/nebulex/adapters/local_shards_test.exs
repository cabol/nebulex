defmodule Nebulex.Adapters.LocalWithShardsTest do
  use ExUnit.Case, async: true
  use Nebulex.LocalTest, cache: Nebulex.TestCache.Local.Shards
  use Nebulex.CacheTest, cache: Nebulex.TestCache.Local.Shards

  alias Nebulex.TestCache.Local.Shards, as: Cache

  setup do
    {:ok, pid} = @cache.start_link(generations: 2)
    :ok

    on_exit(fn ->
      :ok = Process.sleep(10)
      if Process.alive?(pid), do: @cache.stop(pid)
    end)
  end

  describe "shards" do
    test "backend" do
      assert Cache.__backend__() == :shards
    end

    test "custom partitions" do
      defmodule CustomPartitions do
        use Nebulex.Cache,
          otp_app: :nebulex,
          adapter: Nebulex.Adapters.Local,
          backend: :shards
      end

      :ok = Application.put_env(:nebulex, CustomPartitions, partitions: 2)
      {:ok, pid} = CustomPartitions.start_link()

      assert 2 ==
               CustomPartitions
               |> Module.concat("0")
               |> :shards_state.get()
               |> :shards_state.n_shards()

      :ok = CustomPartitions.stop(pid)
    end
  end
end
