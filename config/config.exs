use Mix.Config

config :nebulex,
  nodes: [:"node1@127.0.0.1", :"node2@127.0.0.1"]

import_config "#{Mix.env()}.exs"
