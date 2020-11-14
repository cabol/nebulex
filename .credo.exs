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
        # Design Checks
        {Credo.Check.Design.AliasUsage, priority: :low},

        # Deactivate due to they're not compatible with current Elixir version
        {Credo.Check.Refactor.MapInto, false},
        {Credo.Check.Warning.LazyLogging, false},

        # Readability Checks
        {Credo.Check.Readability.MaxLineLength, priority: :low, max_length: 100},

        # Refactoring Opportunities
        {Credo.Check.Refactor.LongQuoteBlocks, false},
        {Credo.Check.Refactor.CyclomaticComplexity, max_complexity: 15},

        # TODO and FIXME do not cause the build to fail
        {Credo.Check.Design.TagTODO, exit_status: 0},
        {Credo.Check.Design.TagFIXME, exit_status: 0}
      ]
    }
  ]
}
