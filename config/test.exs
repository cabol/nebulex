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
