[
  parallel: false,

  tools: [
    {:credo, "mix credo --strict --format oneline", order: 1},
    {:excoveralls, "mix coveralls.github", order: 2},
    {:sobelow, "mix sobelow --exit --skip", order: 3},
    {:dialyzer, "mix dialyzer --format short", order: 4}
  ]
]
