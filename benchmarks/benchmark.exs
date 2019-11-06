## Benchmarks

:ok = Application.put_env(:nebulex, :nodes, [:"node1@127.0.0.1", :"node2@127.0.0.1"])

required_files =
  for file <- File.ls!("test/support") do
    {file, Code.require_file("../test/support/" <> file, __DIR__)}
  end

nodes = Keyword.values(Nebulex.Cluster.spawn())

Enum.each(required_files, fn {file, loaded} ->
  Enum.each(loaded, fn {mod, bin} ->
    expected = List.duplicate({:module, mod}, length(nodes))

    {^expected, []} =
      :rpc.multicall(
        nodes,
        :code,
        :load_binary,
        [mod, to_charlist(file), bin]
      )
  end)
end)

alias Nebulex.NodeCase
alias Nebulex.TestCache.{Dist, Local}
alias Nebulex.TestCache.Dist.Local, as: DistLocal

# start caches
{:ok, local} = Local.start_link()
{:ok, primary} = DistLocal.start_link()
{:ok, dist} = Dist.start_link()
node_pid_list = NodeCase.start_caches(Node.list(), [DistLocal, Dist])

# samples
keys = Enum.to_list(1..10_000)
bulk = for x <- 1..100, do: {x, x}

# init caches
Enum.each(1..5000, fn x ->
  Local.set(x, x)
  Dist.set(x, x)
end)

inputs = %{
  "Generational Local Cache" => Local,
  "Distributed Cache" => Dist
}

benchmarks = %{
  "get" => fn {cache, random} ->
    cache.get(random)
  end,
  "set" => fn {cache, random} ->
    cache.set(random, random)
  end,
  "add" => fn {cache, random} ->
    cache.add(random, random)
  end,
  "replace" => fn {cache, random} ->
    cache.replace(random, random)
  end,
  "add_or_replace!" => fn {cache, random} ->
    cache.add_or_replace!(random, random)
  end,
  "get_many" => fn {cache, _random} ->
    cache.get_many(1..10)
  end,
  "set_many" => fn {cache, _random} ->
    cache.set_many(bulk)
  end,
  "delete" => fn {cache, random} ->
    cache.delete(random)
  end,
  "take" => fn {cache, random} ->
    cache.take(random)
  end,
  "has_key?" => fn {cache, random} ->
    cache.has_key?(random)
  end,
  "size" => fn {cache, _random} ->
    cache.size()
  end,
  "object_info" => fn {cache, random} ->
    cache.object_info(random, :ttl)
  end,
  "expire" => fn {cache, random} ->
    cache.expire(random, 1)
  end,
  "get_and_update" => fn {cache, random} ->
    cache.get_and_update(random, &Dist.get_and_update_fun/1)
  end,
  "update" => fn {cache, random} ->
    cache.update(random, 1, &Kernel.+(&1, 1))
  end,
  "update_counter" => fn {cache, _random} ->
    cache.update_counter(:counter, 1)
  end,
  "all" => fn {cache, _random} ->
    cache.all()
  end,
  "transaction" => fn {cache, random} ->
    cache.transaction(
      fn ->
        cache.update_counter(random, 1)
        :ok
      end,
      keys: [random]
    )
  end
}

Benchee.run(
  benchmarks,
  inputs: inputs,
  before_scenario: fn cache ->
    {cache, Enum.random(keys)}
  end,
  formatters: [
    {Benchee.Formatters.Console, comparison: false, extended_statistics: true},
    {Benchee.Formatters.HTML, extended_statistics: true}
  ],
  print: [
    fast_warning: false
  ]
)

# stop caches s
if Process.alive?(local), do: Local.stop(local)
if Process.alive?(primary), do: DistLocal.stop(primary)
if Process.alive?(dist), do: Dist.stop(dist)
NodeCase.stop_caches(node_pid_list)
