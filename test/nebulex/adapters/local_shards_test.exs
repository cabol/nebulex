defmodule Nebulex.Adapters.LocalWithShardsTest do
  use ExUnit.Case, async: true
  use Nebulex.CacheTest, cache: Nebulex.TestCache.LocalWithShards
  use Nebulex.LocalTest, cache: Nebulex.TestCache.LocalWithShards

  alias Nebulex.TestCache.LocalWithShards

  test "backend" do
    assert LocalWithShards.__backend__() == :shards
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
