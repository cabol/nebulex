defmodule Nebulex.Mixfile do
  use Mix.Project

  @version "1.0.0-dev"

  def project do
    [app: :nebulex,
     version: @version,
     elixir: "~> 1.3",
     deps: deps(),
     package: package(),
     docs: docs(),
     test_coverage: [tool: ExCoveralls],
     preferred_cli_env: ["coveralls": :test, "coveralls.detail": :test, "coveralls.post": :test, "coveralls.html": :test],
     dialyzer: dialyzer(),
     description: "Local and Distributed Caching Tool for Elixir"]
  end

  def application do
    case Mix.env() do
      :test -> [applications: [:unicode_util_compat]] # fix coveralls.travis issue (because hackney dep)
      _     -> [applications: []]
    end
  end

  defp deps do
    [{:ex_shards, "~> 0.2"},

     # Test
     {:excoveralls, "~> 0.6", only: :test},
     {:mock, "~> 0.2", only: :test},

     # Code Analysis
     {:dialyxir, "~> 0.5", only: :dev, runtime: false},
     {:credo, "~> 0.7", only: [:dev, :test]},

     # Docs
     {:ex_doc, ">= 0.0.0", only: :dev, runtime: false},
     {:inch_ex, "~> 0.5", only: :docs}]
  end

  defp package do
    [name: :nebulex,
     maintainers: ["Carlos A Bolanos"],
     licenses: ["MIT"],
     links: %{github: "https://github.com/cabol/nebulex"}]
  end

  defp docs do
    [source_ref: "v#{@version}", main: "Nebulex",
     canonical: "http://hexdocs.pm/nebulex",
     source_url: "https://github.com/cabol/nebulex",
     extras: ["guides/Getting Started.md"]]
  end

  defp dialyzer do
    [plt_add_apps: [:ex_shards, :mix, :eex],
     flags: [:unmatched_returns, :error_handling, :race_conditions, :no_opaque]]
  end
end
