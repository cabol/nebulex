defmodule Nebulex.Cache.PersistenceErrorTest do
  import Nebulex.CacheCase

  deftests "persistence error" do
    test "dump/2 fails because invalid path", %{cache: cache} do
      assert cache.dump("/invalid/path") ==
               {:error,
                %Nebulex.Error{
                  module: Nebulex.Error,
                  reason: %File.Error{action: "open", path: "/invalid/path", reason: :enoent}
                }}
    end

    test "dump!/2 raises because invalid path", %{cache: cache} do
      msg = "could not open \"/invalid/path\": no such file or directory"

      assert_raise Nebulex.Error, msg, fn ->
        cache.dump!("/invalid/path")
      end
    end

    test "load/2 error because invalid path", %{cache: cache} do
      assert cache.load("wrong_file") ==
               {:error,
                %Nebulex.Error{
                  module: Nebulex.Error,
                  reason: %File.Error{action: "open", path: "wrong_file", reason: :enoent}
                }}
    end

    test "load!/2 raises because invalid path", %{cache: cache} do
      assert_raise Nebulex.Error, "could not open \"wrong_file\": no such file or directory", fn ->
        cache.load!("wrong_file")
      end
    end
  end
end
