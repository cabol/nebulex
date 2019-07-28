use Mix.Config

config :nebulex, Nebulex.TestCache.Local, version_generator: Nebulex.Version.Timestamp

config :nebulex, Nebulex.TestCache.CacheStats, stats: true

config :nebulex, Nebulex.TestCache.LocalWithGC,
  version_generator: Nebulex.Version.Timestamp,
  gc_interval: 1,
  n_generations: 3

config :nebulex, Nebulex.TestCache.LocalWithSizeLimit,
  version_generator: Nebulex.Version.Timestamp,
  gc_interval: 3600,
  n_generations: 3,
  generation_size: 100_000,
  gc_cleanup_interval: 2

config :nebulex, Nebulex.TestCache.DistLocal,
  version_generator: Nebulex.Version.Timestamp,
  gc_interval: 3600

config :nebulex, Nebulex.TestCache.Dist,
  local: Nebulex.TestCache.DistLocal,
  version_generator: Nebulex.Version.Timestamp
