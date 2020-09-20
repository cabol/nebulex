[
  parallel: false,

  tools: [
    {:credo, "mix credo --strict --format oneline", order: 1, env: %{"MIX_ENV" => "test"}},
    {:excoveralls, "mix coveralls.github", order: 2},
    {:sobelow, "mix sobelow --exit --skip", order: 3, env: %{"MIX_ENV" => "test"}},
    {:dialyzer, "mix dialyzer --format short", order: 4, env: %{"MIX_ENV" => "test"}}
  ]
]
