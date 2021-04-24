# Set nodes
nodes = [:"node1@127.0.0.1", :"node2@127.0.0.1", :"node3@127.0.0.1", :"node4@127.0.0.1"]
:ok = Application.put_env(:nebulex, :nodes, nodes)

# Load shared tests
for file <- File.ls!("test/shared/cache") do
  Code.require_file("./shared/cache/" <> file, __DIR__)
end

for file <- File.ls!("test/shared"), not File.dir?("test/shared/" <> file) do
  Code.require_file("./shared/" <> file, __DIR__)
end

# Spawn remote nodes
unless :clustered in Keyword.get(ExUnit.configuration(), :exclude, []) do
  Nebulex.Cluster.spawn(nodes)
end

# For mix tests
Mix.shell(Mix.Shell.Process)

# Start Telemetry
:ok = Application.start(:telemetry)

# Start ExUnit
ExUnit.start()
