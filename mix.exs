defmodule Nebulex.MixProject do
  use Mix.Project

  @source_url "https://github.com/cabol/nebulex"
  @version "2.6.4"

  def project do
    [
      app: :nebulex,
      version: @version,
      elixir: "~> 1.12",
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

  defp elixirc_paths(:test), do: ["lib", "test/support", "test/dialyzer"]
  defp elixirc_paths(_), do: ["lib"]

  def application do
    [
      extra_applications: [:eex],
      mod: {Nebulex.Application, []}
    ]
  end

  defp deps do
    [
      {:shards, "~> 1.1", optional: true},
      {:decorator, "~> 1.4", optional: true},
      {:telemetry, "~> 0.4 or ~> 1.0", optional: true},

      # Test & Code Analysis
      {:ex2ms, "~> 1.6", only: :test},
      {:mock, "~> 0.3", only: :test},
      {:excoveralls, "~> 0.18", only: :test},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:sobelow, "~> 0.13", only: [:dev, :test], runtime: false},
      {:stream_data, "~> 1.1", only: [:dev, :test]},
      {:doctor, "~> 0.21", only: [:dev, :test]},

      # Benchmark Test
      {:benchee, "~> 1.3", only: [:dev, :test]},
      {:benchee_html, "~> 1.0", only: [:dev, :test]},

      # Docs
      {:ex_doc, "~> 0.34", only: [:dev, :test], runtime: false}
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
        "dialyzer --format short",
        "doctor"
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
