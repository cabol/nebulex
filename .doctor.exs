%Doctor.Config{
  ignore_modules: [
    Nebulex.Adapter,
    Nebulex.Adapters.Local.Metadata,
    Nebulex.Adapters.Partitioned.Bootstrap,
    Nebulex.Helpers,
    Nebulex.Telemetry,
    Nebulex.Cluster,
    Nebulex.NodeCase,
    Nebulex.TestCache.Common,
    Nebulex.Dialyzer.CachingDecorators
  ],
  ignore_paths: [],
  min_module_doc_coverage: 30,
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
