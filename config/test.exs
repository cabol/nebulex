use Mix.Config

config :nebulex,
  nodes: [:"node1@127.0.0.1", :"node2@127.0.0.1"]

config :nebulex, Nebulex.TestCache.Local,
  n_shards: 2

config :nebulex, Nebulex.TestCache.LocalWithGC,
  n_shards: 2,
  gc_interval: 3600

config :nebulex, Nebulex.TestCache.DistLocal,
  adapter: Nebulex.Adapters.Local,
  n_shards: 2,
  gc_interval: 3600

config :nebulex, Nebulex.TestCache.Dist,
  adapter: Nebulex.Adapters.Dist,
  local: Nebulex.TestCache.DistLocal

config :nebulex, Nebulex.TestCache.Multilevel,
  levels: [
    Nebulex.TestCache.Multilevel.L1,
    Nebulex.TestCache.Multilevel.L2,
    Nebulex.TestCache.Multilevel.L3
  ]

config :nebulex, Nebulex.TestCache.Multilevel.L1,
  n_shards: 2,
  gc_interval: 3600

config :nebulex, Nebulex.TestCache.Multilevel.L2,
  n_shards: 2,
  gc_interval: 3600

config :nebulex, Nebulex.TestCache.Multilevel.L3,
  n_shards: 2,
  gc_interval: 3600

config :nebulex, Nebulex.TestCache.MultilevelExclusive,
  cache_model: :exclusive,
  levels: [
    Nebulex.TestCache.MultilevelExclusive.L1,
    Nebulex.TestCache.MultilevelExclusive.L2,
    Nebulex.TestCache.MultilevelExclusive.L3
  ]

config :nebulex, Nebulex.TestCache.MultilevelExclusive.L1,
  n_shards: 2,
  gc_interval: 3600

config :nebulex, Nebulex.TestCache.MultilevelExclusive.L2,
  n_shards: 2,
  gc_interval: 3600

config :nebulex, Nebulex.TestCache.MultilevelExclusive.L3,
  n_shards: 2,
  gc_interval: 3600
