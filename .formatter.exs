locals_without_parens = [
  # Nebulex.Utils
  unwrap_or_raise: 1,
  wrap_ok: 1,
  wrap_error: 1,
  wrap_error: 2,

  # Nebulex.Cache.Utils
  defcacheapi: 2,

  # Nebulex.Adapter
  defcommand: 1,
  defcommand: 2,
  defcommandp: 1,
  defcommandp: 2,

  # Nebulex.Caching
  dynamic_cache: 2,
  keyref: 1,
  keyref: 2,

  # Tests
  deftests: 1,
  deftests: 2,
  setup_with_cache: 1,
  setup_with_cache: 2,
  setup_with_dynamic_cache: 2,
  setup_with_dynamic_cache: 3,
  with_telemetry_handler: 2,
  with_telemetry_handler: 3,
  wait_until: 1,
  wait_until: 2,
  wait_until: 3,
  assert_error_module: 2,
  assert_error_reason: 2
]

[
  import_deps: [:stream_data],
  inputs: ["{mix,.formatter}.exs", "{config,lib,test,benchmarks}/**/*.{ex,exs}"],
  line_length: 100,
  locals_without_parens: locals_without_parens,
  export: [locals_without_parens: locals_without_parens]
]
