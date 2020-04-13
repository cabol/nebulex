defmodule Nebulex.Adapters.LocalEtsTest do
  use ExUnit.Case, async: true
  use Nebulex.LocalTest, cache: Nebulex.TestCache.Local.ETS
  use Nebulex.CacheTest, cache: Nebulex.TestCache.Local.ETS

  alias Nebulex.TestCache.Local.ETS, as: Cache

  setup do
    {:ok, pid} = @cache.start_link(generations: 2)
    :ok

    on_exit(fn ->
      :ok = Process.sleep(10)
      if Process.alive?(pid), do: @cache.stop(pid)
    end)
  end

  describe "ets" do
    test "backend" do
      assert Cache.__backend__() == :ets
    end
  end
end
