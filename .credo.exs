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
        # Readability Checks
        {Credo.Check.Readability.MaxLineLength, priority: :low, max_length: 100},

        # Refactoring Opportunities
        {Credo.Check.Refactor.LongQuoteBlocks, false},

        # TODO and FIXME do not cause the build to fail
        {Credo.Check.Design.TagTODO, exit_status: 0},
        {Credo.Check.Design.TagFIXME, exit_status: 0}
      ]
    }
  ]
}
