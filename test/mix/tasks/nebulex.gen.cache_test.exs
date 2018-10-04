defmodule Mix.Tasks.Nebulex.Gen.CacheTest do
  use ExUnit.Case, async: false

  import Nebulex.FileHelpers
  import Mix.Tasks.Nebulex.Gen.Cache, only: [run: 1]

  test "generates a new cache" do
    in_tmp(fn _ ->
      run(["-c", "Cache"])

      assert_file("lib/cache.ex", """
      defmodule Cache do
        use Nebulex.Cache,
          otp_app: :nebulex,
          adapter: Nebulex.Adapters.Local
      end
      """)

      assert_file("config/config.exs", """
      use Mix.Config

      config :nebulex, Cache,
        gc_interval: 86_400 # 24 hrs
      """)
    end)
  end

  test "generates a new cache with existing config file" do
    in_tmp(fn _ ->
      File.mkdir_p!("config")

      File.write!("config/config.exs", """
      # Hello
      use Mix.Config
      # World
      """)

      run(["-c", "Cache"])

      assert_file("config/config.exs", """
      # Hello
      use Mix.Config

      config :nebulex, Cache,
        gc_interval: 86_400 # 24 hrs

      # World
      """)
    end)
  end

  test "generates a new namespaced cache" do
    in_tmp(fn _ ->
      run(["-c", "My.AppCache"])
      assert_file("lib/my/app_cache.ex", "defmodule My.AppCache do")
    end)
  end

  test "fail because missing cache option" do
    assert_raise Mix.Error, ~r"nebulex.gen.cache expects the cache to be given as -c", fn ->
      in_tmp(fn _ ->
        run([])
      end)
    end
  end

  test "generates a new distributed cache" do
    in_tmp(fn _ ->
      run(["-c", "Cache", "-a", "Nebulex.Adapters.Dist"])

      assert_file("lib/cache.ex", """
      defmodule Cache do
        use Nebulex.Cache,
          otp_app: :nebulex,
          adapter: Nebulex.Adapters.Dist
      end
      """)

      assert_file("config/config.exs", """
      use Mix.Config

      config :nebulex, Cache,
        local: :YOUR_LOCAL_CACHE
      """)
    end)
  end

  test "generates a new multilevel cache" do
    in_tmp(fn _ ->
      run(["-c", "Cache", "-a", "Nebulex.Adapters.Multilevel"])

      assert_file("lib/cache.ex", """
      defmodule Cache do
        use Nebulex.Cache,
          otp_app: :nebulex,
          adapter: Nebulex.Adapters.Multilevel
      end
      """)

      assert_file("config/config.exs", """
      use Mix.Config

      config :nebulex, Cache,
        cache_model: :inclusive,
        levels: []
      """)
    end)
  end

  test "generates a new default cache" do
    in_tmp(fn _ ->
      run(["-c", "Cache", "-a", "MyAdapter"])

      assert_file("lib/cache.ex", """
      defmodule Cache do
        use Nebulex.Cache,
          otp_app: :nebulex,
          adapter: MyAdapter
      end
      """)

      assert_file("config/config.exs", """
      use Mix.Config

      config :nebulex, Cache,
        gc_interval: 86_400 # 24 hrs
      """)
    end)
  end
end
