defmodule Nebulex.Adapters.LocalWithShardsTest do
  use ExUnit.Case, async: true
  use Nebulex.LocalTest
  use Nebulex.CacheTest

  import Nebulex.Helpers
  import Nebulex.TestCase

  alias Nebulex.Adapter
  alias Nebulex.TestCache.Cache

  setup_with_dynamic_cache(Cache, :local_with_shards, backend: :shards)

  describe "shards" do
    test "backend", %{name: name} do
      Adapter.with_meta(name, fn _, meta ->
        assert meta.backend == :shards
      end)
    end

    test "custom partitions" do
      defmodule CustomPartitions do
        use Nebulex.Cache,
          otp_app: :nebulex,
          adapter: Nebulex.Adapters.Local
      end

      :ok = Application.put_env(:nebulex, CustomPartitions, backend: :shards, partitions: 2)
      {:ok, _pid} = CustomPartitions.start_link()

      assert [CustomPartitions, Generation, 0]
             |> normalize_module_name()
             |> :shards_state.get()
             |> :shards_state.n_shards() == 2

      :ok = CustomPartitions.stop()
    end
  end
end
