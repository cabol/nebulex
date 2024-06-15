defmodule Nebulex.Cache.PersistenceErrorTest do
  import Nebulex.CacheCase

  deftests "persistence error" do
    test "dump/2 fails because invalid path", %{cache: cache} do
      assert {:error,
              %Nebulex.Error{
                module: Nebulex.Error,
                opts: opts,
                reason: %File.Error{action: "open", path: "/invalid/path", reason: :enoent}
              }} = cache.dump("/invalid/path")

      assert Keyword.fetch!(opts, :cache) == cache
      assert Keyword.fetch!(opts, :stacktrace) != []
    end

    test "dump!/2 raises because invalid path", %{cache: cache} do
      err =
        Regex.escape("""
        the following exception occurred when executing a command.

            ** (File.Error) could not open \"/invalid/path\": no such file or directory
        """)

      assert_raise Nebulex.Error, ~r|#{err}|, fn ->
        cache.dump!("/invalid/path")
      end
    end

    test "load/2 error because invalid path", %{cache: cache} do
      assert {:error,
              %Nebulex.Error{
                module: Nebulex.Error,
                opts: opts,
                reason: %File.Error{action: "open", path: "wrong_file", reason: :enoent}
              }} = cache.load("wrong_file")

      assert Keyword.fetch!(opts, :cache) == cache
      assert Keyword.fetch!(opts, :stacktrace) != []
    end

    test "load!/2 raises because invalid path", %{cache: cache} do
      assert_raise Nebulex.Error, ~r|could not open "wrong_file": no such file|, fn ->
        cache.load!("wrong_file")
      end
    end
  end
end
