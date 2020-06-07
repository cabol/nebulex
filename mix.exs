defmodule Nebulex.Mixfile do
  use Mix.Project

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
        "coveralls.html": :test
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
      {:shards, "~> 0.6", optional: true},
      {:decorator, "~> 1.3", optional: true},

      # Test
      {:excoveralls, "~> 0.13", only: :test},
      {:ex2ms, "~> 1.6", only: :test},
      {:mock, "~> 0.3", only: :test},
      {:benchee, "~> 1.0", optional: true, only: :test},
      {:benchee_html, "~> 1.0", optional: true, only: :test},

      # Code Analysis
      {:dialyxir, "~> 1.0", optional: true, only: [:dev, :test], runtime: false},
      {:credo, "~> 1.4", optional: true, only: [:dev, :test]},

      # Docs
      {:ex_doc, "~> 0.22", only: :dev, runtime: false},
      {:inch_ex, "~> 2.0", only: :docs}
    ]
  end

  defp package do
    [
      name: :nebulex,
      maintainers: ["Carlos Bolanos"],
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/cabol/nebulex"}
    ]
  end

  defp docs do
    [
      main: "Nebulex",
      source_ref: "v#{@version}",
      canonical: "http://hexdocs.pm/nebulex",
      source_url: "https://github.com/cabol/nebulex",
      extras: [
        "guides/getting-started.md",
        "guides/cache-usage-patterns.md"
      ]
    ]
  end

  defp dialyzer do
    [
      plt_add_apps: [:shards, :mix, :eex, :logger],
      plt_file: {:no_warn, "priv/plts/dialyzer-#{Mix.env()}.plt"},
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
end
