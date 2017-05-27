defmodule Mix.Tasks.Nebulex.Gen.Cache do
  use Mix.Task

  import Mix.Nebulex
  import Mix.Generator

  @shortdoc "Generates a new cache"

  @moduledoc """
  Generates a new cache.

  The cache will be placed in the `lib` directory.

  ## Examples

      mix nebulex.gen.cache -c Custom.Cache -a Nebulex.Adapters.Local

  ## Command line options

    * `-c`, `--cache` - the cache to generate
    * `-a`, `--adapter` - the cache adapter to use (optional)
  """

  @doc false
  def run(args) do
    no_umbrella!("nebulex.gen.cache")
    switches = [cache: :atom, adapter: :adapter]
    aliases = [c: :cache, a: :adapter]

    {parsed, _, _} = OptionParser.parse(args, switches: switches, aliases: aliases)

    unless cache_str = parsed[:cache] do
      Mix.raise "nebulex.gen.cache expects the cache to be given as -c MyApp.Cache"
    end

    cache = Module.concat([cache_str])
    adapter = Module.concat([parsed[:adapter] || Nebulex.Adapters.Local])

    config      = Mix.Project.config
    underscored = Macro.underscore(inspect(cache))

    base = Path.basename(underscored)
    file = Path.join("lib", underscored) <> ".ex"
    app  = config[:app] || :YOUR_APP_NAME
    opts = %{mod: cache, adapter: adapter, app: app, base: base}

    create_directory Path.dirname(file)
    create_file file, cache_template(opts)

    case File.read "config/config.exs" do
      {:ok, contents} ->
        Mix.shell.info [:green, "* updating ", :reset, "config/config.exs"]
        File.write! "config/config.exs",
                    String.replace(contents, "use Mix.Config", config_template(opts))
      {:error, _} ->
        create_file "config/config.exs", config_template(opts)
    end

    Mix.shell.info """
    Don't forget to add your new cache to your supervision tree
    (typically in #{mixfile_loc(app)}):

        supervisor(#{inspect cache}, [])

    And for more information about cache config options, check the adapter
    documentation and Nebulex.Cache shared options.
    """
  end

  defp mixfile_loc(app) do
    case Elixir.Version.compare(System.version, "1.4.0") do
      :lt -> "lib/#{app}.ex"
      _   -> "lib/#{app}/application.ex" # greater or equal than
    end
  end

  embed_template :cache, """
  defmodule <%= inspect @mod %> do
    use Nebulex.Cache, otp_app: <%= inspect @app %>
  end
  """

  embed_template :config, """
  use Mix.Config

  config <%= inspect @app %>, <%= inspect @mod %>,
    adapter: <%= inspect @adapter %>
  """
end
