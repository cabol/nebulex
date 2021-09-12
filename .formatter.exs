locals_without_parens = [
  # Nebulex.Helpers
  unwrap_or_raise: 1,
  wrap_ok: 1,
  wrap_error: 1,
  wrap_error: 2
]

[
  import_deps: [:stream_data],
  inputs: ["{mix,.formatter}.exs", "{config,lib,test,benchmarks}/**/*.{ex,exs}"],
  line_length: 100,
  locals_without_parens: locals_without_parens,
  export: [locals_without_parens: locals_without_parens]
]
