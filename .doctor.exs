%Doctor.Config{
  ignore_modules: [
    Nebulex.Cache.Impl,
    Nebulex.Cache.Options,
    Nebulex.Cache.QuerySpec,
    Nebulex.Caching.Options,
    Nebulex.Adapter.Transaction.Options,
    Nebulex.Adapters.Nil.Options,
    Nebulex.Dialyzer.CachingDecorators
  ],
  ignore_paths: [],
  min_module_doc_coverage: 40,
  min_module_spec_coverage: 0,
  min_overall_doc_coverage: 80,
  min_overall_moduledoc_coverage: 100,
  min_overall_spec_coverage: 0,
  exception_moduledoc_required: true,
  raise: false,
  reporter: Doctor.Reporters.Full,
  struct_type_spec_required: true,
  umbrella: false,
  failed: false
}
