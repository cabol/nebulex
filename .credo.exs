%{
  configs: [
    %{
      name: "default",
      files: %{
        included: ["lib/", "src/", "test/", "benchmarks/"],
        excluded: [~r"/_build/", ~r"/deps/"]
      },
      color: true,
      checks: [
        ## Design Checks
        {Credo.Check.Design.AliasUsage, priority: :low},

        ## Readability Checks
        {Credo.Check.Readability.MaxLineLength, priority: :low, max_length: 100},

        ## Refactoring Opportunities
        {Credo.Check.Refactor.LongQuoteBlocks, false}
      ]
    }
  ]
}
