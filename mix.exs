defmodule Nebulex.Mixfile do
  use Mix.Project

  @version "1.1.1-dev"

  def project do
    [
      app: :nebulex,
      version: @version,
      elixir: "~> 1.8",
      deps: deps(),
      elixirc_options: [warnings_as_errors: System.get_env("CI") == "true"],

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
      description: "A fast, flexible and powerful distributed caching framework for Elixir."
    ]
  end

  def application do
    []
  end

  defp deps do
    [
      {:shards, "~> 0.6"},

      # Test
      {:excoveralls, "~> 0.11", only: :test},
      {:ex2ms, "~> 1.5", only: :test},
      {:mock, "~> 0.3", only: :test},
      {:benchee, "~> 1.0", optional: true, only: :dev},
      {:benchee_html, "~> 1.0", optional: true, only: :dev},

      # Code Analysis
      {:dialyxir, "~> 0.5", optional: true, only: [:dev, :test], runtime: false},
      {:credo, "~> 1.0", optional: true, only: [:dev, :test]},

      # Docs
      {:ex_doc, "~> 0.20", only: :dev, runtime: false},
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
        "guides/hooks.md",
        "guides/caching-dsl.md"
      ]
    ]
  end

  defp dialyzer do
    [
      plt_add_apps: [:shards, :mix, :eex],
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
