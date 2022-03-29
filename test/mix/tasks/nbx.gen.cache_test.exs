defmodule Mix.Tasks.Nbx.Gen.CacheTest do
  use ExUnit.Case

  import Mix.Tasks.Nbx.Gen.Cache, only: [run: 1]

  describe "nbx.gen.cache" do
    test "generates a new cache" do
      in_tmp("new_cache", fn ->
        run(["-c", "Cache"])

        assert_file("lib/cache.ex", """
        defmodule Cache do
          use Nebulex.Cache,
            otp_app: :nebulex,
            adapter: Nebulex.Adapters.Local
        end
        """)

        first_line = if Code.ensure_loaded?(Config), do: "import Config", else: "use Mix.Config"

        assert_file("config/config.exs", """
        #{first_line}

        config :nebulex, Cache,
          # When using :shards as backend
          # backend: :shards,
          # GC interval for pushing new generation: 12 hrs
          gc_interval: :timer.hours(12),
          # Max 1 million entries in cache
          max_size: 1_000_000,
          # Max 2 GB of memory
          allocated_memory: 2_000_000_000,
          # GC min timeout: 10 sec
          gc_cleanup_min_timeout: :timer.seconds(10),
          # GC max timeout: 10 min
          gc_cleanup_max_timeout: :timer.minutes(10)
        """)
      end)
    end

    test "generates a new cache with existing config file" do
      in_tmp("existing_config", fn ->
        File.mkdir_p!("config")

        File.write!("config/config.exs", """
        # Hello
        use Mix.Config
        # World
        """)

        run(["-c", "Cache", "-a", "ABC"])

        assert_file("config/config.exs", """
        # Hello
        use Mix.Config

        # See the adapter's documentation for configuration options
        # config :nebulex, Cache,
        #   key: :value
        # World
        """)
      end)
    end

    test "generates a new namespaced cache" do
      in_tmp("namespaced", fn ->
        run(["-c", "MyApp.Cache"])
        assert_file("lib/my_app/cache.ex", "defmodule MyApp.Cache do")
      end)
    end

    test "raises exception because missing option -c" do
      msg = "nbx.gen.cache expects the cache to be given as -c MyApp.Cache"

      assert_raise Mix.Error, msg, fn ->
        run(["-a", "ABC"])
      end
    end

    test "raises exception because multiple options -c" do
      msg = "nbx.gen.cache expects a single cache to be given"

      assert_raise Mix.Error, msg, fn ->
        run(["-c", "Cache1", "-c", "Cache2"])
      end
    end

    test "raises exception because multiple options -a" do
      msg = "nbx.gen.cache expects a single adapter to be given"

      assert_raise Mix.Error, msg, fn ->
        run(["-c", "Cache", "-a", "A", "-a", "B"])
      end
    end
  end

  describe "nbx.gen.cache with -a option" do
    test "generates a partitioned cache" do
      in_tmp("partitioned_cache", fn ->
        run(["-c", "PartitionedCache", "-a", "Nebulex.Adapters.Partitioned"])

        assert_file("lib/partitioned_cache.ex", """
        defmodule PartitionedCache do
          use Nebulex.Cache,
            otp_app: :nebulex,
            adapter: Nebulex.Adapters.Partitioned,
            primary_storage_adapter: Nebulex.Adapters.Local
        end
        """)

        first_line = if Code.ensure_loaded?(Config), do: "import Config", else: "use Mix.Config"

        assert_file("config/config.exs", """
        #{first_line}

        config :nebulex, PartitionedCache,
          primary: [
            # When using :shards as backend
            # backend: :shards,
            # GC interval for pushing new generation: 12 hrs
            gc_interval: :timer.hours(12),
            # Max 1 million entries in cache
            max_size: 1_000_000,
            # Max 2 GB of memory
            allocated_memory: 2_000_000_000,
            # GC min timeout: 10 sec
            gc_cleanup_min_timeout: :timer.seconds(10),
            # GC max timeout: 10 min
            gc_cleanup_max_timeout: :timer.minutes(10)
          ]
        """)
      end)
    end

    test "generates a replicated cache" do
      in_tmp("replicated_cache", fn ->
        run(["-c", "ReplicatedCache", "-a", "Nebulex.Adapters.Replicated"])

        assert_file("lib/replicated_cache.ex", """
        defmodule ReplicatedCache do
          use Nebulex.Cache,
            otp_app: :nebulex,
            adapter: Nebulex.Adapters.Replicated,
            primary_storage_adapter: Nebulex.Adapters.Local
        end
        """)

        first_line = if Code.ensure_loaded?(Config), do: "import Config", else: "use Mix.Config"

        assert_file("config/config.exs", """
        #{first_line}

        config :nebulex, ReplicatedCache,
          primary: [
            # When using :shards as backend
            # backend: :shards,
            # GC interval for pushing new generation: 12 hrs
            gc_interval: :timer.hours(12),
            # Max 1 million entries in cache
            max_size: 1_000_000,
            # Max 2 GB of memory
            allocated_memory: 2_000_000_000,
            # GC min timeout: 10 sec
            gc_cleanup_min_timeout: :timer.seconds(10),
            # GC max timeout: 10 min
            gc_cleanup_max_timeout: :timer.minutes(10)
          ]
        """)
      end)
    end

    test "generates a multilevel cache" do
      in_tmp("multilevel_cache", fn ->
        run(["-c", "MultilevelCache", "-a", "Nebulex.Adapters.Multilevel"])

        assert_file("lib/multilevel_cache.ex", """
        defmodule MultilevelCache do
          use Nebulex.Cache,
            otp_app: :nebulex,
            adapter: Nebulex.Adapters.Multilevel

          ## Cache Levels

          # Default auto-generated L1 cache (local)
          defmodule L1 do
            use Nebulex.Cache,
              otp_app: :nebulex,
              adapter: Nebulex.Adapters.Local
          end

          # Default auto-generated L2 cache (partitioned cache)
          defmodule L2 do
            use Nebulex.Cache,
              otp_app: :nebulex,
              adapter: Nebulex.Adapters.Partitioned
          end

          ## TODO: Add, remove or modify the auto-generated cache levels above
        end
        """)

        first_line = if Code.ensure_loaded?(Config), do: "import Config", else: "use Mix.Config"

        assert_file("config/config.exs", """
        #{first_line}

        config :nebulex, MultilevelCache,
          model: :inclusive,
          levels: [
            # Default auto-generated L1 cache (local)
            {
              MultilevelCache.L1,
              # GC interval for pushing new generation: 12 hrs
              gc_interval: :timer.hours(12),
              # Max 1 million entries in cache
              max_size: 1_000_000
            },
            # Default auto-generated L2 cache (partitioned cache)
            {
              MultilevelCache.L2,
              primary: [
                # GC interval for pushing new generation: 12 hrs
                gc_interval: :timer.hours(12),
                # Max 1 million entries in cache
                max_size: 1_000_000
              ]
            }
          ]
        """)
      end)
    end
  end

  ## Private Functions

  @tmp_path Path.expand("../../../tmp", __DIR__)

  defp in_tmp(path, fun) do
    path = Path.join(@tmp_path, path)
    File.rm_rf!(path)
    File.mkdir_p!(path)
    File.cd!(path, fun)
  end

  defp assert_file(file, match) do
    assert File.read!(file) =~ match
  end
end
