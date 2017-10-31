Enum.each Path.wildcard("bench/tasks/*.exs"), &Code.require_file/1

defmodule Nebulex.Mixfile do
  use Mix.Project

  @version "1.0.0-rc.3"

  def project do
    [
      app: :nebulex,
      version: @version,
      elixir: "~> 1.3",
      deps: deps(),

      # Docs
      name: "Nebulex",
      docs: docs(),

      # Testing
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: ["coveralls": :test, "coveralls.detail": :test, "coveralls.post": :test, "coveralls.html": :test],

      # Dialyzer
      dialyzer: dialyzer(),

      # Hex
      package: package(),
      description: "Fast, flexible and powerful cache wrapper for Elixir"
    ]
  end

  def application do
    [
      applications: []
    ]
  end

  defp deps do
    [
      {:ex_shards, "~> 0.2"},

      # Test
      {:excoveralls, "~> 0.6", only: :test},
      {:mock, "~> 0.2", only: :test},
      {:benchfella, "~> 0.3", optional: true, only: [:dev, :test]},

      # Code Analysis
      {:dialyxir, "~> 0.5", only: :dev, runtime: false},
      {:credo, "~> 0.7", only: [:dev, :test]},

      # Docs
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false},
      {:inch_ex, "~> 0.5", only: :docs}
    ]
  end

  defp package do
    [
      name: :nebulex,
      maintainers: ["Carlos A Bolanos"],
      licenses: ["MIT"],
      links: %{github: "https://github.com/cabol/nebulex"}
    ]
  end

  defp docs do
    [
      main: "Nebulex",
      source_ref: "v#{@version}",
      canonical: "http://hexdocs.pm/nebulex",
      source_url: "https://github.com/cabol/nebulex",
      extras: ["guides/Getting Started.md", "guides/Hooks.md"]
    ]
  end

  defp dialyzer do
    [
      plt_add_apps: [:ex_shards, :mix, :eex],
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
