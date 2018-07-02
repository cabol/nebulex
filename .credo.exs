%{
  configs: [
    %{
      name: "default",
      files: %{
        included: ["lib/", "src/", "test/", "web/", "apps/"],
        excluded: [~r"/_build/", ~r"/deps/"]
      },
      color: true,
      checks: [
        ## Design Checks
        {Credo.Check.Design.AliasUsage, priority: :low},

        ## Readability Checks
        {Credo.Check.Readability.MaxLineLength, priority: :low, max_length: 110},

        ## Refactoring Opportunities
        {Credo.Check.Refactor.LongQuoteBlocks, false}
      ]
    }
  ]
}
