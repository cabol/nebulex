defmodule Mix.Tasks.Nbx.Gen.Cache do
  @shortdoc "Generates a new cache"

  @moduledoc """
  Generates a new cache.

  The cache will be placed in the `lib` directory.

  For generating a cache with the config, you can run:

      mix nbx.gen.cache -c MyApp.Cache

  Besides, you can also specify the adapter you want to use, like so:

      mix nbx.gen.cache -c MyApp.LocalCache -a Nebulex.Adapters.Local
      mix nbx.gen.cache -c MyApp.PartitionedCache -a Nebulex.Adapters.Partitioned
      mix nbx.gen.cache -c MyApp.ReplicatedCache -a Nebulex.Adapters.Replicated
      mix nbx.gen.cache -c MyApp.MultilevelCache -a Nebulex.Adapters.Multilevel

  ## Command line options

    * `-c`, `--cache` - The cache to generate.

    * `-a`, `--adapter` - The cache adapter to use (optional).
      Defaults to `Nebulex.Adapters.Local`.

  """

  use Mix.Task

  import Mix.Nebulex
  import Mix.Generator

  alias Mix.Project

  @switches [
    cache: [:string, :keep],
    adapter: [:string, :keep]
  ]

  @aliases [
    c: :cache,
    a: :adapter
  ]

  @doc false
  def run(args) do
    no_umbrella!("nbx.gen.cache")
    {opts, _} = OptionParser.parse!(args, strict: @switches, aliases: @aliases)

    {cache, adapter} = get_cache_and_adapter(opts)

    config = Project.config()
    underscored = Macro.underscore(inspect(cache))

    base = Path.basename(underscored)
    file = Path.join("lib", underscored) <> ".ex"
    app = config[:app] || :YOUR_APP_NAME
    opts = [mod: cache, app: app, base: base, adapter: adapter]

    {cache_template, config_template} = resolve_template(opts)

    create_directory(Path.dirname(file))
    create_file(file, cache_template)
    config_path = config[:config_path] || "config/config.exs"

    case File.read(config_path) do
      {:ok, contents} ->
        check = String.contains?(contents, "import Config")
        config_first_line = get_first_config_line(check) <> "\n"
        new_contents = config_first_line <> "\n" <> config_template
        Mix.shell().info([:green, "* updating ", :reset, config_path])
        File.write!(config_path, String.replace(contents, config_first_line, new_contents))

      {:error, _} ->
        config_first_line = Config |> Code.ensure_loaded?() |> get_first_config_line()
        create_file(config_path, config_first_line <> "\n\n" <> config_template)
    end

    Mix.shell().info("""
    Don't forget to add your new cache to your supervision tree
    (typically in lib/#{app}/application.ex):

        {#{inspect(cache)}, []}

    """)
  end

  defp get_cache_and_adapter(opts) do
    cache =
      case Keyword.get_values(opts, :cache) do
        [] -> Mix.raise("nbx.gen.cache expects the cache to be given as -c MyApp.Cache")
        [cache] -> Module.concat([cache])
        [_ | _] -> Mix.raise("nbx.gen.cache expects a single cache to be given")
      end

    adapter =
      case Keyword.get_values(opts, :adapter) do
        [] -> Nebulex.Adapters.Local
        [adapter] -> Module.concat([adapter])
        [_ | _] -> Mix.raise("nbx.gen.cache expects a single adapter to be given")
      end

    {cache, adapter}
  end

  defp get_first_config_line(true), do: "import Config"
  defp get_first_config_line(false), do: "use Mix.Config"

  defp resolve_template(opts) do
    case opts[:adapter] do
      Nebulex.Adapters.Local ->
        {cache_template(opts), local_config_template(opts)}

      Nebulex.Adapters.Partitioned ->
        {dist_cache_template(opts), dist_config_template(opts)}

      Nebulex.Adapters.Replicated ->
        {dist_cache_template(opts), dist_config_template(opts)}

      Nebulex.Adapters.Multilevel ->
        {ml_cache_template(opts), ml_config_template(opts)}

      _ ->
        {cache_template(opts), config_template(opts)}
    end
  end

  embed_template(:cache, """
  defmodule <%= inspect @mod %> do
    use Nebulex.Cache,
      otp_app: <%= inspect @app %>,
      adapter: <%= inspect @adapter %>
  end
  """)

  embed_template(:dist_cache, """
  defmodule <%= inspect @mod %> do
    use Nebulex.Cache,
      otp_app: <%= inspect @app %>,
      adapter: <%= inspect @adapter %>,
      primary_storage_adapter: Nebulex.Adapters.Local
  end
  """)

  embed_template(:ml_cache, """
  defmodule <%= inspect @mod %> do
    use Nebulex.Cache,
      otp_app: <%= inspect @app %>,
      adapter: Nebulex.Adapters.Multilevel

    ## Cache Levels

    # Default auto-generated L1 cache (local)
    defmodule L1 do
      use Nebulex.Cache,
        otp_app: <%= inspect @app %>,
        adapter: Nebulex.Adapters.Local
    end

    # Default auto-generated L2 cache (partitioned cache)
    defmodule L2 do
      use Nebulex.Cache,
        otp_app: <%= inspect @app %>,
        adapter: Nebulex.Adapters.Partitioned
    end

    ## TODO: Add, remove or modify the auto-generated cache levels above
  end
  """)

  embed_template(:config, """
  # See the adapter's documentation for configuration options
  # config <%= inspect @app %>, <%= inspect @mod %>,
  #   key: :value
  """)

  embed_template(:local_config, """
  config <%= inspect @app %>, <%= inspect @mod %>,
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

  embed_template(:dist_config, """
  config <%= inspect @app %>, <%= inspect @mod %>,
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

  embed_template(:ml_config, """
  config <%= inspect @app %>, <%= inspect @mod %>,
    model: :inclusive,
    levels: [
      # Default auto-generated L1 cache (local)
      {
        <%= inspect @mod %>.L1,
        # GC interval for pushing new generation: 12 hrs
        gc_interval: :timer.hours(12),
        # Max 1 million entries in cache
        max_size: 1_000_000
      },
      # Default auto-generated L2 cache (partitioned cache)
      {
        <%= inspect @mod %>.L2,
        primary: [
          # GC interval for pushing new generation: 12 hrs
          gc_interval: :timer.hours(12),
          # Max 1 million entries in cache
          max_size: 1_000_000
        ]
      }
    ]
  """)
end
