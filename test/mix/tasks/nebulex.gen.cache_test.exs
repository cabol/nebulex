defmodule Mix.Tasks.Nebulex.Gen.CacheTest do
  use ExUnit.Case, async: false

  import Nebulex.FileHelpers
  import Mix.Tasks.Nebulex.Gen.Cache, only: [run: 1]
  import Mock

  test "generates a new cache" do
    in_tmp fn _ ->
      run ["-c", "Cache"]

      assert_file "lib/cache.ex", """
      defmodule Cache do
        use Nebulex.Cache, otp_app: :nebulex
      end
      """

      assert_file "config/config.exs", """
      use Mix.Config

      config :nebulex, Cache,
        adapter: Nebulex.Adapters.Local
      """
    end
  end

  test "generates a new cache with existing config file" do
    in_tmp fn _ ->
      File.mkdir_p! "config"
      File.write! "config/config.exs", """
      # Hello
      use Mix.Config
      # World
      """

      run ["-c", "Cache"]

      assert_file "config/config.exs", """
      # Hello
      use Mix.Config

      config :nebulex, Cache,
        adapter: Nebulex.Adapters.Local

      # World
      """
    end
  end

  test "generates a new namespaced cache" do
    in_tmp fn _ ->
      run ["-c", "My.AppCache"]
      assert_file "lib/my/app_cache.ex", "defmodule My.AppCache do"
    end
  end

  test "fail because missing cache option" do
    assert_raise Mix.Error, ~r"nebulex.gen.cache expects the cache to be given as -c", fn ->
      in_tmp fn _ ->
        run []
      end
    end
  end

  test "generates a new cache for Elixir < 1.4.0" do
    with_mock Version, [compare: fn(_, _) -> :lt end] do
      in_tmp fn _ ->
        run ["-c", "Cache"]
        assert_file "lib/cache.ex", "defmodule Cache do"
      end
    end
  end
end
