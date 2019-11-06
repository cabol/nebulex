# Set nodes
:ok = Application.put_env(:nebulex, :nodes, [:"node1@127.0.0.1", :"node2@127.0.0.1"])

# Load support files
required_files =
  for file <- File.ls!("test/support") do
    {file, Code.require_file("./support/" <> file, __DIR__)}
  end

# Load shared tests
for file <- File.ls!("test/shared/cache") do
  Code.require_file("./shared/cache/" <> file, __DIR__)
end

for file <- File.ls!("test/shared"), not File.dir?("test/shared/" <> file) do
  Code.require_file("./shared/" <> file, __DIR__)
end

# Spawn remote nodes and load support files on them if clustered is present
unless :clustered in Keyword.get(ExUnit.configuration(), :exclude, []) do
  nodes = Keyword.values(Nebulex.Cluster.spawn())

  Enum.each(required_files, fn {file, loaded} ->
    Enum.each(loaded, fn {mod, bin} ->
      expected = List.duplicate({:module, mod}, length(nodes))
      {^expected, []} = :rpc.multicall(nodes, :code, :load_binary, [mod, to_charlist(file), bin])
    end)
  end)
end

# For tasks/generators testing
Mix.start()
Mix.shell(Mix.Shell.Process)

# Start ExUnit
ExUnit.start()
