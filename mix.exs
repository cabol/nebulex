defmodule Nebulex.MixProject do
  use Mix.Project

  @source_url "https://github.com/cabol/nebulex"
  @version "3.0.0-dev"

  def project do
    [
      app: :nebulex,
      version: @version,
      elixir: "~> 1.11",
      elixirc_paths: elixirc_paths(Mix.env()),
      aliases: aliases(),
      deps: deps(),

      # Testing
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        check: :test,
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test
      ],

      # Dialyzer
      dialyzer: dialyzer(),

      # Hex
      description: "In-memory and distributed caching toolkit for Elixir",
      package: package(),

      # Docs
      name: "Nebulex",
      docs: docs()
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/dialyzer"]
  defp elixirc_paths(_), do: ["lib"]

  def application do
    [
      extra_applications: [:eex],
      mod: {Nebulex.Application, []}
    ]
  end

  defp deps do
    [
      {:nimble_options, "~> 0.5"},
      {:decorator, "~> 1.4", optional: true},
      {:telemetry, "~> 1.2", optional: true},

      # Test & Code Analysis
      {:excoveralls, "~> 0.15", only: :test},
      {:credo, "~> 1.6", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.2", only: [:dev, :test], runtime: false},
      {:sobelow, "~> 0.11", only: [:dev, :test], runtime: false},
      {:stream_data, "~> 0.5", only: [:dev, :test]},
      {:mimic, "~> 1.7", only: :test},

      # Benchmark Test
      {:benchee, "~> 1.1", only: [:dev, :test]},
      {:benchee_html, "~> 1.0", only: [:dev, :test]},

      # Docs
      {:ex_doc, "~> 0.29", only: [:dev, :test], runtime: false},
      {:inch_ex, "~> 2.0", only: :docs}
    ]
  end

  defp aliases do
    [
      check: [
        "compile --warnings-as-errors",
        "format --check-formatted",
        "credo --strict",
        "coveralls.html",
        "sobelow --exit --skip",
        "dialyzer --format short"
      ]
    ]
  end

  defp package do
    [
      name: :nebulex,
      maintainers: ["Carlos Bolanos"],
      licenses: ["MIT"],
      links: %{
        "Changelog" => "#{@source_url}/blob/master/CHANGELOG.md",
        "GitHub" => @source_url
      }
    ]
  end

  defp docs do
    [
      main: "Nebulex",
      source_ref: "v#{@version}",
      canonical: "http://hexdocs.pm/nebulex",
      source_url: @source_url,
      extras: [
        "guides/getting-started.md",
        "guides/cache-usage-patterns.md",
        "guides/telemetry.md",
        "guides/migrating-to-v2.md",
        "guides/creating-new-adapter.md"
      ],
      groups_for_functions: [
        # Caching decorators
        group_for_function("Decorator API"),
        group_for_function("Internal API"),
        # Cache API
        group_for_function("User callbacks"),
        group_for_function("Runtime API"),
        group_for_function("Entry API"),
        group_for_function("Query API"),
        group_for_function("Persistence API"),
        group_for_function("Transaction API"),
        group_for_function("Stats API")
      ]
    ]
  end

  defp group_for_function(group), do: {String.to_atom(group), &(&1[:group] == group)}

  defp dialyzer do
    [
      plt_add_apps: [:mix, :telemetry, :ex_unit],
      plt_file: {:no_warn, "priv/plts/" <> plt_file_name()},
      flags: [
        :unmatched_returns,
        :error_handling,
        :no_opaque,
        :unknown,
        :no_return
      ]
    ]
  end

  defp plt_file_name do
    "dialyzer-#{Mix.env()}-#{System.otp_release()}-#{System.version()}.plt"
  end
end
