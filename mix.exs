defmodule Nebulex.MixProject do
  use Mix.Project

  @source_url "https://github.com/cabol/nebulex"
  @version "2.1.0-dev"

  def project do
    [
      app: :nebulex,
      version: @version,
      elixir: "~> 1.9",
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

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  def application do
    [
      extra_applications: [:eex],
      mod: {Nebulex.Application, []}
    ]
  end

  defp deps do
    [
      {:shards, "~> 1.0", optional: true},
      {:decorator, "~> 1.4", optional: true},
      {:telemetry, "~> 0.4", optional: true},

      # Test & Code Analysis
      {:ex2ms, "~> 1.6", only: :test},
      {:mock, "~> 0.3", only: :test},
      {:excoveralls, "~> 0.13", only: :test},
      {:credo, "~> 1.5", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.0", only: [:dev, :test], runtime: false},
      {:sobelow, "~> 0.11", only: [:dev, :test], runtime: false},
      {:stream_data, "~> 0.5", only: [:dev, :test]},

      # Benchmark Test
      {:benchee, "~> 1.0", only: :test},
      {:benchee_html, "~> 1.0", only: :test},

      # Docs
      {:ex_doc, "~> 0.23", only: [:dev, :test], runtime: false},
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
        "guides/migrating-to-v2.md"
      ]
    ]
  end

  defp dialyzer do
    [
      plt_add_apps: [:shards, :mix, :telemetry],
      plt_file: {:no_warn, "priv/plts/" <> plt_file_name()},
      flags: [
        :unmatched_returns,
        :error_handling,
        :race_conditions,
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
