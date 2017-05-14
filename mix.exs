defmodule Nebulex.Mixfile do
  use Mix.Project

  def project do
    [app: :nebulex,
     version: "0.1.0",
     elixir: "~> 1.3",
     deps: deps(),
     package: package(),
     test_coverage: [tool: ExCoveralls],
     preferred_cli_env: ["coveralls": :test, "coveralls.detail": :test, "coveralls.post": :test, "coveralls.html": :test],
     dialyzer: dialyzer(),
     description: "Distributed and Local Caching Library"]
  end

  def application do
    [applications: []]
  end

  defp deps do
    [{:ex_shards, "~> 0.2"},

     # Coverage
     {:excoveralls, "~> 0.6", only: :test},

     # Dialyzer
     {:dialyxir, "~> 0.5", only: :dev, runtime: false},

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

  defp dialyzer do
    [plt_add_apps: [:ex_shards],
     flags: [:unmatched_returns, :error_handling, :race_conditions, :no_opaque]]
  end
end
