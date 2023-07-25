locals_without_parens = [
  # Nebulex.Caching
  keyref: 1,
  keyref: 2,

  # Tests
  deftests: 1,
  deftests: 2,
  setup_with_cache: 1,
  setup_with_cache: 2,
  setup_with_dynamic_cache: 2,
  setup_with_dynamic_cache: 3
]

[
  import_deps: [:stream_data],
  inputs: ["{mix,.formatter}.exs", "{config,lib,test,benchmarks}/**/*.{ex,exs}"],
  line_length: 100,
  locals_without_parens: locals_without_parens,
  export: [locals_without_parens: locals_without_parens]
]
