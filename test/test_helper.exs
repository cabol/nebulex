# Load shared tests
Code.require_file "./shared/cache_test.exs", __DIR__
Code.require_file "./shared/multilevel_test.exs", __DIR__

# Load support files
required_files = for file <- File.ls!("test/support") do
  {file, Code.require_file("./support/" <> file, __DIR__)}
end

# Spawn remote nodes and load support files on them if clustered is present
unless :clustered in Keyword.get(ExUnit.configuration(), :exclude, []) do
  nodes = Keyword.values(Nebulex.Cluster.spawn())
  Enum.each(required_files, fn({file, loaded}) ->
    Enum.each(loaded, fn({mod, bin}) ->
      expected = List.duplicate({:module, mod}, length(nodes))
      {^expected, []} = :rpc.multicall(nodes, :code, :load_binary, [mod, to_char_list(file), bin])
    end)
  end)
end

# Start ExUnit
ExUnit.start()
