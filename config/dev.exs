use Mix.Config

config :nebulex, Nebulex.TestCache.DistLocal, gc_interval: 3600

config :nebulex, Nebulex.TestCache.Dist, local: Nebulex.TestCache.DistLocal
