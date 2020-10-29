defmodule Nebulex.MixProject do
  use Mix.Project

  @source_url "https://github.com/cabol/nebulex"
  @version "2.0.0-rc.0"

  def project do
    [
      app: :nebulex,
      version: @version,
      elixir: "~> 1.9",
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),

      # Docs
      name: "Nebulex",
      docs: docs(),

      # Testing
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test,
        check: :test,
        credo: :test,
        dialyzer: :test,
        sobelow: :test
      ],

      # Dialyzer
      dialyzer: dialyzer(),

      # Hex
      package: package(),
      description: """
      In-Process and Distributed Caching Toolkit for Elixir. Easily craft and
      deploy distributed cache topologies and different cache usage patterns.
      """
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  def application do
    [
      mod: {Nebulex.Application, []}
    ]
  end

  defp deps do
    [
      {:shards, "~> 1.0", optional: true},
      {:decorator, "~> 1.3", optional: true},
      {:telemetry, "~> 0.4", optional: true},

      # Test & Code Analysis
      {:ex2ms, "~> 1.6", only: :test},
      {:mock, "~> 0.3", only: :test},
      {:benchee, "~> 1.0", only: :test},
      {:benchee_html, "~> 1.0", only: :test},
      {:excoveralls, "~> 0.13", only: :test},
      {:dialyxir, "~> 1.0", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.4", only: [:dev, :test]},
      {:ex_check, "~> 0.12", only: [:dev, :test], runtime: false},
      {:sobelow, "~> 0.10", only: [:dev, :test], runtime: false},

      # Docs
      {:ex_doc, "~> 0.23", only: [:dev, :test], runtime: false},
      {:inch_ex, "~> 2.0", only: :docs}
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
      plt_add_apps: [:shards, :mix, :eex, :telemetry],
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
