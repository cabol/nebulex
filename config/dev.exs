use Mix.Config

config :nebulex, Nebulex.TestCache.Partitioned.Primary, gc_interval: 3600

config :nebulex, Nebulex.TestCache.Partitioned, primary: Nebulex.TestCache.Partitioned.Primary
