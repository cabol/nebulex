defmodule Nebulex.Cache.PersistenceErrorTest do
  import Nebulex.CacheCase

  deftests "persistence error" do
    test "dump: invalid path", %{cache: cache} do
      assert cache.dump("/invalid/path") == {:error, :enoent}
    end

    test "load: invalid path", %{cache: cache} do
      assert cache.load("wrong_file") == {:error, :enoent}
    end
  end
end
